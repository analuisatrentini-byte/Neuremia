//
//  BackendAuthClient.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation
import Security
import SwiftUI

// MARK: - Keychain storage

/// Secure storage for the JWT and the APNs device token. Replaces the previous
/// UserDefaults-backed @AppStorage that left credentials in plaintext plist files.
enum KeychainStore {
    enum Key: String {
        case authToken = "neuroflow.authToken"
        case apnsDeviceToken = "neuroflow.apnsDeviceToken"
    }

    private static let service = "io.neuroflow.app.secure"

    static func string(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    static func set(_ value: String, for key: Key) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }

        return false
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        SecItemDelete(baseQuery(for: key) as CFDictionary) == errSecSuccess
    }

    /// One-shot migration from the legacy @AppStorage("neuroflowAuthToken")
    /// location. Idempotent: safe to call on every launch.
    static func migrateLegacyTokenIfNeeded() {
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
        ("neuroflowAPNsDeviceToken", .apnsDeviceToken)
    ]

    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }
}

/// SwiftUI property wrapper that behaves like @AppStorage but persists into
/// the Keychain. Lets us flip from @AppStorage to @KeychainStored with a
/// single-character change at each call site.
@propertyWrapper
struct KeychainStored: DynamicProperty {
    @State private var value: String
    private let key: KeychainStore.Key

    init(_ key: KeychainStore.Key) {
        self.key = key
        _value = State(initialValue: KeychainStore.string(for: key) ?? "")
    }

    var wrappedValue: String {
        get { value }
        nonmutating set {
            value = newValue
            if newValue.isEmpty {
                KeychainStore.delete(key)
            } else {
                KeychainStore.set(newValue, for: key)
            }
        }
    }

    var projectedValue: Binding<String> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

// MARK: - Backend configuration

enum BackendConfiguration {
    /// Read from the bundle Info.plist key `NeuroFlowAPIBaseURL`. Falls back to
    /// the local dev backend in DEBUG so the local toolchain keeps working.
    /// Release builds MUST set the key in build settings, e.g.
    /// INFOPLIST_KEY_NeuroFlowAPIBaseURL = https://api.your-domain.com
    static var baseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "NeuroFlowAPIBaseURL") as? String,
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }
        #if DEBUG
        return URL(string: "http://127.0.0.1:8000")!
        #else
        fatalError("NeuroFlowAPIBaseURL is required in Info.plist for release builds")
        #endif
    }
}

// MARK: - DTOs

struct BackendUser: Decodable {
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

struct BackendLoginResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let user: BackendUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
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
    let title: String
    let message: String
    let acknowledged: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case createdAt = "created_at"
        case level
        case title
        case message
        case acknowledged
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

enum BackendAuthClient {
    static var baseURL: URL { BackendConfiguration.baseURL }

    private static let timeoutInterval: TimeInterval = 30

    static func login(email: String, password: String) async throws -> BackendLoginResponse {
        let url = baseURL.appending(path: "auth/login")
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginRequest(email: email, password: password))

        let (data, response) = try await URLSession.shared.data(for: request)
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
        let url = baseURL.appending(path: "auth/register")
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RegisterRequest(email: email, password: password, fullName: fullName))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(BackendLoginResponse.self, from: data)
    }

    static func requestPasswordReset(email: String) async throws -> String {
        let response: MessageResponse = try await postReturning(path: "auth/password-reset", payload: PasswordResetRequest(email: email))
        return response.message
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

    static func clinicianPatients(token: String) async throws -> [BackendUser] {
        try await get(path: "clinician/patients", token: token)
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

    static func caregivers(token: String) async throws -> [BackendCaregiverContact] {
        try await get(path: "caregivers", token: token)
    }

    static func createCaregiver(_ payload: BackendCaregiverPayload, token: String) async throws -> BackendCaregiverContact {
        try await postReturning(path: "caregivers", payload: payload, token: token)
    }

    // MARK: - Private helpers

    private static func decodeServerError(from data: Data, status: Int) -> BackendAuthError {
        if status == 401 {
            return .unauthorized
        }
        if let detail = try? JSONDecoder().decode(ErrorDetail.self, from: data) {
            return .serverError(detail.detail)
        }
        return .serverError("Erro do servidor: \(status)")
    }

    private static func post<T: Encodable>(path: String, payload: T, token: String) async throws {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }
    }

    private static func get<R: Decodable>(path: String, token: String) async throws -> R {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func postReturning<T: Encodable, R: Decodable>(path: String, payload: T, token: String) async throws -> R {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAuthError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw decodeServerError(from: data, status: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    private static func postReturning<T: Encodable, R: Decodable>(path: String, payload: T) async throws -> R {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
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
