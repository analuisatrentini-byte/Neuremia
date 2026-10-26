//
//  NeuremiaApp.swift
//  Neuremia
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData
import UIKit
import BackgroundTasks
#if canImport(HealthKit)
import HealthKit
#endif

/// Single source of truth for the on-device backup file path.
/// Both ContentView (writes) and NeuremiaBackgroundTasks (reads) use this.
enum BackupStore {
    /// Protected file in Documents, excluded from iCloud Backup.
    static var protectedFileURL: URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let currentURL = directory.appendingPathComponent("neuremia-backup.json")
        let legacyURL = directory.appendingPathComponent("neuroflow-backup.json")
        if !FileManager.default.fileExists(atPath: currentURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.moveItem(at: legacyURL, to: currentURL)
        }
        return currentURL
    }
}

private enum NeuremiaBackgroundTasks {
    static let backupRefreshIdentifier = "ALTB.Neuremia.backup-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backupRefreshIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackupRefresh(task: refreshTask)
        }
    }

    static func scheduleBackupRefresh() {
        let intervalDays = max(1, UserDefaults.standard.integer(forKey: "neuremiaBackupIntervalDays"))
        let request = BGAppRefreshTaskRequest(identifier: backupRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalDays * 86_400))

        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set("Backup em segundo plano agendado.", forKey: "neuremiaBackgroundBackupStatus")
        } catch {
            UserDefaults.standard.set("Falha ao agendar backup em segundo plano: \(error.localizedDescription)", forKey: "neuremiaBackgroundBackupStatus")
        }
    }

    private static func handleBackupRefresh(task: BGAppRefreshTask) {
        scheduleBackupRefresh()

        task.expirationHandler = {
            UserDefaults.standard.set("Backup em segundo plano expirou antes de finalizar.", forKey: "neuremiaBackgroundBackupStatus")
        }

        // S15: The backup file is written directly by makeBackupExport with
        // .completeFileProtection and isExcludedFromBackup = true. The
        // background task only needs to verify the file exists and record the
        // timestamp — no PHI passes through UserDefaults.
        let fileURL = BackupStore.protectedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            UserDefaults.standard.set("Sem backup local para atualizar em segundo plano.", forKey: "neuremiaBackgroundBackupStatus")
            task.setTaskCompleted(success: true)
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "neuremiaLastAutomaticBackupAt")
        UserDefaults.standard.set("Backup em segundo plano verificado.", forKey: "neuremiaBackgroundBackupStatus")
        task.setTaskCompleted(success: true)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    #if canImport(HealthKit)
    /// Kept alive for the lifetime of the process so background delivery
    /// callbacks resolve. HealthKitPipelineController holds the observer
    /// queries; this store is the one that executed them.
    let healthStore = HKHealthStore()
    #endif

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Move any legacy plaintext credentials out of UserDefaults before any
        // view reads them.
        NeuremiaStorageMigration.migrateLegacyDefaultsIfNeeded()
        KeychainStore.migrateLegacyTokenIfNeeded()
        NeuremiaBackgroundTasks.register()
        NeuremiaBackgroundTasks.scheduleBackupRefresh()
        // Re-arm HealthKit background delivery on cold launch. Apple docs are
        // explicit: observer queries must be set up in didFinishLaunching so
        // HK can call them when it wakes the app from a background delivery.
        installHealthKitPipelineIfPreviouslyEnabled()
        return true
    }

    #if canImport(HealthKit)
    private func installHealthKitPipelineIfPreviouslyEnabled() {
        // Only re-arm if the user had already granted authorization in a
        // previous session — otherwise we'd fire a permission prompt from
        // the AppDelegate, which is bad UX and won't succeed anyway.
        guard UserDefaults.standard.bool(forKey: "neuremiaHealthKitEnabled"),
              HKHealthStore.isHealthDataAvailable() else {
            return
        }
        let types: [HKSampleType] = [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ].compactMap { $0 }
        guard !types.isEmpty else { return }

        let store = healthStore
        Task {
            await HealthKitPipelineController.shared.registerObservers(
                store: store,
                types: types
            ) { _, type in
                // Delta samples have already been persisted by the anchored
                // query. Stamp the observer timestamp so the foreground sync
                // path knows to re-run the aggregate rollup on next activation.
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: "neuremiaLastHealthKitObserverAt"
                )
                UserDefaults.standard.set(
                    type.identifier,
                    forKey: "neuremiaLastHealthKitObserverType"
                )
            }
        }
    }
    #else
    private func installHealthKitPipelineIfPreviouslyEnabled() {}
    #endif

    func applicationDidEnterBackground(_ application: UIApplication) {
        NeuremiaBackgroundTasks.scheduleBackupRefresh()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        KeychainStore.set(token, for: .apnsDeviceToken)
        UserDefaults.standard.set("Token APNs recebido. Envie ao backend nas configurações.", forKey: "neuremiaRemotePushStatus")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set("Falha no APNs: \(error.localizedDescription)", forKey: "neuremiaRemotePushStatus")
    }
}

@main
struct NeuremiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Non-nil when the persistent store had to be rebuilt or replaced with an
    /// in-memory fallback. ContentView reads this once on appear and shows a
    /// banner so the user knows what happened.
    nonisolated(unsafe) static var storeRecoveryMessage: String?

    let sharedModelContainer: ModelContainer

    init() {
        NeuremiaStorageMigration.migrateLegacyDefaultsIfNeeded()
        KeychainStore.migrateLegacyTokenIfNeeded()

        let schema = Schema(NeuremiaSchemaV3.models, version: NeuremiaSchemaV3.versionIdentifier)
        let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // Schema fingerprint — sorted type-name hash. When the shipped model
        // set drifts from what's on disk (e.g. new @Model added to an existing
        // VersionedSchema without bumping its identifier), SwiftData raises an
        // uncatchable NSException inside NSLightweightMigrationStage init that
        // `try?` cannot see. So we detect drift proactively and wipe the store
        // BEFORE opening — the migration path that crashes never runs.
        let fingerprintKey = "neuremiaSchemaFingerprint"
        let currentFingerprint = NeuremiaSchemaV3.models
            .map { String(describing: $0) }
            .sorted()
            .joined(separator: "|")
        let storedFingerprint = UserDefaults.standard.string(forKey: fingerprintKey)
        let storeURL = persistentConfig.url
        let sidecarExtensions = ["", "-wal", "-shm"]

        // Drift when: (a) fingerprint exists and doesn't match, or (b) no
        // fingerprint yet but a store file exists on disk — case (b) covers
        // legacy installs (pre-fingerprint) whose schema might be stale.
        let storeExists = FileManager.default.fileExists(atPath: storeURL.path)
        let hasDrift = storedFingerprint != currentFingerprint
        if hasDrift && storeExists {
            Self.quarantinePersistentStore(storeURL: storeURL, sidecarExtensions: sidecarExtensions)
            if storedFingerprint != nil {
                NeuremiaApp.storeRecoveryMessage =
                    "O banco de dados local foi recriado após uma atualização do " +
                    "aplicativo. Os arquivos anteriores foram preservados para recuperação técnica."
            }
        }

        // 1st try — normal persistent open with migration plan.
        if let container = try? ModelContainer(for: schema, migrationPlan: NeuremiaMigrationPlan.self, configurations: [persistentConfig]) {
            UserDefaults.standard.set(currentFingerprint, forKey: fingerprintKey)
            sharedModelContainer = container
            return
        }

        // 2nd try — quarantine the unreadable store and recreate. Catches any
        // remaining corruption that fingerprint drift didn't cover without
        // destroying the old files irreversibly.
        Self.quarantinePersistentStore(storeURL: storeURL, sidecarExtensions: sidecarExtensions)

        if let container = try? ModelContainer(for: schema, migrationPlan: NeuremiaMigrationPlan.self, configurations: [persistentConfig]) {
            UserDefaults.standard.set(currentFingerprint, forKey: fingerprintKey)
            sharedModelContainer = container
            NeuremiaApp.storeRecoveryMessage =
                "O banco de dados local foi recriado após um erro de compatibilidade. " +
                "Registros anteriores não puderam ser recuperados."
            return
        }

        // 3rd try — in-memory fallback. The app stays open so the user can
        // still access the crisis plan and SOS contacts.
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [inMemoryConfig])
        } catch {
            fatalError("In-memory ModelContainer failed unexpectedly: \(error)")
        }
        NeuremiaApp.storeRecoveryMessage =
            "Não foi possível abrir o banco de dados local. O aplicativo está " +
            "funcionando sem persistência — dados deste uso não serão salvos. " +
            "Reinicie o app para tentar novamente."
    }

    private static func quarantinePersistentStore(storeURL: URL, sidecarExtensions: [String]) {
        let fileManager = FileManager.default
        let recoveryRoot = storeURL.deletingLastPathComponent()
            .appendingPathComponent("RecoveredPersistentStores", isDirectory: true)
        let recoveryDirectory = recoveryRoot
            .appendingPathComponent(String(Int(Date().timeIntervalSince1970)), isDirectory: true)

        do {
            try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            var rootValues = URLResourceValues()
            rootValues.isExcludedFromBackup = true
            var mutableRoot = recoveryRoot
            try? mutableRoot.setResourceValues(rootValues)
        } catch {
            return
        }

        for ext in sidecarExtensions {
            let sidecar = storeURL.deletingPathExtension()
                .appendingPathExtension(storeURL.pathExtension + ext)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            let destination = recoveryDirectory.appendingPathComponent(sidecar.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: sidecar, to: destination)
                try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            } catch {
                try? fileManager.removeItem(at: sidecar)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
