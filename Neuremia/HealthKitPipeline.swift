//
//  HealthKitPipeline.swift
//  Neuremia
//
//  Continuous biometric pipeline for Apple Health. Owns:
//   • Per-type HKQueryAnchor persistence (delta sync).
//   • HKObserverQuery registration for background delivery — the observer
//     completion handler is *always* invoked so iOS keeps waking the app.
//   • Rank-based sample deduplication (Watch > iPhone; manual entries dropped).
//   • Multi-day reconciliation between HK snapshots and diary check-ins.
//   • Signal-quality scoring based on source diversity + sample density.
//   • Authorization probing — reads that come back empty after auth are flagged
//     as "silently denied" so the UI can prompt the user to re-open Settings.
//
//  The pipeline is intentionally decoupled from the SwiftUI layer so it can
//  be exercised from AppDelegate on cold launch as well as from the diary UI.
//

import Foundation

#if canImport(HealthKit)
import HealthKit

// MARK: - Anchor persistence

/// Persists one HKQueryAnchor per HKSampleType identifier so anchored queries
/// can pull deltas across cold launches instead of re-scanning the entire store.
///
/// Marked `nonisolated` because it is called from HK's own background dispatch
/// queues (observer + anchored query callbacks). The underlying UserDefaults
/// operations are thread-safe.
nonisolated
enum HealthKitAnchorStore {
    private static let prefix = "neuremiaHKAnchor."

    static func load(for typeIdentifier: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: prefix + typeIdentifier) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    static func save(_ anchor: HKQueryAnchor, for typeIdentifier: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        UserDefaults.standard.set(data, forKey: prefix + typeIdentifier)
    }

    /// Wipes every stored anchor. Called on logout so the next user's first
    /// sync starts from a clean slate rather than inheriting deltas from the
    /// previous account.
    static func clearAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Source ranking

/// Ranks a sample's provenance so multiple devices (Watch + iPhone + manual)
/// reporting the same day can be deduplicated deterministically.
enum HealthKitSampleSourceRank: Int, Comparable {
    case manualEntry = -1
    case unknown = 0
    case iPhone = 1
    case watch = 3

    static func < (lhs: HealthKitSampleSourceRank, rhs: HealthKitSampleSourceRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func rank(_ sample: HKSample) -> HealthKitSampleSourceRank {
        if let wasUserEntered = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool, wasUserEntered {
            return .manualEntry
        }
        if let device = sample.device {
            let model = (device.model ?? "").lowercased()
            if model.contains("watch") { return .watch }
            if model.contains("iphone") { return .iPhone }
        }
        // Fall back to the bundle identifier of the writing source — Watch
        // samples routed through the iPhone often lose their HKDevice.
        let bundle = sample.sourceRevision.source.bundleIdentifier.lowercased()
        if bundle.contains("watch") { return .watch }
        if bundle.contains("iphone") || bundle.contains("com.apple.health") { return .iPhone }
        return .unknown
    }
}

// MARK: - Reconciliation

enum HealthKitReconciliationSeverity: String, Codable, Hashable {
    case ok
    case warn
    case critical
}

struct HealthKitReconciliationIssue: Codable, Hashable, Identifiable {
    let id: String
    let dayKey: String
    let severity: HealthKitReconciliationSeverity
    let message: String
}

struct HealthKitReconciliationReport: Codable, Hashable {
    var generatedAt: Date
    var daysReconciled: Int
    var issues: [HealthKitReconciliationIssue]

    static let empty = HealthKitReconciliationReport(generatedAt: .distantPast, daysReconciled: 0, issues: [])

    static func decode(from raw: String) -> HealthKitReconciliationReport {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HealthKitReconciliationReport.self, from: data) else {
            return .empty
        }
        return decoded
    }

    func encodedString() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    var criticalCount: Int { issues.filter { $0.severity == .critical }.count }
    var warnCount: Int { issues.filter { $0.severity == .warn }.count }
}

// MARK: - Permission snapshot

/// Per-type authorization state. Note that iOS deliberately does not expose
/// whether a *read* permission was denied — only sharing (write) status is
/// surfaced. We rely on empty probe queries as a soft signal instead.
struct HealthKitAuthorizationSnapshot: Codable, Hashable {
    var deniedShareTypes: [String] = []
    /// Types where authorization succeeded but a 30-day probe returned zero
    /// samples. That is not proof of denial (user may simply not have the
    /// data), but combined with a Watch/iPhone that we know is capable of
    /// producing it (e.g. steps), it's the strongest signal iOS gives us.
    var suspectedSilentDenials: [String] = []
    var lastCheckedAt: Date = .distantPast

    var hasIssues: Bool { !deniedShareTypes.isEmpty || !suspectedSilentDenials.isEmpty }
}

// MARK: - Quality metrics

/// Aggregated per-day signal quality inputs. Kept separate from
/// HealthKitDailySnapshot because the raw sample counts are only meaningful
/// for scoring, not for downstream clinical analysis.
struct HealthKitDailySignalMetrics {
    var heartRateSamples: Int = 0
    var restingHeartRateSamples: Int = 0
    var hrvSamples: Int = 0
    var stepSamples: Int = 0
    var hasWatchSource: Bool = false
    var hasSleepSample: Bool = false
    var hasEnergySample: Bool = false

    /// Returns 0…1. Weights favour source diversity (55%) and HR density
    /// (20%) because those are the two dimensions clinicians care about most
    /// when interpreting HRV / sleep trends.
    func score(sourceCount: Int) -> Double {
        let baseCoverage = min(Double(sourceCount) / 6.0, 1)
        let hrDensity = min(Double(heartRateSamples) / 24.0, 1)   // ≥1/hr = full credit
        let rhrDensity = min(Double(restingHeartRateSamples) / 1.0, 1)
        let hrvDensity = min(Double(hrvSamples) / 6.0, 1)         // Watch typically writes ~6/day
        let activityCoverage = stepSamples > 0 || hasEnergySample ? 0.08 : 0.0
        let sleepCoverage = hasSleepSample ? 0.10 : 0.0
        let watchBonus = hasWatchSource ? 0.15 : 0.0
        return min(baseCoverage * 0.42 + hrDensity * 0.16 + rhrDensity * 0.07 + hrvDensity * 0.12 + activityCoverage + sleepCoverage + watchBonus, 1)
    }
}

// MARK: - Public quality helpers

enum HealthKitPipelineQuality {
    /// De-dup samples for the same start/end window by preferring higher-ranked
    /// sources. Manual entries are dropped outright — for continuous monitoring
    /// we only trust device-generated data.
    static func dedupe(_ samples: [HKSample]) -> [HKSample] {
        var best: [String: HKSample] = [:]
        for sample in samples {
            let rank = HealthKitSampleSourceRank.rank(sample)
            if rank == .manualEntry { continue }
            let key = "\(sample.sampleType.identifier)|\(Int(sample.startDate.timeIntervalSince1970))|\(Int(sample.endDate.timeIntervalSince1970))"
            if let existing = best[key] {
                if HealthKitSampleSourceRank.rank(existing) < rank {
                    best[key] = sample
                }
            } else {
                best[key] = sample
            }
        }
        return Array(best.values)
    }

    /// Multi-day reconciliation between HK daily snapshots and diary check-ins.
    /// Produces a typed list of issues (ok/warn/critical) that the UI can render
    /// as an actionable checklist instead of a free-form status string.
    static func reconcile(
        snapshots: [HealthKitDailySnapshot],
        checkInsByDay: [String: (sleepHours: Double, hasEntry: Bool)]
    ) -> HealthKitReconciliationReport {
        var issues: [HealthKitReconciliationIssue] = []
        let generatedAt = Date()

        for snapshot in snapshots {
            let day = snapshot.dayKey
            let checkIn = checkInsByDay[day]

            if snapshot.qualityScore < 0.3 {
                issues.append(HealthKitReconciliationIssue(
                    id: "\(day)-signal",
                    dayKey: day,
                    severity: .critical,
                    message: "\(day): sinal insuficiente (qualidade \(Int(snapshot.qualityScore * 100))%). Verifique se o iPhone/Watch registrou o dia."
                ))
            } else if snapshot.qualityScore < 0.55 {
                issues.append(HealthKitReconciliationIssue(
                    id: "\(day)-signal",
                    dayKey: day,
                    severity: .warn,
                    message: "\(day): qualidade parcial (\(Int(snapshot.qualityScore * 100))%). Sensores incompletos."
                ))
            }

            guard let checkIn = checkIn, checkIn.hasEntry else {
                // Missing diary entry isn't an HK failure — skip silently.
                continue
            }

            if snapshot.sleepHours > 0 && checkIn.sleepHours > 0 {
                let delta = abs(snapshot.sleepHours - checkIn.sleepHours)
                if delta >= 2.5 {
                    issues.append(HealthKitReconciliationIssue(
                        id: "\(day)-sleep-critical",
                        dayKey: day,
                        severity: .critical,
                        message: "\(day): divergência de sono \(String(format: "%.1f", delta))h entre Apple Health e diário."
                    ))
                } else if delta >= 1.0 {
                    issues.append(HealthKitReconciliationIssue(
                        id: "\(day)-sleep-warn",
                        dayKey: day,
                        severity: .warn,
                        message: "\(day): sono difere do diário em \(String(format: "%.1f", delta))h."
                    ))
                }
            } else if snapshot.sleepHours == 0 && checkIn.sleepHours > 0 {
                issues.append(HealthKitReconciliationIssue(
                    id: "\(day)-sleep-missing",
                    dayKey: day,
                    severity: .warn,
                    message: "\(day): diário reporta sono, mas Apple Health não recebeu amostras."
                ))
            }
        }

        return HealthKitReconciliationReport(
            generatedAt: generatedAt,
            daysReconciled: snapshots.count,
            issues: issues.sorted { lhs, rhs in
                if lhs.severity == rhs.severity { return lhs.dayKey > rhs.dayKey }
                return lhs.severity == .critical
            }
        )
    }
}

// MARK: - Observer controller

/// Owns the long-running HKObserverQuery lifetime for each sample type.
/// Registration is idempotent: calling `registerObservers` twice with the
/// same type is a no-op. All handler execution goes through `Task { … }` so
/// callers can safely be @MainActor while the HK callback stays on its own
/// dispatch queue.
actor HealthKitPipelineController {
    static let shared = HealthKitPipelineController()

    typealias DeltaHandler = @Sendable (_ samples: [HKSample], _ type: HKSampleType) async -> Void

    private var observerQueries: [String: HKObserverQuery] = [:]

    /// Register observer queries for each provided sample type. When HK
    /// invokes the observer (foreground or background), the controller pulls
    /// a delta via HKAnchoredObjectQuery, forwards new samples to
    /// `deltaHandler`, then calls the observer's completion handler so iOS
    /// keeps our background budget healthy.
    func registerObservers(
        store: HKHealthStore,
        types: [HKSampleType],
        deltaHandler: @escaping DeltaHandler
    ) {
        for type in types where observerQueries[type.identifier] == nil {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                // The completion handler MUST run in every code path or iOS
                // will exponentially back off and eventually stop delivery.
                guard let self else { completion(); return }
                if error != nil { completion(); return }
                Task {
                    let samples = await self.fetchDelta(store: store, type: type)
                    await deltaHandler(samples, type)
                    completion()
                }
            }
            store.execute(query)
            observerQueries[type.identifier] = query
        }
    }

    /// Run a single anchored delta pull for `type`. Advances the persisted
    /// anchor even on empty results so a genuinely idle day doesn't cause
    /// us to keep re-scanning the same window.
    func fetchDelta(store: HKHealthStore, type: HKSampleType) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let anchor = HealthKitAnchorStore.load(for: type.identifier)
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, _ in
                if let newAnchor {
                    HealthKitAnchorStore.save(newAnchor, for: type.identifier)
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    /// Detach all observers. Called on logout or when the user revokes
    /// biometric consent — releases the background delivery budget for
    /// other apps.
    func stopAll(store: HKHealthStore) {
        for (_, query) in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
    }

    var registeredTypeCount: Int { observerQueries.count }
}

// MARK: - Authorization probing

enum HealthKitAuthorizationProbe {
    /// Best-effort classification: after `requestAuthorization` returns,
    /// probe each read type for at least one sample in the last 30 days.
    /// If a type is capable of producing data (heart rate, steps) but the
    /// probe returns nothing, mark it as a suspected silent denial so the
    /// UI can nudge the user toward Settings › Privacy › Health.
    static func probe(
        store: HKHealthStore,
        readTypes: [HKSampleType],
        shareTypes: [HKSampleType]
    ) async -> HealthKitAuthorizationSnapshot {
        var snapshot = HealthKitAuthorizationSnapshot(lastCheckedAt: Date())

        for type in shareTypes {
            switch store.authorizationStatus(for: type) {
            case .sharingDenied:
                snapshot.deniedShareTypes.append(type.identifier)
            default:
                break
            }
        }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: thirtyDaysAgo, end: Date(), options: .strictStartDate)
        for type in readTypes {
            let hasAny = await probeHasSample(store: store, type: type, predicate: predicate)
            if !hasAny {
                snapshot.suspectedSilentDenials.append(type.identifier)
            }
        }
        return snapshot
    }

    private static func probeHasSample(store: HKHealthStore, type: HKSampleType, predicate: NSPredicate) async -> Bool {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
        }
    }
}

#endif
