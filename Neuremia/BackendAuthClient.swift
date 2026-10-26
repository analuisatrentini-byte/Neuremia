//
//  BackendAuthClient.swift
//  Neuremia
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Combine
import CryptoKit
import Foundation
import os
import Security
import SwiftUI

extension Notification.Name {
    /// Posted whenever `KeychainStore` writes or deletes a value so that
    /// `@KeychainStored` property wrappers can refresh their published state.
    // Explicitamente nonisolated: o arquivo importa SwiftUI e Swift 6/iOS 26
    // inferia MainActor, mas essas Name constants precisam ser acessíveis
    // do contexto nonisolated do KeychainStore.
    nonisolated static let keychainStoreDidChange = Notification.Name("io.neuremia.keychainStoreDidChange")
    /// Posted when SessionRefreshCoordinator drops the session because the
    /// refresh token is missing or rejected. Views can react and route to login.
    nonisolated static let neuremiaSessionExpired = Notification.Name("io.neuremia.sessionExpired")
}

// MARK: - Keychain storage

/// Secure storage for the JWT and the APNs device token. Replaces the previous
/// UserDefaults-backed @AppStorage that left credentials in plaintext plist files.
///
/// Marcado como `nonisolated` para evitar que o `import SwiftUI` no arquivo
/// contamine a enum com isolamento MainActor (Swift 6/iOS 26). É utility
/// puro: só toca Keychain + posta notificação; nada de UI.
nonisolated enum KeychainStore {
    enum Key: String {
        case authToken = "neuremia.authToken"
        case refreshToken = "neuremia.refreshToken"
        case apnsDeviceToken = "neuremia.apnsDeviceToken"
        case draftEncryptionKey = "neuremia.draftEncryptionKey"
        case userRole = "neuremia.userRole"
        case userEmail = "neuremia.userEmail"
        case userName = "neuremia.userName"
        case userId = "neuremia.userId"
    }

    private static let service = "io.neuremia.app.secure"
    private static let legacyService = "io.neuroflow.app.secure"
    static let notificationKeyName = "neuremia.keychain.key"
    // N-C2: Serialize all Keychain reads/writes through a single unfair lock so
    // that concurrent JWT refresh and background sync tasks never race on
    // SecItemCopyMatching / SecItemUpdate pairs.
    private static var lock = OSAllocatedUnfairLock()

    static func string(for key: Key) -> String? {
        lock.withLock { () -> String? in
            var query = baseQuery(for: key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else { return nil }
            return value
        }
    }

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        let success: Bool = lock.withLock {
            let data = Data(value.utf8)
            let query = baseQuery(for: key)
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                return true
            } else if updateStatus == errSecItemNotFound {
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
                return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
            }
            return false
        }
        if success { postChange(for: key) }
        return success
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let success: Bool = lock.withLock {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        if success { postChange(for: key) }
        return success
    }

    private static func postChange(for key: Key) {
        NotificationCenter.default.post(
            name: .keychainStoreDidChange,
            object: nil,
            userInfo: [notificationKeyName: key.rawValue]
        )
    }

    /// One-shot migration from old NeuroFlow keys and legacy plaintext
    /// @AppStorage credentials. Idempotent: safe to call on every launch.
    static func migrateLegacyTokenIfNeeded() {
        migrateLegacyKeychainItemsIfNeeded()

        let defaults = UserDefaults.standard
        for (legacyKey, target) in legacyMigrations {
            guard let value = defaults.string(forKey: legacyKey), !value.isEmpty else { continue }
            if string(for: target) == nil {
                _ = set(value, for: target)
            }
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private static let legacyMigrations: [(String, Key)] = [
        ("neuroflowAuthToken", .authToken),
        ("neuremiaAuthToken", .authToken),
        ("neuroflowAPNsDeviceToken", .apnsDeviceToken),
        ("neuremiaAPNsDeviceToken", .apnsDeviceToken),
        ("neuroflowUserRole", .userRole),
        ("neuremiaUserRole", .userRole),
        ("neuroflowUserEmail", .userEmail),
        ("neuremiaUserEmail", .userEmail),
        ("neuroflowUserName", .userName),
        ("neuremiaUserName", .userName),
        ("neuroflowUserId", .userId),
        ("neuremiaUserId", .userId)
    ]

    private static let legacyKeychainAccounts: [(String, Key)] = [
        ("neuroflow.authToken", .authToken),
        ("neuroflow.refreshToken", .refreshToken),
        ("neuroflow.apnsDeviceToken", .apnsDeviceToken),
        ("neuroflow.draftEncryptionKey", .draftEncryptionKey),
        ("neuroflow.userRole", .userRole),
        ("neuroflow.userEmail", .userEmail),
        ("neuroflow.userName", .userName),
        ("neuroflow.userId", .userId)
    ]

    private static func migrateLegacyKeychainItemsIfNeeded() {
        for (legacyAccount, target) in legacyKeychainAccounts {
            guard let value = string(forAccount: legacyAccount, service: legacyService) else {
                continue
            }
            if string(for: target) != nil || set(value, for: target) {
                _ = delete(account: legacyAccount, service: legacyService)
            }
        }
    }

    // Swift 6 / iOS 26: sem `nonisolated`, o compilador infere MainActor
    // por conta do `import SwiftUI` no arquivo e trata as chamadas de dentro
    // de `lock.withLock { ... }` (nonisolated sync) como cross-actor. Como
    // esta função só lê `static let service` e `key.rawValue`, é puro utility.
    nonisolated private static func baseQuery(for key: Key) -> [String: Any] {
        baseQuery(account: key.rawValue, service: service)
    }

    nonisolated private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func string(forAccount account: String, service: String) -> String? {
        lock.withLock { () -> String? in
            var query = baseQuery(account: account, service: service)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess,
                  let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else { return nil }
            return value
        }
    }

    @discardableResult
    private static func delete(account: String, service: String) -> Bool {
        lock.withLock {
            let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }
}

enum NeuremiaStorageMigration {
    static func migrateLegacyDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        migrate(defaults: defaults, keyPairs: userDefaultsKeyPairs)
        migratePrefix(defaults: defaults, oldPrefix: "neuroflowHKAnchor.", newPrefix: "neuremiaHKAnchor.")
    }

    private static func migrate(defaults: UserDefaults, keyPairs: [(old: String, new: String)]) {
        for pair in keyPairs {
            guard defaults.object(forKey: pair.new) == nil,
                  let legacyValue = defaults.object(forKey: pair.old) else {
                continue
            }
            defaults.set(legacyValue, forKey: pair.new)
            defaults.removeObject(forKey: pair.old)
        }
    }

    private static func migratePrefix(defaults: UserDefaults, oldPrefix: String, newPrefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(oldPrefix) {
            let suffix = key.dropFirst(oldPrefix.count)
            let newKey = newPrefix + suffix
            guard defaults.object(forKey: newKey) == nil,
                  let legacyValue = defaults.object(forKey: key) else {
                continue
            }
            defaults.set(legacyValue, forKey: newKey)
            defaults.removeObject(forKey: key)
        }
    }

    private static let userDefaultsKeyPairs: [(old: String, new: String)] = [
        ("neuroflowMedicationReminderEnabled", "neuremiaMedicationReminderEnabled"),
        ("neuroflowCheckInReminderEnabled", "neuremiaCheckInReminderEnabled"),
        ("neuroflowDailyRetentionReminderEnabled", "neuremiaDailyRetentionReminderEnabled"),
        ("neuroflowMedicationReminderHour", "neuremiaMedicationReminderHour"),
        ("neuroflowCheckInReminderHour", "neuremiaCheckInReminderHour"),
        ("neuroflowDailyRetentionReminderHour", "neuremiaDailyRetentionReminderHour"),
        ("neuroflowCustomSymptomName", "neuremiaCustomSymptomName"),
        ("neuroflowCustomSymptomValue", "neuremiaCustomSymptomValue"),
        ("neuroflowCustomSymptomsData", "neuremiaCustomSymptomsData"),
        ("neuroflowNextAppointmentAt", "neuremiaNextAppointmentAt"),
        ("neuroflowNextAppointmentNote", "neuremiaNextAppointmentNote"),
        ("neuroflowAutoMonthlyReportEnabled", "neuremiaAutoMonthlyReportEnabled"),
        ("neuroflowAutoBackupEnabled", "neuremiaAutoBackupEnabled"),
        ("neuroflowBackupIntervalDays", "neuremiaBackupIntervalDays"),
        ("neuroflowLastAutomaticBackupAt", "neuremiaLastAutomaticBackupAt"),
        ("neuroflowAutoCareTeamSendEnabled", "neuremiaAutoCareTeamSendEnabled"),
        ("neuroflowCareTeamContact", "neuremiaCareTeamContact"),
        ("neuroflowCareTeamSendStatus", "neuremiaCareTeamSendStatus"),
        ("neuroflowShareWithCaregiver", "neuremiaShareWithCaregiver"),
        ("neuroflowHealthKitEnabled", "neuremiaHealthKitEnabled"),
        ("neuroflowHealthKitStatus", "neuremiaHealthKitStatus"),
        ("neuroflowHealthSteps", "neuremiaHealthSteps"),
        ("neuroflowHealthSleepHours", "neuremiaHealthSleepHours"),
        ("neuroflowHealthHeartRate", "neuremiaHealthHeartRate"),
        ("neuroflowHealthActiveEnergy", "neuremiaHealthActiveEnergy"),
        ("neuroflowHealthHRV", "neuremiaHealthHRV"),
        ("neuroflowLastHealthKitSyncAt", "neuremiaLastHealthKitSyncAt"),
        ("neuroflowHealthKitPipelineData", "neuremiaHealthKitPipelineData"),
        ("neuroflowHealthKitReconciliationData", "neuremiaHealthKitReconciliationData"),
        ("neuroflowHealthKitAuthData", "neuremiaHealthKitAuthData"),
        ("neuroflowHRVBaseline", "neuremiaHRVBaseline"),
        ("neuroflowHRVBaselineSamples", "neuremiaHRVBaselineSamples"),
        ("neuroflowHRVContextBaselinesData", "neuremiaHRVContextBaselinesData"),
        ("neuroflowRemotePushEnabled", "neuremiaRemotePushEnabled"),
        ("neuroflowRemotePushStatus", "neuremiaRemotePushStatus"),
        ("neuroflowBackgroundBackupStatus", "neuremiaBackgroundBackupStatus"),
        ("neuroflowOfflineSyncQueueData", "neuremiaOfflineSyncQueueData"),
        ("neuroflowLastSyncStatus", "neuremiaLastSyncStatus"),
        ("neuroflowBiometricConsentAccepted", "neuremiaBiometricConsentAccepted"),
        ("neuroflowBiometricConsentGrantedAt", "neuremiaBiometricConsentGrantedAt"),
        ("neuroflowPatientMoodModerateThreshold", "neuremiaPatientMoodModerateThreshold"),
        ("neuroflowPatientAnxietyModerateThreshold", "neuremiaPatientAnxietyModerateThreshold"),
        ("neuroflowPatientMinimumSleepThreshold", "neuremiaPatientMinimumSleepThreshold"),
        ("neuroflowCaregiverDigestConsent", "neuremiaCaregiverDigestConsent"),
        ("neuroflowCaregiverSMSConsent", "neuremiaCaregiverSMSConsent"),
        ("neuroflowCriticalPushConsent", "neuremiaCriticalPushConsent"),
        ("neuroflowPrivacyRetentionDays", "neuremiaPrivacyRetentionDays"),
        ("neuroflowOnboardingComplete", "neuremiaOnboardingComplete"),
        ("neuroflowMoodCoachmarkSeen", "neuremiaMoodCoachmarkSeen"),
        ("neuroflowLegalAcceptedVersion", "neuremiaLegalAcceptedVersion"),
        ("neuroflowInviteSnoozedUntil", "neuremiaInviteSnoozedUntil"),
        ("neuroflowLastHealthKitObserverAt", "neuremiaLastHealthKitObserverAt"),
        ("neuroflowLastHealthKitObserverType", "neuremiaLastHealthKitObserverType"),
        ("neuroflowSchemaFingerprint", "neuremiaSchemaFingerprint")
    ]
}

/// Listens to KeychainStore change notifications so SwiftUI views re-render
/// when the underlying value mutates from a non-UI path (e.g. a background
/// token refresh updating the Keychain).
final class KeychainObserver: ObservableObject {
    @Published var value: String
    private let key: KeychainStore.Key
    private var observerToken: NSObjectProtocol?

    init(key: KeychainStore.Key) {
        self.key = key
        self.value = KeychainStore.string(for: key) ?? ""
        observerToken = NotificationCenter.default.addObserver(
            forName: .keychainStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let changedKey = note.userInfo?[KeychainStore.notificationKeyName] as? String,
                  changedKey == key.rawValue else { return }
            let next = KeychainStore.string(for: key) ?? ""
            if next != self.value {
                self.value = next
            }
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func write(_ newValue: String) {
        value = newValue
        if newValue.isEmpty {
            KeychainStore.delete(key)
        } else {
            KeychainStore.set(newValue, for: key)
        }
    }
}

/// SwiftUI property wrapper that behaves like @AppStorage but persists into
/// the Keychain AND reacts to out-of-band changes (e.g. transparent token
/// refresh from SessionRefreshCoordinator).
@propertyWrapper
struct KeychainStored: DynamicProperty {
    @StateObject private var observer: KeychainObserver

    init(_ key: KeychainStore.Key) {
        _observer = StateObject(wrappedValue: KeychainObserver(key: key))
    }

    var wrappedValue: String {
        get { observer.value }
        nonmutating set { observer.write(newValue) }
    }

    var projectedValue: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

// MARK: - Encrypted drafts (S15 / F13')

/// Symmetric-key encryption layer for the patient's in-progress diary data.
///
/// Drafts (mood sliders, journal text, intrusive thoughts, side effects) used
/// to live in `@AppStorage`, which means UserDefaults, which means **the
/// iCloud Backup catalog**. That leaked PHI through a channel no clinical
/// product should rely on. Sprint 16 fixes it: drafts are still stored in
/// UserDefaults for portability, but as **AES-GCM ciphertext encrypted with
/// a 256-bit key kept exclusively in the Keychain**. If iCloud Backup
/// snapshots the plist, it captures bytes that are useless without the key.
enum DraftStore {
    /// Prefix used by the encrypted store so we don't collide with the
    /// legacy `@AppStorage("neuremiaDraft*")` keys during migration.
    static let storagePrefix = "neuremiaDraftEnc_"
    private static let legacyStoragePrefix = "neuroflowDraftEnc_"

    private static let symmetricKey: SymmetricKey = {
        if let stored = KeychainStore.string(for: .draftEncryptionKey),
           let data = Data(base64Encoded: stored), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let raw = fresh.withUnsafeBytes { Data($0) }
        KeychainStore.set(raw.base64EncodedString(), for: .draftEncryptionKey)
        return fresh
    }()

    static func loadCodable<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        let storageKey = storagePrefix + key
        migrateLegacyEncryptedBlobIfNeeded(forKey: key)
        guard let base64 = UserDefaults.standard.string(forKey: storageKey),
              let ciphertext = Data(base64Encoded: base64) else {
            return nil
        }
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(sealed, using: symmetricKey)
            return try JSONDecoder().decode(T.self, from: plaintext)
        } catch {
            return nil
        }
    }

    static func saveCodable<T: Codable>(_ value: T, forKey key: String) {
        let storageKey = storagePrefix + key
        do {
            let plaintext = try JSONEncoder().encode(value)
            let sealed = try AES.GCM.seal(plaintext, using: symmetricKey)
            guard let combined = sealed.combined else { return }
            UserDefaults.standard.set(combined.base64EncodedString(), forKey: storageKey)
        } catch {
            // Encryption should never fail with a healthy CryptoKit. If it
            // somehow does, dropping the write is strictly safer than
            // falling back to plaintext.
        }
    }

    static func remove(forKey key: String) {
        UserDefaults.standard.removeObject(forKey: storagePrefix + key)
        if let legacyKey = legacyDraftKey(for: key) {
            UserDefaults.standard.removeObject(forKey: legacyStoragePrefix + legacyKey)
        }
    }

    // MARK: - Backup envelope helpers

    /// Encrypt a plain string to AES-GCM base-64 for inclusion in the
    /// backup JSON. The same device key is used so the file is useless
    /// without the Keychain — even if the JSON is extracted from the device.
    static func encryptString(_ value: String) -> String? {
        guard let plaintext = value.data(using: .utf8) else { return nil }
        guard let sealed = try? AES.GCM.seal(plaintext, using: symmetricKey),
              let combined = sealed.combined else { return nil }
        return combined.base64EncodedString()
    }

    /// Inverse of `encryptString(_:)`. Returns `nil` if the ciphertext is
    /// malformed or was encrypted with a different key (e.g. restored from
    /// a different device without key migration).
    static func decryptString(_ base64: String) -> String? {
        guard let ciphertext = Data(base64Encoded: base64),
              let sealed = try? AES.GCM.SealedBox(combined: ciphertext),
              let plaintext = try? AES.GCM.open(sealed, using: symmetricKey) else { return nil }
        return String(data: plaintext, encoding: .utf8)
    }

    /// One-shot migration: if the legacy plaintext `@AppStorage` value still
    /// exists, capture it, write it encrypted, and remove the plaintext copy
    /// so subsequent iCloud Backups no longer carry the PHI in the clear.
    static func migrateLegacyValue<T: Codable>(
        legacyKey: String,
        as type: T.Type
    ) -> T? {
        guard loadCodable(T.self, forKey: legacyKey) == nil else {
            return nil
        }
        let defaults = UserDefaults.standard
        let candidateKeys = [legacyKey, legacyDraftKey(for: legacyKey)].compactMap { $0 }
        guard let sourceKey = candidateKeys.first(where: { defaults.object(forKey: $0) != nil }),
              let raw = defaults.object(forKey: sourceKey),
              let typed = raw as? T else {
            return nil
        }
        saveCodable(typed, forKey: legacyKey)
        for key in candidateKeys {
            defaults.removeObject(forKey: key)
        }
        return typed
    }

    private static func migrateLegacyEncryptedBlobIfNeeded(forKey key: String) {
        let defaults = UserDefaults.standard
        let storageKey = storagePrefix + key
        guard defaults.object(forKey: storageKey) == nil,
              let legacyKey = legacyDraftKey(for: key),
              let legacyBase64 = defaults.string(forKey: legacyStoragePrefix + legacyKey) else {
            return
        }
        defaults.set(legacyBase64, forKey: storageKey)
        defaults.removeObject(forKey: legacyStoragePrefix + legacyKey)
    }

    private static func legacyDraftKey(for key: String) -> String? {
        guard key.hasPrefix("neuremia") else { return nil }
        return "neuroflow" + key.dropFirst("neuremia".count)
    }
}

/// SwiftUI property wrapper that mirrors `@AppStorage` for `Codable` values
/// but routes all reads/writes through `DraftStore` so the on-disk byte
/// stream is AES-GCM ciphertext rather than plain plist entries.
@propertyWrapper
struct EncryptedDraft<Value: Codable>: DynamicProperty {
    @State private var value: Value
    private let key: String

    init(_ key: String, defaultValue: Value) {
        self.key = key
        // Priority order:
        // 1. Existing encrypted blob.
        // 2. Legacy plaintext @AppStorage value (auto-migrate, then wipe).
        // 3. Caller's default.
        if let existing = DraftStore.loadCodable(Value.self, forKey: key) {
            _value = State(initialValue: existing)
        } else if let migrated = DraftStore.migrateLegacyValue(legacyKey: key, as: Value.self) {
            _value = State(initialValue: migrated)
        } else {
            _value = State(initialValue: defaultValue)
        }
    }

    var wrappedValue: Value {
        get { value }
        nonmutating set {
            value = newValue
            DraftStore.saveCodable(newValue, forKey: key)
        }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

// MARK: - Backend configuration

enum BackendConfiguration {
    private static let localDevelopmentBaseURL = "http://127.0.0.1:8000"
    private static let disabledRemoteBaseURL = "https://neuremia-backend-not-configured.invalid"

    /// Read from the bundle Info.plist key `NeuremiaAPIBaseURL`.
    /// DEBUG falls back to the local dev backend. Release never crashes because
    /// of a missing value; an invalid or placeholder URL resolves to a reserved
    /// `.invalid` host so network callers fail safely instead of terminating.
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "NeuremiaAPIBaseURL") as? String,
           isUsableBackendURL(raw),
           let url = URL(string: raw) {
            return url
        }
        #if DEBUG
        return URL(string: localDevelopmentBaseURL)!
        #else
        return URL(string: disabledRemoteBaseURL)!
        #endif
    }

    private static func isUsableBackendURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              url.scheme == "https" || url.scheme == "http" else {
            return false
        }
        return !host.contains("your-domain.com")
            && !host.contains("example.com")
            && !host.contains("placeholder")
    }

    /// Hex-encoded SHA-256 of pinned server certificates. Configure via
    /// `INFOPLIST_KEY_NeuremiaPinnedCertHashes = hash1,hash2` (comma-separated).
    /// If empty, the app uses the standard iOS TLS trust evaluation.
    static var pinnedCertificateHashes: Set<String> {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "NeuremiaPinnedCertHashes") as? String,
              !raw.isEmpty else {
            return []
        }
        let normalized = raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        // Validate each token is a 64-char lowercase hex SHA-256. A typo or
        // accidental CRLF in the build setting now drops that single entry
        // instead of poisoning the whole pin set.
        return Set(normalized.filter { hash in
            hash.count == 64 && hash.allSatisfy { $0.isHexDigit }
        })
    }
}

/// URLSessionDelegate that validates the server certificate against a set of
/// SHA-256 pins read from Info.plist. Production builds with pins configured
/// refuse to talk to a server presenting a cert outside the allowlist —
/// blocking MITM via attacker-owned trusted CAs.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host
        #if DEBUG
        // Local backend runs over plain HTTP — no trust to validate.
        if host == "127.0.0.1" || host == "localhost" {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        #endif

        let pins = BackendConfiguration.pinnedCertificateHashes
        guard !pins.isEmpty else {
            // No pins configured: rely on the platform trust store. This keeps
            // production resilient to normal certificate rotation while still
            // allowing stricter pinning when real hashes are supplied.
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Sprint B: avaliar a cadeia ANTES de comparar pins. Sem isso, um cert
        // pinado mas expirado/revogado seria aceito (CN bate por hash mesmo
        // após validade vencer). SecTrustEvaluateWithError aplica as policies
        // padrão (validity, hostname, basic constraints) e retorna false em
        // qualquer falha.
        var evaluationError: CFError?
        guard SecTrustEvaluateWithError(trust, &evaluationError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var serverHashes: Set<String> = []
        let certificates = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        for certificate in certificates {
            let data = SecCertificateCopyData(certificate) as Data
            let digest = SHA256.hash(data: data)
            serverHashes.insert(digest.compactMap { String(format: "%02x", $0) }.joined())
        }

        if !serverHashes.isDisjoint(with: pins) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - DTOs

struct BackendUser: Decodable, Hashable {
    let id: Int
    let email: String
    let fullName: String
    let role: String
    let riskScore: Int?
    let riskLevel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case role
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
    }
}

struct BackendPatientListResponse: Decodable {
    let items: [BackendUser]
    let total: Int
    let skip: Int
    let limit: Int
}

struct BackendLoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let user: BackendUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case user
    }
}

struct BackendDailyCheckInPayload: Codable {
    let mood: Double
    let anxiety: Double
    let energy: Double
    let irritability: Double
    let sleepHours: Double
    let appetite: Double
    let libido: Double
    let medicationTaken: Bool
    let sideEffects: String
    let automaticThoughts: String
    let suicidalIdeation: Bool
    let journalEntry: String

    enum CodingKeys: String, CodingKey {
        case mood
        case anxiety
        case energy
        case irritability
        case sleepHours = "sleep_hours"
        case appetite
        case libido
        case medicationTaken = "medication_taken"
        case sideEffects = "side_effects"
        case automaticThoughts = "automatic_thoughts"
        case suicidalIdeation = "suicidal_ideation"
        case journalEntry = "journal_entry"
    }
}

struct BackendDailyCheckIn: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let createdAt: String
    let mood: Double
    let anxiety: Double
    let energy: Double
    let irritability: Double
    let sleepHours: Double
    let appetite: Double
    let libido: Double
    let medicationTaken: Bool
    let sideEffects: String
    let automaticThoughts: String
    let suicidalIdeation: Bool
    let journalEntry: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case createdAt = "created_at"
        case mood
        case anxiety
        case energy
        case irritability
        case sleepHours = "sleep_hours"
        case appetite
        case libido
        case medicationTaken = "medication_taken"
        case sideEffects = "side_effects"
        case automaticThoughts = "automatic_thoughts"
        case suicidalIdeation = "suicidal_ideation"
        case journalEntry = "journal_entry"
    }
}

struct BackendScaleAssessmentPayload: Codable {
    let scaleName: String
    let answers: [Int]
    let score: Int
    let interpretation: String

    enum CodingKeys: String, CodingKey {
        case scaleName = "scale_name"
        case answers
        case score
        case interpretation
    }
}

struct BackendScaleAssessment: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let createdAt: String
    let scaleName: String
    let answers: [Int]
    let score: Int
    let interpretation: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case createdAt = "created_at"
        case scaleName = "scale_name"
        case answers
        case score
        case interpretation
    }
}

struct BackendClinicalReportPayload: Codable {
    let riskLevel: String
    let summary: String
    var autoSend: Bool = false
    var careTeamContact: String? = nil
    var apnsToken: String? = nil

    enum CodingKeys: String, CodingKey {
        case riskLevel = "risk_level"
        case summary
        case autoSend = "auto_send"
        case careTeamContact = "care_team_contact"
        case apnsToken = "apns_token"
    }
}

struct PushTokenPayload: Encodable {
    let token: String
    let platform: String
}

struct BackendCriticalAlertPayload: Encodable {
    let level: String
    let alertType: String
    let escalationTarget: String
    let title: String
    let message: String
    let policy: String
    let channels: [String]
    let caregiverIds: [Int]
    let apnsToken: String?
    let safetyPlanSummary: String

    enum CodingKeys: String, CodingKey {
        case level
        case alertType = "alert_type"
        case escalationTarget = "escalation_target"
        case title
        case message
        case policy
        case channels
        case caregiverIds = "caregiver_ids"
        case apnsToken = "apns_token"
        case safetyPlanSummary = "safety_plan_summary"
    }
}

struct BackendCriticalAlertDispatch: Decodable, Identifiable {
    let id: String
    let alertId: Int?
    let status: String
    let escalationStartedAt: String?
    let channels: [String]
    let acknowledgementRequired: Bool
    let acknowledgementURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case alertId = "alert_id"
        case status
        case escalationStartedAt = "escalation_started_at"
        case channels
        case acknowledgementRequired = "acknowledgement_required"
        case acknowledgementURL = "acknowledgement_url"
    }
}

struct BackendCriticalAlertAcknowledgementPayload: Encodable {
    let status: String
    let note: String
}

struct BackendClinicalAlertWorkflowPayload: Encodable {
    let status: String
    let assignedClinicianId: Int?
    let snoozedUntil: String?
    let contactStatus: String?
    let resolutionNote: String?

    enum CodingKeys: String, CodingKey {
        case status
        case assignedClinicianId = "assigned_clinician_id"
        case snoozedUntil = "snoozed_until"
        case contactStatus = "contact_status"
        case resolutionNote = "resolution_note"
    }
}

struct BackendCaregiverPayload: Encodable {
    let name: String
    let contact: String
    let relationship: String
    let shareEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case contact
        case relationship
        case shareEnabled = "share_enabled"
    }
}

struct BackendCaregiverContact: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let name: String
    let contact: String
    let relationship: String
    let shareEnabled: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case name
        case contact
        case relationship
        case shareEnabled = "share_enabled"
        case createdAt = "created_at"
    }
}

struct BackendClinicalAlert: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let createdAt: String
    let level: String
    let alertType: String
    let escalationTarget: String
    let title: String
    let message: String
    let acknowledged: Bool
    let workflowStatus: String?
    let contactStatus: String?
    let assignedClinicianName: String?
    let snoozedUntil: String?
    let resolvedAt: String?
    let auditSummary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case createdAt = "created_at"
        case level
        case alertType = "alert_type"
        case escalationTarget = "escalation_target"
        case title
        case message
        case acknowledged
        case workflowStatus = "workflow_status"
        case contactStatus = "contact_status"
        case assignedClinicianName = "assigned_clinician_name"
        case snoozedUntil = "snoozed_until"
        case resolvedAt = "resolved_at"
        case auditSummary = "audit_summary"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        patientId = try container.decode(Int.self, forKey: .patientId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        level = try container.decode(String.self, forKey: .level)
        alertType = try container.decodeIfPresent(String.self, forKey: .alertType)
            ?? ClinicalAlertKind.psychiatricEmergency.rawValue
        escalationTarget = try container.decodeIfPresent(String.self, forKey: .escalationTarget)
            ?? ClinicalEscalationTarget.clinicianCaregiverNow.rawValue
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        acknowledged = try container.decode(Bool.self, forKey: .acknowledged)
        workflowStatus = try container.decodeIfPresent(String.self, forKey: .workflowStatus)
        contactStatus = try container.decodeIfPresent(String.self, forKey: .contactStatus)
        assignedClinicianName = try container.decodeIfPresent(String.self, forKey: .assignedClinicianName)
        snoozedUntil = try container.decodeIfPresent(String.self, forKey: .snoozedUntil)
        resolvedAt = try container.decodeIfPresent(String.self, forKey: .resolvedAt)
        auditSummary = try container.decodeIfPresent(String.self, forKey: .auditSummary)
    }
}

struct BackendClinicalReport: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let createdAt: String
    let riskLevel: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case createdAt = "created_at"
        case riskLevel = "risk_level"
        case summary
    }
}

struct BackendTemporalRiskPredictionPayload: Encodable {
    let checkIns: [BackendTemporalCheckInPoint]
    let assessments: [BackendTemporalScalePoint]
    let previousEpisodes: [BackendTemporalEpisodePoint]

    enum CodingKeys: String, CodingKey {
        case checkIns = "check_ins"
        case assessments
        case previousEpisodes = "previous_episodes"
    }
}

struct BackendTemporalCheckInPoint: Encodable {
    let recordedAt: String
    let mood: Double
    let anxiety: Double
    let energy: Double
    let irritability: Double
    let sleepHours: Double
    let medicationTaken: Bool
    let suicidalIdeation: Bool
    let eventTags: [String]

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case mood
        case anxiety
        case energy
        case irritability
        case sleepHours = "sleep_hours"
        case medicationTaken = "medication_taken"
        case suicidalIdeation = "suicidal_ideation"
        case eventTags = "event_tags"
    }
}

struct BackendTemporalScalePoint: Encodable {
    let recordedAt: String
    let scaleName: String
    let score: Int

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
        case scaleName = "scale_name"
        case score
    }
}

struct BackendTemporalEpisodePoint: Encodable {
    let startedAt: String
    let kind: String
    let severity: String

    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at"
        case kind
        case severity
    }
}

struct BackendTemporalRiskPrediction: Decodable {
    let modelVersion: String
    let generatedAt: String
    let sevenDayRiskScore: Int
    let fourteenDayRiskScore: Int
    let sevenDayRiskLevel: String
    let fourteenDayRiskLevel: String
    let primaryWindow: String
    let confidence: Double
    let drivers: [String]
    let evidence: [String]

    enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
        case generatedAt = "generated_at"
        case sevenDayRiskScore = "seven_day_risk_score"
        case fourteenDayRiskScore = "fourteen_day_risk_score"
        case sevenDayRiskLevel = "seven_day_risk_level"
        case fourteenDayRiskLevel = "fourteen_day_risk_level"
        case primaryWindow = "primary_window"
        case confidence
        case drivers
        case evidence
    }
}

struct BackendModelValidationReport: Decodable, Identifiable {
    let id: String
    let modelVersion: String
    let trainedAt: String
    let validationWindowDays: Int
    let patientCount: Int
    let episodeCount: Int
    let sensitivitySevenDay: Double
    let sensitivityFourteenDay: Double
    let falsePositiveRate: Double
    let medianLeadTimeDays: Double
    let calibrationSummary: String

    enum CodingKeys: String, CodingKey {
        case id
        case modelVersion = "model_version"
        case trainedAt = "trained_at"
        case validationWindowDays = "validation_window_days"
        case patientCount = "patient_count"
        case episodeCount = "episode_count"
        case sensitivitySevenDay = "sensitivity_7d"
        case sensitivityFourteenDay = "sensitivity_14d"
        case falsePositiveRate = "false_positive_rate"
        case medianLeadTimeDays = "median_lead_time_days"
        case calibrationSummary = "calibration_summary"
    }
}

struct BackendClinicalTask: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let patientName: String
    let alertId: Int?
    let title: String
    let priority: String
    let status: String
    let assignedClinicianName: String?
    let contactStatus: String?
    let dueAt: String?
    let snoozedUntil: String?
    let resolvedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case patientName = "patient_name"
        case alertId = "alert_id"
        case title
        case priority
        case status
        case assignedClinicianName = "assigned_clinician_name"
        case contactStatus = "contact_status"
        case dueAt = "due_at"
        case snoozedUntil = "snoozed_until"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
    }
}

struct BackendAuditLog: Decodable, Identifiable {
    let id: Int
    /// Nullable after Sprint 9: rows referencing a deleted user are retained
    /// with `actor_user_id = NULL` for forensic compliance. Was previously
    /// `Int` (non-optional) — decoding crashed once any user invoked
    /// DELETE /me. Sprint 10 regression: keep this optional.
    let actorUserId: Int?
    let action: String
    let resourceType: String
    let resourceId: String
    let createdAt: String
    let reason: String?
    let dataScope: [String]
    let alertId: Int?
    let consentSnapshot: String?
    let consentVersion: String?

    enum CodingKeys: String, CodingKey {
        case id
        case actorUserId = "actor_user_id"
        case action
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case createdAt = "created_at"
        case reason
        case dataScope = "data_scope"
        case alertId = "alert_id"
        case consentSnapshot = "consent_snapshot"
        case consentVersion = "consent_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        actorUserId = try container.decodeIfPresent(Int.self, forKey: .actorUserId)
        action = try container.decode(String.self, forKey: .action)
        resourceType = try container.decode(String.self, forKey: .resourceType)
        resourceId = try container.decode(String.self, forKey: .resourceId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        dataScope = try container.decodeIfPresent([String].self, forKey: .dataScope) ?? []
        alertId = try container.decodeIfPresent(Int.self, forKey: .alertId)
        consentSnapshot = try container.decodeIfPresent(String.self, forKey: .consentSnapshot)
        consentVersion = try container.decodeIfPresent(String.self, forKey: .consentVersion)
    }
}

struct BackendRetentionDeleteResponse: Decodable {
    let deletedCheckins: Int
    let deletedAssessments: Int
    let deletedAlerts: Int
    let deletedReports: Int

    enum CodingKeys: String, CodingKey {
        case deletedCheckins = "deleted_checkins"
        case deletedAssessments = "deleted_assessments"
        case deletedAlerts = "deleted_alerts"
        case deletedReports = "deleted_reports"
    }
}

struct BackendAccountDeleteResponse: Decodable {
    let deletedUserId: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case deletedUserId = "deleted_user_id"
        case message
    }
}

struct BackendLinkedClinician: Decodable, Identifiable {
    let clinicianId: Int
    let clinicianFullName: String
    let clinicianEmail: String
    let linkedAt: String

    var id: Int { clinicianId }

    enum CodingKeys: String, CodingKey {
        case clinicianId = "clinician_id"
        case clinicianFullName = "clinician_full_name"
        case clinicianEmail = "clinician_email"
        case linkedAt = "linked_at"
    }
}

/// Invite as seen from the clinician dashboard: enriched with the patient
/// the request was directed at, with status that includes `revoked` so the
/// clinician sees when the patient declined.
struct BackendSentInvite: Decodable, Identifiable {
    let id: Int
    let patientId: Int
    let patientFullName: String
    let patientEmail: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case patientFullName = "patient_full_name"
        case patientEmail = "patient_email"
        case status
        case createdAt = "created_at"
    }
}

struct BackendClinicianInvite: Decodable, Identifiable {
    let id: Int
    let clinicianId: Int
    let patientId: Int
    let clinicianFullName: String
    let clinicianEmail: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case clinicianId = "clinician_id"
        case patientId = "patient_id"
        case clinicianFullName = "clinician_full_name"
        case clinicianEmail = "clinician_email"
        case status
        case createdAt = "created_at"
    }
}

enum BackendAuthError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case unauthorized
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "URL do backend inválida."
        case .invalidCredentials:
            "E-mail ou senha inválidos."
        case .unauthorized:
            "Sessão expirada. Entre novamente."
        case .serverError(let message):
            message
        case .invalidResponse:
            "Resposta inválida do servidor."
        }
    }
}

/// Protocol surface for the backend so tests can inject a mock instead of
/// hitting the network. The static `BackendAuthClient` is the live impl,
/// reachable via `BackendAuthClient.live`.
protocol BackendAPI {
    func login(email: String, password: String) async throws -> BackendLoginResponse
    func register(email: String, password: String, fullName: String) async throws -> BackendLoginResponse
    func requestPasswordReset(email: String) async throws -> String
    func confirmPasswordReset(email: String, resetCode: String, newPassword: String) async throws -> String
    func refresh(refreshToken: String) async throws -> BackendLoginResponse
    func logout(refreshToken: String, accessToken: String) async throws

    func inviteClinicianAccess(patientEmail: String, token: String) async throws -> BackendClinicianInvite
    func pendingInvites(token: String) async throws -> [BackendClinicianInvite]
    func acceptInvite(id: Int, token: String) async throws -> BackendClinicianInvite
    func revokeInvite(id: Int, token: String) async throws -> BackendClinicianInvite
    func linkedClinicians(token: String) async throws -> [BackendLinkedClinician]
    func revokeClinicalAccess(clinicianId: Int, token: String) async throws

    func clinicianPatients(token: String) async throws -> [BackendUser]
    func clinicianSentInvites(token: String) async throws -> [BackendSentInvite]
    func patientCheckIns(patientId: Int, token: String) async throws -> [BackendDailyCheckIn]
    func patientAssessments(patientId: Int, token: String) async throws -> [BackendScaleAssessment]
    func patientAlerts(patientId: Int, token: String) async throws -> [BackendClinicalAlert]
    func patientReports(patientId: Int, token: String) async throws -> [BackendClinicalReport]
    func predictTemporalRisk(patientId: Int, payload: BackendTemporalRiskPredictionPayload, token: String) async throws -> BackendTemporalRiskPrediction
    func modelValidationReport(token: String) async throws -> BackendModelValidationReport
    func clinicalTasks(patientId: Int?, token: String) async throws -> [BackendClinicalTask]
    func updateClinicalAlertWorkflow(alertId: Int, payload: BackendClinicalAlertWorkflowPayload, token: String) async throws -> BackendClinicalAlert

    func createCheckIn(_ payload: BackendDailyCheckInPayload, token: String) async throws
    func createAssessment(_ payload: BackendScaleAssessmentPayload, token: String) async throws
    func createReport(_ payload: BackendClinicalReportPayload, token: String) async throws
    func registerPushToken(token deviceToken: String, platform: String, token authToken: String) async throws
    func dispatchCriticalAlert(_ payload: BackendCriticalAlertPayload, token: String) async throws -> BackendCriticalAlertDispatch
    func acknowledgeCriticalAlert(dispatchId: String, payload: BackendCriticalAlertAcknowledgementPayload, token: String) async throws -> BackendCriticalAlertDispatch

    func caregivers(token: String) async throws -> [BackendCaregiverContact]
    func createCaregiver(_ payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact
    func updateCaregiver(id: Int, payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact
    func deleteCaregiver(id: Int, token: String) async throws

    // LGPD / data subject rights
    func exportAccount(token: String) async throws -> Data
    func auditLogs(token: String) async throws -> [BackendAuditLog]
    func deleteOldClinicalData(daysOlderThan: Int, token: String) async throws -> BackendRetentionDeleteResponse
    func deleteAccount(token: String) async throws -> BackendAccountDeleteResponse
}

/// Thin instance bridge so consumers can hold a `BackendAPI` reference instead
/// of the enum directly. Keeps the existing static-call sites working
/// unchanged while opening the door to injection in views and tests.
struct LiveBackendAPI: BackendAPI {
    func login(email: String, password: String) async throws -> BackendLoginResponse {
        try await BackendAuthClient.login(email: email, password: password)
    }
    func register(email: String, password: String, fullName: String) async throws -> BackendLoginResponse {
        try await BackendAuthClient.register(email: email, password: password, fullName: fullName)
    }
    func requestPasswordReset(email: String) async throws -> String {
        try await BackendAuthClient.requestPasswordReset(email: email)
    }
    func confirmPasswordReset(email: String, resetCode: String, newPassword: String) async throws -> String {
        try await BackendAuthClient.confirmPasswordReset(email: email, resetCode: resetCode, newPassword: newPassword)
    }
    func refresh(refreshToken: String) async throws -> BackendLoginResponse {
        try await BackendAuthClient.refresh(refreshToken: refreshToken)
    }
    func logout(refreshToken: String, accessToken: String) async throws {
        try await BackendAuthClient.logout(refreshToken: refreshToken, accessToken: accessToken)
    }
    func inviteClinicianAccess(patientEmail: String, token: String) async throws -> BackendClinicianInvite {
        try await BackendAuthClient.inviteClinicianAccess(patientEmail: patientEmail, token: token)
    }
    func pendingInvites(token: String) async throws -> [BackendClinicianInvite] {
        try await BackendAuthClient.pendingInvites(token: token)
    }
    func acceptInvite(id: Int, token: String) async throws -> BackendClinicianInvite {
        try await BackendAuthClient.acceptInvite(id: id, token: token)
    }
    func revokeInvite(id: Int, token: String) async throws -> BackendClinicianInvite {
        try await BackendAuthClient.revokeInvite(id: id, token: token)
    }
    func linkedClinicians(token: String) async throws -> [BackendLinkedClinician] {
        try await BackendAuthClient.linkedClinicians(token: token)
    }
    func revokeClinicalAccess(clinicianId: Int, token: String) async throws {
        try await BackendAuthClient.revokeClinicalAccess(clinicianId: clinicianId, token: token)
    }
    func clinicianPatients(token: String) async throws -> [BackendUser] {
        try await BackendAuthClient.clinicianPatients(token: token)
    }
    func clinicianSentInvites(token: String) async throws -> [BackendSentInvite] {
        try await BackendAuthClient.clinicianSentInvites(token: token)
    }
    func patientCheckIns(patientId: Int, token: String) async throws -> [BackendDailyCheckIn] {
        try await BackendAuthClient.patientCheckIns(patientId: patientId, token: token)
    }
    func patientAssessments(patientId: Int, token: String) async throws -> [BackendScaleAssessment] {
        try await BackendAuthClient.patientAssessments(patientId: patientId, token: token)
    }
    func patientAlerts(patientId: Int, token: String) async throws -> [BackendClinicalAlert] {
        try await BackendAuthClient.patientAlerts(patientId: patientId, token: token)
    }
    func patientReports(patientId: Int, token: String) async throws -> [BackendClinicalReport] {
        try await BackendAuthClient.patientReports(patientId: patientId, token: token)
    }
    func predictTemporalRisk(patientId: Int, payload: BackendTemporalRiskPredictionPayload, token: String) async throws -> BackendTemporalRiskPrediction {
        try await BackendAuthClient.predictTemporalRisk(patientId: patientId, payload: payload, token: token)
    }
    func modelValidationReport(token: String) async throws -> BackendModelValidationReport {
        try await BackendAuthClient.modelValidationReport(token: token)
    }
    func clinicalTasks(patientId: Int?, token: String) async throws -> [BackendClinicalTask] {
        try await BackendAuthClient.clinicalTasks(patientId: patientId, token: token)
    }
    func updateClinicalAlertWorkflow(alertId: Int, payload: BackendClinicalAlertWorkflowPayload, token: String) async throws -> BackendClinicalAlert {
        try await BackendAuthClient.updateClinicalAlertWorkflow(alertId: alertId, payload: payload, token: token)
    }
    func createCheckIn(_ payload: BackendDailyCheckInPayload, token: String) async throws {
        try await BackendAuthClient.createCheckIn(payload, token: token)
    }
    func createAssessment(_ payload: BackendScaleAssessmentPayload, token: String) async throws {
        try await BackendAuthClient.createAssessment(payload, token: token)
    }
    func createReport(_ payload: BackendClinicalReportPayload, token: String) async throws {
        try await BackendAuthClient.createReport(payload, token: token)
    }
    func registerPushToken(token deviceToken: String, platform: String, token authToken: String) async throws {
        try await BackendAuthClient.registerPushToken(token: deviceToken, platform: platform, token: authToken)
    }
    func dispatchCriticalAlert(_ payload: BackendCriticalAlertPayload, token: String) async throws -> BackendCriticalAlertDispatch {
        try await BackendAuthClient.dispatchCriticalAlert(payload, token: token)
    }
    func acknowledgeCriticalAlert(dispatchId: String, payload: BackendCriticalAlertAcknowledgementPayload, token: String) async throws -> BackendCriticalAlertDispatch {
        try await BackendAuthClient.acknowledgeCriticalAlert(dispatchId: dispatchId, payload: payload, token: token)
    }
    func caregivers(token: String) async throws -> [BackendCaregiverContact] {
        try await BackendAuthClient.caregivers(token: token)
    }
    func createCaregiver(_ payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact {
        try await BackendAuthClient.createCaregiver(payload, token: token)
    }
    func updateCaregiver(id: Int, payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact {
        try await BackendAuthClient.updateCaregiver(id: id, payload: payload, token: token)
    }
    func deleteCaregiver(id: Int, token: String) async throws {
        try await BackendAuthClient.deleteCaregiver(id: id, token: token)
    }
    func exportAccount(token: String) async throws -> Data {
        try await BackendAuthClient.exportAccount(token: token)
    }
    func auditLogs(token: String) async throws -> [BackendAuditLog] {
        try await BackendAuthClient.auditLogs(token: token)
    }
    func deleteOldClinicalData(daysOlderThan: Int, token: String) async throws -> BackendRetentionDeleteResponse {
        try await BackendAuthClient.deleteOldClinicalData(daysOlderThan: daysOlderThan, token: token)
    }
    func deleteAccount(token: String) async throws -> BackendAccountDeleteResponse {
        try await BackendAuthClient.deleteAccount(token: token)
    }
}

/// Serializes refresh-token rotation. Multiple in-flight requests that fail
/// with 401 share the same refresh attempt (single-flight) so we never burn
/// a fresh refresh token on a stampede.
actor SessionRefreshCoordinator {
    static let shared = SessionRefreshCoordinator()
    private init() {}

    private var inflight: Task<String, Error>?

    /// Returns a new access token if refresh succeeded. Side effects:
    /// updates Keychain (which posts keychainStoreDidChange so views see
    /// the new token), or clears the session and posts neuremiaSessionExpired
    /// if refresh failed.
    func refresh() async throws -> String {
        if let inflight {
            return try await inflight.value
        }

        let refreshTok = await MainActor.run { KeychainStore.string(for: .refreshToken) ?? "" }
        guard !refreshTok.isEmpty else {
            await clearSessionAndNotify()
            throw BackendAuthError.unauthorized
        }

        let task = Task<String, Error> { [refreshTok] in
            let response = try await BackendAuthClient.refresh(refreshToken: refreshTok)
            await MainActor.run {
                KeychainStore.set(response.accessToken, for: .authToken)
                KeychainStore.set(response.refreshToken, for: .refreshToken)
            }
            return response.accessToken
        }
        inflight = task

        do {
            let newAccess = try await task.value
            inflight = nil
            return newAccess
        } catch {
            inflight = nil
            // Only clear the session when the backend actively rejected the
            // refresh token. Transient errors (no network, DNS hiccup,
            // certificate handshake failure) MUST NOT kick the user out —
            // they'd lose access to local crisis contacts mid-incident.
            if Self.isSessionExpired(error) {
                await clearSessionAndNotify()
                throw BackendAuthError.unauthorized
            }
            throw error
        }
    }

    private static func isSessionExpired(_ error: Error) -> Bool {
        if let authError = error as? BackendAuthError {
            switch authError {
            case .unauthorized, .invalidCredentials:
                return true
            case .invalidResponse, .invalidURL, .serverError:
                return false
            }
        }
        return false
    }

    private func clearSessionAndNotify() async {
        await MainActor.run {
            KeychainStore.delete(.authToken)
            KeychainStore.delete(.refreshToken)
            NotificationCenter.default.post(name: .neuremiaSessionExpired, object: nil)
        }
    }
}

enum BackendAuthClient {
    static let live: BackendAPI = LiveBackendAPI()

    static var baseURL: URL { BackendConfiguration.baseURL.appending(path: "v1") }

    static func endpointURL(path: String) -> URL {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let url = baseURL.appending(path: String(parts.first ?? ""))
        guard parts.count == 2,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.query = String(parts[1])
        return components.url ?? url
    }

    private static let timeoutInterval: TimeInterval = 30

    /// URLSession used for backend traffic. Production: pinned delegate.
    /// Tests swap this for `URLSession.shared` so MockURLProtocol can
    /// intercept requests.
    nonisolated(unsafe) static var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.httpAdditionalHeaders = ["Cache-Control": "no-store"]
        return URLSession(
            configuration: config,
            delegate: CertificatePinningDelegate(),
            delegateQueue: nil
        )
    }()

    static func login(email: String, password: String) async throws -> BackendLoginResponse {
        let url = endpointURL(path: "auth/login")
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(BackendLoginResponse.self, from: data)
        case 401:
            throw BackendAuthError.invalidCredentials
        default:
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
    }

    static func register(email: String, password: String, fullName: String) async throws -> BackendLoginResponse {
        let url = endpointURL(path: "auth/register")
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RegisterRequest(email: email, password: password, fullName: fullName))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }

        if (try? JSONDecoder().decode(MessageResponse.self, from: data)) != nil {
            throw BackendAuthError.serverError("Não foi possível concluir o cadastro. Se você já tem uma conta, toque em Já tenho conta para entrar.")
        }
        return try JSONDecoder().decode(BackendLoginResponse.self, from: data)
    }

    static func requestPasswordReset(email: String) async throws -> String {
        let response: MessageResponse = try await postReturning(path: "auth/password-reset", payload: PasswordResetRequest(email: email))
        return response.message
    }

    static func confirmPasswordReset(email: String, resetCode: String, newPassword: String) async throws -> String {
        let response: MessageResponse = try await postReturning(
            path: "auth/password-reset/confirm",
            payload: PasswordResetConfirmRequest(email: email, resetCode: resetCode, newPassword: newPassword)
        )
        return response.message
    }

    static func refresh(refreshToken: String) async throws -> BackendLoginResponse {
        try await postReturning(path: "auth/refresh", payload: RefreshRequest(refreshToken: refreshToken))
    }

    static func logout(refreshToken: String, accessToken: String) async throws {
        // Intentionally bypass `withAuthRetry`: logout is fire-and-forget. If
        // the access token is rejected, we DO NOT want the coordinator to
        // burn the user's current refresh token rotating for a doomed call —
        // especially relevant if the user already re-logged in with new
        // tokens (Sprint 11, S40).
        try await rawPost(path: "auth/logout", payload: RefreshRequest(refreshToken: refreshToken), token: accessToken)
    }

    static func inviteClinicianAccess(patientEmail: String, token: String) async throws -> BackendClinicianInvite {
        try await postReturning(path: "clinician/invites", payload: LinkPatientRequest(patientEmail: patientEmail), token: token)
    }

    static func pendingInvites(token: String) async throws -> [BackendClinicianInvite] {
        try await get(path: "me/invites", token: token)
    }

    static func acceptInvite(id: Int, token: String) async throws -> BackendClinicianInvite {
        try await postReturning(path: "me/invites/\(id)/accept", payload: EmptyBody(), token: token)
    }

    static func revokeInvite(id: Int, token: String) async throws -> BackendClinicianInvite {
        try await postReturning(path: "me/invites/\(id)/revoke", payload: EmptyBody(), token: token)
    }

    static func linkedClinicians(token: String) async throws -> [BackendLinkedClinician] {
        try await get(path: "me/linked-clinicians", token: token)
    }

    static func revokeClinicalAccess(clinicianId: Int, token: String) async throws {
        try await delete(path: "me/clinical-access/\(clinicianId)", token: token)
    }

    static func clinicianPatients(token: String) async throws -> [BackendUser] {
        let response: BackendPatientListResponse = try await get(path: "clinician/patients?limit=200", token: token)
        return response.items
    }

    static func clinicianSentInvites(token: String) async throws -> [BackendSentInvite] {
        try await get(path: "clinician/invites", token: token)
    }

    static func patientCheckIns(patientId: Int, token: String) async throws -> [BackendDailyCheckIn] {
        try await get(path: "patients/\(patientId)/checkins", token: token)
    }

    static func patientAssessments(patientId: Int, token: String) async throws -> [BackendScaleAssessment] {
        try await get(path: "patients/\(patientId)/assessments", token: token)
    }

    static func patientAlerts(patientId: Int, token: String) async throws -> [BackendClinicalAlert] {
        try await get(path: "patients/\(patientId)/alerts", token: token)
    }

    static func patientReports(patientId: Int, token: String) async throws -> [BackendClinicalReport] {
        try await get(path: "patients/\(patientId)/reports", token: token)
    }

    static func predictTemporalRisk(patientId: Int, payload: BackendTemporalRiskPredictionPayload, token: String) async throws -> BackendTemporalRiskPrediction {
        try await postReturning(path: "patients/\(patientId)/temporal-risk/predict", payload: payload, token: token)
    }

    static func modelValidationReport(token: String) async throws -> BackendModelValidationReport {
        try await get(path: "clinician/model-validation/latest", token: token)
    }

    static func clinicalTasks(patientId: Int? = nil, token: String) async throws -> [BackendClinicalTask] {
        if let patientId {
            return try await get(path: "patients/\(patientId)/clinical-tasks", token: token)
        }
        return try await get(path: "clinician/clinical-tasks?status=open", token: token)
    }

    static func updateClinicalAlertWorkflow(alertId: Int, payload: BackendClinicalAlertWorkflowPayload, token: String) async throws -> BackendClinicalAlert {
        try await patchReturning(path: "clinical-alerts/\(alertId)/workflow", payload: payload, token: token)
    }

    static func createCheckIn(_ payload: BackendDailyCheckInPayload, token: String) async throws {
        try await post(path: "checkins", payload: payload, token: token)
    }

    static func createAssessment(_ payload: BackendScaleAssessmentPayload, token: String) async throws {
        try await post(path: "assessments", payload: payload, token: token)
    }

    static func createReport(_ payload: BackendClinicalReportPayload, token: String) async throws {
        try await post(path: "reports", payload: payload, token: token)
    }

    static func registerPushToken(token deviceToken: String, platform: String, token authToken: String) async throws {
        try await post(path: "devices/push-token", payload: PushTokenPayload(token: deviceToken, platform: platform), token: authToken)
    }

    static func dispatchCriticalAlert(_ payload: BackendCriticalAlertPayload, token: String) async throws -> BackendCriticalAlertDispatch {
        try await postReturning(path: "critical-alerts/dispatch", payload: payload, token: token)
    }

    static func acknowledgeCriticalAlert(dispatchId: String, payload: BackendCriticalAlertAcknowledgementPayload, token: String) async throws -> BackendCriticalAlertDispatch {
        try await postReturning(path: "critical-alerts/\(dispatchId)/acknowledge", payload: payload, token: token)
    }

    static func caregivers(token: String) async throws -> [BackendCaregiverContact] {
        try await get(path: "caregivers", token: token)
    }

    static func createCaregiver(_ payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact {
        try await postReturning(path: "caregivers", payload: payload, token: token)
    }

    static func updateCaregiver(id: Int, payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact {
        try await patchReturning(path: "caregivers/\(id)", payload: payload, token: token)
    }

    static func deleteCaregiver(id: Int, token: String) async throws {
        try await delete(path: "caregivers/\(id)", token: token)
    }

    // MARK: - LGPD / data subject rights

    static func exportAccount(token: String) async throws -> Data {
        try await withAuthRetry(token: token) { activeToken in
            try await rawExportAccount(token: activeToken)
        }
    }

    private static func rawExportAccount(token: String) async throws -> Data {
        let url = endpointURL(path: "me/export")
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
        return data
    }

    static func auditLogs(token: String) async throws -> [BackendAuditLog] {
        try await get(path: "me/audit-logs", token: token)
    }

    static func deleteOldClinicalData(daysOlderThan: Int, token: String) async throws -> BackendRetentionDeleteResponse {
        try await deleteReturning(path: "me/clinical-data?days_older_than=\(max(daysOlderThan, 1))", token: token)
    }

    static func deleteAccount(token: String) async throws -> BackendAccountDeleteResponse {
        try await deleteReturning(path: "me", token: token)
    }

    // M4 — Biometric consent sync with backend consent registry (LGPD Art. 9 §1).
    static func grantBiometricConsent(token: String) async throws {
        struct ConsentPayload: Encodable {
            let purpose: String
            let policy_version: String
        }
        try await rawPost(
            path: "me/consents",
            payload: ConsentPayload(purpose: "biometric_processing", policy_version: "1.0"),
            token: token
        )
    }

    static func revokeBiometricConsent(token: String) async throws {
        try await rawDelete(path: "me/consents/biometric_processing", token: token)
    }

    // MARK: - Private helpers

    static func decodeServerError(from data: Data, status: Int) -> BackendAuthError {
        if status == 401 {
            return .unauthorized
        }
        if let detail = try? JSONDecoder().decode(ErrorDetail.self, from: data) {
            return .serverError(detail.detail)
        }
        return .serverError("Erro do servidor: \(status)")
    }

    // MARK: - Authenticated helpers with transparent refresh

    /// Wraps an authenticated HTTP attempt with automatic refresh-on-401.
    /// `attempt` receives the token to use. If the closure throws
    /// `.unauthorized`, the coordinator refreshes the session and the closure
    /// is invoked a second time with the new token. Refresh failure surfaces
    /// the original `.unauthorized`.
    private static func withAuthRetry<T>(
        token: String,
        attempt: (String) async throws -> T
    ) async throws -> T {
        do {
            return try await attempt(token)
        } catch BackendAuthError.unauthorized {
            let refreshed = try await SessionRefreshCoordinator.shared.refresh()
            return try await attempt(refreshed)
        }
    }

    private static func post<T: Encodable>(path: String, payload: T, token: String) async throws {
        try await withAuthRetry(token: token) { activeToken in
            try await rawPost(path: path, payload: payload, token: activeToken)
        }
    }

    private static func get<R: Decodable>(path: String, token: String) async throws -> R {
        try await withAuthRetry(token: token) { activeToken in
            try await rawGet(path: path, token: activeToken)
        }
    }

    private static func postReturning<T: Encodable, R: Decodable>(path: String, payload: T, token: String) async throws -> R {
        try await withAuthRetry(token: token) { activeToken in
            try await rawPostReturning(path: path, payload: payload, token: activeToken)
        }
    }

    // MARK: - Raw helpers (no retry)

    private static func rawPost<T: Encodable>(path: String, payload: T, token: String) async throws {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
    }

    private static func rawGet<R: Decodable>(path: String, token: String) async throws -> R {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func rawPostReturning<T: Encodable, R: Decodable>(path: String, payload: T, token: String) async throws -> R {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func postReturning<T: Encodable, R: Decodable>(path: String, payload: T) async throws -> R {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func patchReturning<T: Encodable, R: Decodable>(path: String, payload: T, token: String) async throws -> R {
        try await withAuthRetry(token: token) { activeToken in
            try await rawPatchReturning(path: path, payload: payload, token: activeToken)
        }
    }

    private static func delete(path: String, token: String) async throws {
        try await withAuthRetry(token: token) { activeToken in
            try await rawDelete(path: path, token: activeToken)
        }
    }

    private static func deleteReturning<R: Decodable>(path: String, token: String) async throws -> R {
        try await withAuthRetry(token: token) { activeToken in
            try await rawDeleteReturning(path: path, token: activeToken)
        }
    }

    private static func rawPatchReturning<T: Encodable, R: Decodable>(path: String, payload: T, token: String) async throws -> R {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func rawDelete(path: String, token: String) async throws {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
    }

    private static func rawDeleteReturning<R: Decodable>(path: String, token: String) async throws -> R {
        let url = endpointURL(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    private struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    private struct PasswordResetRequest: Encodable {
        let email: String
    }

    private struct PasswordResetConfirmRequest: Encodable {
        let email: String
        let resetCode: String
        let newPassword: String

        enum CodingKeys: String, CodingKey {
            case email
            case resetCode = "reset_code"
            case newPassword = "new_password"
        }
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct RegisterRequest: Encodable {
        let email: String
        let password: String
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case email
            case password
            case fullName = "full_name"
        }
    }

    private struct LinkPatientRequest: Encodable {
        let patientEmail: String

        enum CodingKeys: String, CodingKey {
            case patientEmail = "patient_email"
        }
    }

    private struct EmptyBody: Encodable {}

    private struct ErrorDetail: Decodable {
        let detail: String
    }

    private struct MessageResponse: Decodable {
        let message: String
    }
}
