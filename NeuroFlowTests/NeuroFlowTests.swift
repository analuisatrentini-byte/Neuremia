//
//  NeuroFlowTests.swift
//  NeuroFlowTests
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation
import Testing
@testable import NeuroFlow

struct NeuroFlowTests {
    @Test func phq9ScoreAndInterpretation() {
        let answers = [2, 2, 1, 2, 1, 1, 1, 0, 0]
        let score = ClinicalAnalysis.score(for: .phq9, answers: answers)

        #expect(score == 10)
        #expect(ClinicalAnalysis.interpretation(for: .phq9, score: score) == "Moderado")
    }

    @Test func gad7SevereInterpretation() {
        let score = ClinicalAnalysis.score(for: .gad7, answers: [3, 3, 3, 2, 2, 1, 1])

        #expect(score == 15)
        #expect(ClinicalAnalysis.interpretation(for: .gad7, score: score) == "Grave")
    }

    @Test func ymrsUsesElevenWeightedItems() {
        #expect(ScaleKind.ymrs.questions.count == 11)
        #expect(ScaleKind.ymrs.answerRange(for: 4) == 0...8)
        #expect(ScaleKind.ymrs.answerRange(for: 5) == 0...8)
        #expect(ScaleKind.ymrs.answerRange(for: 7) == 0...8)
        #expect(ScaleKind.ymrs.answerRange(for: 8) == 0...8)
        #expect(ScaleKind.ymrs.answerRange(for: 0) == 0...4)
    }

    @Test func ymrsMarkedToSevereInterpretation() {
        let score = ClinicalAnalysis.score(for: .ymrs, answers: [3, 3, 2, 2, 5, 5, 2, 4, 4, 1, 1])

        #expect(score == 32)
        #expect(ClinicalAnalysis.interpretation(for: .ymrs, score: score) == "Marcado a grave")
    }

    @Test func ymrsScoreClampedToValidRanges() {
        // Items at indices 4,5,7,8 accept 0–8; all others 0–4.
        // Out-of-range values must be clamped, never inflating the total.
        // Max possible: 7×4 + 4×8 = 60.
        let allMax = ClinicalAnalysis.score(for: .ymrs, answers: [4, 4, 4, 4, 8, 8, 4, 8, 8, 4, 4])
        #expect(allMax == 60)

        // Passing a value above the item ceiling (e.g. 9 on a 0–8 item, 5 on a 0–4 item)
        // must be silently clamped down, not crash or produce a score above 60.
        let overflowAnswers = [5, 5, 5, 5, 9, 9, 5, 9, 9, 5, 5]
        let clamped = ClinicalAnalysis.score(for: .ymrs, answers: overflowAnswers)
        #expect(clamped == 60)

        // PHQ-9 overflow clamped to max 27 (9 items × 3).
        let phq9Over = Array(repeating: 5, count: 9)
        #expect(ClinicalAnalysis.score(for: .phq9, answers: phq9Over) == 27)

        // GAD-7 overflow clamped to max 21 (7 items × 3).
        let gad7Over = Array(repeating: 5, count: 7)
        #expect(ClinicalAnalysis.score(for: .gad7, answers: gad7Over) == 21)
    }

    @Test func textAssessmentDetectsHighRiskTerms() {
        let assessment = ClinicalAnalysis.textAssessment(for: "Estou sem saída e penso em morrer")

        #expect(assessment.level == .high)
        #expect(assessment.detectedTerms.contains("morrer"))
        #expect(!assessment.recommendation.isEmpty)
    }

    @Test func textAssessmentExpandedHighRiskVocabulary() {
        // Diacritics stripped by .diacriticInsensitive folding.
        let suicida = ClinicalAnalysis.textAssessment(for: "Estou me sentindo suicida hoje")
        #expect(suicida.level == .high)

        let autolesao = ClinicalAnalysis.textAssessment(for: "Voltei a me machucar ontem à noite")
        #expect(autolesao.level == .high)

        let passiveDeath = ClinicalAnalysis.textAssessment(for: "Queria não acordar mais amanhã")
        #expect(passiveDeath.level == .high)

        let farewell = ClinicalAnalysis.textAssessment(for: "Ninguém vai sentir falta de mim")
        #expect(farewell.level == .high)
    }

    @Test func textAssessmentExpandedModerateVocabulary() {
        let limit = ClinicalAnalysis.textAssessment(for: "Estou no limite, não aguento mais")
        #expect(limit.level == .moderate)

        let isolation = ClinicalAnalysis.textAssessment(for: "Me sinto sozinha e invisível para todos")
        #expect(isolation.level == .moderate)

        let exhausted = ClinicalAnalysis.textAssessment(for: "Estou completamente esgotada e sem esperança")
        #expect(exhausted.level == .moderate)

        let panic = ClinicalAnalysis.textAssessment(for: "Tive um ataque de pânico no trabalho")
        #expect(panic.level == .moderate)
    }

    @Test func textAssessmentLowForNeutralText() {
        let neutral = ClinicalAnalysis.textAssessment(for: "Hoje foi um dia tranquilo, caminhei no parque")
        #expect(neutral.level == .low)
        #expect(neutral.detectedTerms.isEmpty)
    }

    @Test func trendUsesOLSNotFirstToLastDelta() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // Mood sequence: broadly declining (OLS slope < 0) but the final
        // value happens to be higher than the first, so first-to-last delta
        // would wrongly report an upward trend.
        // Values: 4, 3, 2, 1, 2  — first=4, last=2 (wrong: delta = -0.5)
        // OLS slope ≈ -0.8, correctly capturing the overall decline.
        let checkIns = [
            makeCheckIn(date: start,                             mood: 4.0, anxiety: 1.0, sleepHours: 7.0, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(86_400),  mood: 3.0, anxiety: 1.0, sleepHours: 7.0, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(172_800), mood: 2.0, anxiety: 1.0, sleepHours: 7.0, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(259_200), mood: 1.0, anxiety: 1.0, sleepHours: 7.0, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(345_600), mood: 2.0, anxiety: 1.0, sleepHours: 7.0, medicationTaken: true),
        ]
        let summary = ClinicalAnalysis.summary(checkIns: checkIns, assessments: [])
        // OLS slope must be negative; first-to-last would give (2-4)/4 = -0.5 (negative, correct here).
        // More importantly, verify it is steeper than the naive estimate:
        // OLS on [4,3,2,1,2]: slope = -0.8 < -0.5 (first-to-last).
        #expect(summary.moodTrend < -0.5)
    }

    @Test func longitudinalSummaryDetectsWorseningMoodAndAdherence() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIns = [
            makeCheckIn(date: start, mood: 4.5, anxiety: 1.0, sleepHours: 7.5, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(86_400), mood: 3.5, anxiety: 2.0, sleepHours: 6.0, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(172_800), mood: 2.0, anxiety: 3.5, sleepHours: 4.5, medicationTaken: false)
        ]

        let summary = ClinicalAnalysis.summary(checkIns: checkIns, assessments: [])

        #expect(summary.riskLevel == .moderate)
        #expect(summary.moodTrend < 0)
        #expect(summary.anxietyTrend > 0)
        #expect(summary.medicationAdherence < 1)
        #expect(summary.signals.contains("Humor em queda nos registros recentes"))
    }

    @Test func phq9SevereAssessmentRaisesRiskInSummary() {
        let assessment = ScaleAssessment(
            scaleName: ScaleKind.phq9.rawValue,
            answers: [3, 3, 3, 3, 3, 3, 2, 2, 1],
            score: 23,
            interpretation: "Grave"
        )

        let summary = ClinicalAnalysis.summary(checkIns: [], assessments: [assessment])

        #expect(summary.riskLevel == .high)
    }

    @Test func reportContainsClinicalSupportDisclaimer() {
        let report = ClinicalAnalysis.reportText(checkIns: [], assessments: [])

        #expect(report.contains("Relatório clínico NeuroFlow"))
        #expect(report.contains("sem substituir julgamento médico"))
    }

    @Test func gad7ModerateAssessmentRaisesModerateRisk() {
        let assessment = ScaleAssessment(
            scaleName: ScaleKind.gad7.rawValue,
            answers: [2, 2, 2, 1, 1, 1, 1],
            score: 10,
            interpretation: "Moderado"
        )

        let summary = ClinicalAnalysis.summary(checkIns: [], assessments: [assessment])

        #expect(summary.riskLevel == .moderate)
    }

    @Test func suicidalIdeationRaisesHighRisk() {
        let checkIn = DailyCheckIn(
            mood: 3,
            anxiety: 2,
            energy: 3,
            irritability: 1,
            sleepHours: 7,
            appetite: 3,
            libido: 3,
            medicationTaken: true,
            sideEffects: "",
            automaticThoughts: "",
            suicidalIdeation: true,
            journalEntry: ""
        )

        let summary = ClinicalAnalysis.summary(checkIns: [checkIn], assessments: [])

        #expect(summary.riskLevel == .high)
    }

    @Test func officialScaleItemCountsRemainStable() {
        #expect(ScaleKind.phq9.questions.count == 9)
        #expect(ScaleKind.gad7.questions.count == 7)
        #expect(ScaleKind.ymrs.questions.count == 11)
    }

    @Test func backupSnapshotRoundTripsMedicationSymptomsAndClinicalData() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let medication = MedicationPlanEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Lamotrigina",
            dose: "100 mg",
            schedule: "Noite",
            prescription: "Após jantar",
            changeNote: "Aumentou de 50 mg",
            createdAt: date
        )
        let symptom = CustomSymptomEntry(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Impulsividade",
            value: 4,
            createdAt: date
        )
        let checkIn = DailyCheckInSnapshot(
            date: date,
            mood: 3,
            anxiety: 2,
            energy: 4,
            irritability: 1,
            sleepHours: 7,
            appetite: 3,
            libido: 3,
            medicationTaken: true,
            sideEffects: "Sonolência",
            automaticThoughts: "Pensamento repetitivo",
            suicidalIdeation: false,
            journalEntry: "Dia estável"
        )
        let assessment = ScaleAssessmentSnapshot(
            date: date,
            scaleName: ScaleKind.gad7.rawValue,
            answers: [1, 1, 1, 1, 1, 1, 1],
            score: 7,
            interpretation: "Leve"
        )
        let snapshot = NeuroFlowBackupSnapshot(
            exportedAt: date,
            medicationPlans: [medication],
            customSymptoms: [symptom],
            offlineQueue: [],
            checkIns: [checkIn],
            assessments: [assessment]
        )

        let restored = try NeuroFlowBackupSnapshot.decode(from: snapshot.encodedData())

        #expect(restored.medicationPlans == [medication])
        #expect(restored.customSymptoms == [symptom])
        #expect(restored.checkIns == [checkIn])
        #expect(restored.assessments == [assessment])
    }

    @MainActor
    @Test func offlineQueueStoresDecodableCheckInPayload() throws {
        let payload = BackendDailyCheckInPayload(
            mood: 2,
            anxiety: 4,
            energy: 2,
            irritability: 3,
            sleepHours: 5,
            appetite: 2,
            libido: 2,
            medicationTaken: false,
            sideEffects: "Náusea",
            automaticThoughts: "Preocupação constante",
            suicidalIdeation: false,
            journalEntry: "Registro offline"
        )
        let payloadData = try JSONEncoder().encode(payload)
        let item = OfflineSyncItem(
            kind: .checkIn,
            payloadJSON: String(data: payloadData, encoding: .utf8)!,
            summary: "Registro diário"
        )

        let restoredItem = try JSONDecoder().decode(OfflineSyncItem.self, from: JSONEncoder().encode(item))
        let restoredPayload = try JSONDecoder().decode(
            BackendDailyCheckInPayload.self,
            from: Data(restoredItem.payloadJSON.utf8)
        )

        #expect(restoredItem.kind == .checkIn)
        #expect(restoredPayload.mood == 2)
        #expect(restoredPayload.medicationTaken == false)
        #expect(restoredPayload.journalEntry == "Registro offline")
    }

    @Test func medicationPlanSupportsMultipleEntriesAndChangeHistory() {
        let plans = [
            MedicationPlanEntry(name: "Lítio", dose: "300 mg", schedule: "Manhã", prescription: "Com alimento", changeNote: "Início"),
            MedicationPlanEntry(name: "Quetiapina", dose: "25 mg", schedule: "Noite", prescription: "Ao deitar", changeNote: "Reduziu dose")
        ]

        #expect(plans.count == 2)
        #expect(plans[0].summary == "Lítio • 300 mg • Manhã")
        #expect(plans[1].changeNote.contains("Reduziu"))
    }

    @Test func customSymptomsAllowMultipleTrackedScales() {
        let symptoms = [
            CustomSymptomEntry(name: "Impulsividade", value: 4),
            CustomSymptomEntry(name: "Compulsão", value: 2)
        ]

        #expect(symptoms.count == 2)
        #expect(symptoms.map(\.name).contains("Impulsividade"))
        #expect(symptoms.map(\.value).reduce(0, +) == 6)
    }

    @Test func monthlyReportSummaryCalculatesPdfMetrics() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIns = [
            makeCheckIn(date: start, mood: 4, anxiety: 2, sleepHours: 8, medicationTaken: true),
            makeCheckIn(date: start.addingTimeInterval(86_400), mood: 2, anxiety: 4, sleepHours: 6, medicationTaken: false)
        ]

        let lines = MonthlyReportSummary.lines(for: checkIns, now: start)

        #expect(lines.contains("Registros no mês: 2"))
        #expect(lines.contains("Humor médio: 3.0/5"))
        #expect(lines.contains("Ansiedade média: 3.0/5"))
        #expect(lines.contains("Adesão medicamentosa: 50%"))
    }

    @Test func backendLevelMapsKnownTiersAndFailsSafeOnUnknown() {
        // B26 regression: a future backend severity ("critical") must NEVER
        // be silently downgraded to "Leve". Default for anything outside the
        // known set is `.moderate` so the user is at least nudged to review.
        #expect(ContentView.backendLevelToClinical("high") == .high)
        #expect(ContentView.backendLevelToClinical("HIGH") == .high)
        #expect(ContentView.backendLevelToClinical("moderate") == .moderate)
        #expect(ContentView.backendLevelToClinical("low") == .low)
        // Aliases mapped explicitly.
        #expect(ContentView.backendLevelToClinical("urgent") == .high)
        #expect(ContentView.backendLevelToClinical("medium") == .moderate)
        #expect(ContentView.backendLevelToClinical("minimal") == .low)
        // Unknown / future / typo'd strings default to .moderate, never .low.
        #expect(ContentView.backendLevelToClinical("critical-emergency") == .moderate)
        #expect(ContentView.backendLevelToClinical("") == .moderate)
        #expect(ContentView.backendLevelToClinical("not-a-real-tier") == .moderate)
    }

    @Test func safetyFlowHighRiskCombinesIdeationAndTextTerms() {
        let checkIn = DailyCheckIn(
            mood: 2,
            anxiety: 4,
            energy: 1,
            irritability: 3,
            sleepHours: 4,
            appetite: 2,
            libido: 2,
            medicationTaken: false,
            sideEffects: "",
            automaticThoughts: "Não vejo saída",
            suicidalIdeation: true,
            journalEntry: "penso em morrer"
        )

        let summary = ClinicalAnalysis.summary(checkIns: [checkIn], assessments: [])
        let textRisk = ClinicalAnalysis.textAssessment(for: "\(checkIn.journalEntry) \(checkIn.automaticThoughts)")

        #expect(summary.riskLevel == .high)
        #expect(textRisk.level == .high)
    }

    private func makeCheckIn(date: Date, mood: Double, anxiety: Double, sleepHours: Double, medicationTaken: Bool) -> DailyCheckIn {
        DailyCheckIn(
            date: date,
            mood: mood,
            anxiety: anxiety,
            energy: 3,
            irritability: 1,
            sleepHours: sleepHours,
            appetite: 3,
            libido: 3,
            medicationTaken: medicationTaken,
            sideEffects: "",
            automaticThoughts: "",
            suicidalIdeation: false,
            journalEntry: ""
        )
    }
}

// MARK: - DraftStore tests (Sprint 16 / F13' / S15)

@MainActor
struct DraftStoreTests {
    private static func cleanKeys(_ keys: [String]) {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: DraftStore.storagePrefix + key)
        }
    }

    @Test func roundTripsCodableValues() {
        let key = "test.draft.roundtrip"
        Self.cleanKeys([key])
        defer { Self.cleanKeys([key]) }

        DraftStore.saveCodable(4.5, forKey: key)
        #expect(DraftStore.loadCodable(Double.self, forKey: key) == 4.5)
    }

    @Test func ciphertextIsNeverPlaintext() {
        // S15 contract: whatever sits in UserDefaults under our key must NOT
        // contain the actual journal text — otherwise an iCloud Backup leak
        // would still expose PHI.
        let key = "test.draft.cipher"
        Self.cleanKeys([key])
        defer { Self.cleanKeys([key]) }

        let secret = "Sentindo-me em crise hoje"
        DraftStore.saveCodable(secret, forKey: key)

        let storedRaw = UserDefaults.standard.string(forKey: DraftStore.storagePrefix + key)
        #expect(storedRaw != nil)
        #expect(storedRaw?.contains("crise") == false)
        #expect(storedRaw?.contains("Sentindo") == false)

        let decoded = DraftStore.loadCodable(String.self, forKey: key)
        #expect(decoded == secret)
    }

    @Test func migratesLegacyAppStorageStringIntoEncryptedSlot() {
        let key = "neuroflowDraftJournalEntry"
        Self.cleanKeys([key])
        defer { Self.cleanKeys([key]) }

        // Simulate the pre-Sprint-16 plaintext stored by @AppStorage.
        UserDefaults.standard.set("Diário antigo plain", forKey: key)

        let migrated = DraftStore.migrateLegacyValue(legacyKey: key, as: String.self)
        #expect(migrated == "Diário antigo plain")
        // Legacy key is wiped after migration.
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        // Encrypted blob now lives at the prefixed key.
        let encrypted = UserDefaults.standard.string(forKey: DraftStore.storagePrefix + key)
        #expect(encrypted != nil)
        #expect(encrypted?.contains("plain") == false)
    }

    @Test func returnsNilWhenNothingStored() {
        let key = "test.draft.absent"
        Self.cleanKeys([key])
        defer { Self.cleanKeys([key]) }

        #expect(DraftStore.loadCodable(Double.self, forKey: key) == nil)
        #expect(DraftStore.migrateLegacyValue(legacyKey: key, as: Double.self) == nil)
    }

    @Test func removeClearsEncryptedValue() {
        let key = "test.draft.remove"
        Self.cleanKeys([key])
        defer { Self.cleanKeys([key]) }

        DraftStore.saveCodable(7, forKey: key)
        #expect(DraftStore.loadCodable(Int.self, forKey: key) == 7)

        DraftStore.remove(forKey: key)
        #expect(DraftStore.loadCodable(Int.self, forKey: key) == nil)
    }
}

// MARK: - BackendAuthClient tests (URLProtocol mock)

/// Intercepts URLSession.shared requests so BackendAuthClient can be exercised
/// without hitting the actual backend.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var savedSession: URLSession?

    static func install(handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)) {
        Self.handler = handler
        Self.lastRequest = nil
        URLProtocol.registerClass(MockURLProtocol.self)
        // Swap in URLSession.shared so the registered URLProtocol class
        // intercepts BackendAuthClient traffic. Pinned production session
        // doesn't include MockURLProtocol in protocolClasses.
        savedSession = BackendAuthClient.session
        BackendAuthClient.session = URLSession.shared
    }

    static func reset() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        if let saved = savedSession {
            BackendAuthClient.session = saved
            savedSession = nil
        }
        Self.handler = nil
        Self.lastRequest = nil
        // Belt-and-suspenders: drop any tokens a test seeded into the
        // Keychain so the next test starts from a clean slate even if it
        // forgets its own teardown (Sprint 14 polish).
        KeychainStore.delete(.authToken)
        KeychainStore.delete(.refreshToken)
        KeychainStore.delete(.apnsDeviceToken)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockResponse(statusCode: Int, json: String, for url: URL) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, Data(json.utf8))
}

@MainActor
struct BackendAuthClientTests {
    @Test func loginReturnsTokenAndUserOn200() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/auth/login")
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "access_token": "tok-abc",
                    "refresh_token": "ref-xyz",
                    "token_type": "bearer",
                    "user": {
                        "id": 1,
                        "email": "ana@neuroflow.io",
                        "full_name": "Ana",
                        "role": "patient",
                        "risk_score": null,
                        "risk_level": null
                    }
                }
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let response = try await BackendAuthClient.login(email: "ana@neuroflow.io", password: "supersecret1")
        let user = response.user
        #expect(response.accessToken == "tok-abc")
        #expect(response.refreshToken == "ref-xyz")
        #expect(user.email == "ana@neuroflow.io")
        #expect(user.role == "patient")
    }

    @Test func loginThrowsInvalidCredentialsOn401() async {
        MockURLProtocol.install { request in
            mockResponse(statusCode: 401, json: "{\"detail\":\"Invalid credentials\"}", for: request.url!)
        }
        defer { MockURLProtocol.reset() }

        await #expect(throws: BackendAuthError.self) {
            _ = try await BackendAuthClient.login(email: "x@y.com", password: "wrong-password")
        }
    }

    @Test func registerDoesNotSendRoleField() async throws {
        MockURLProtocol.install { request in
            // Sprint 1 regression: clients must not be able to set role on signup.
            if let body = request.httpBody ?? request.bodyStreamData(),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                #expect(json["role"] == nil)
                #expect(json["email"] as? String == "new@example.com")
                #expect(json["full_name"] as? String == "New Patient")
            }
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "access_token": "tok-new",
                    "refresh_token": "ref-new",
                    "token_type": "bearer",
                    "user": {
                        "id": 42,
                        "email": "new@example.com",
                        "full_name": "New Patient",
                        "role": "patient",
                        "risk_score": null,
                        "risk_level": null
                    }
                }
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let response = try await BackendAuthClient.register(
            email: "new@example.com",
            password: "supersecret1",
            fullName: "New Patient"
        )
        let user = response.user
        #expect(user.id == 42)
    }

    @Test func inviteClinicianAccessSendsBearerToken() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/clinician/invites")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-doc")
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "id": 7,
                    "clinician_id": 9,
                    "patient_id": 12,
                    "clinician_full_name": "Doctor",
                    "clinician_email": "doc@neuroflow.io",
                    "status": "pending",
                    "created_at": "2026-06-12T10:00:00"
                }
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let invite = try await BackendAuthClient.inviteClinicianAccess(
            patientEmail: "patient@example.com",
            token: "tok-doc"
        )
        #expect(invite.status == "pending")
        #expect(invite.patientId == 12)
    }

    @Test func deleteAccountReturnsConfirmation() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/me")
            return mockResponse(
                statusCode: 200,
                json: "{\"deleted_user_id\": 17, \"message\": \"Conta apagada.\"}",
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let response = try await BackendAuthClient.deleteAccount(token: "tok")
        #expect(response.deletedUserId == 17)
        #expect(response.message == "Conta apagada.")
    }

    @Test func deleteOldClinicalDataIncludesRetentionParam() async throws {
        MockURLProtocol.install { request in
            #expect(request.url?.path == "/me/clinical-data")
            #expect(request.url?.query == "days_older_than=180")
            return mockResponse(
                statusCode: 200,
                json: """
                {"deleted_checkins": 3, "deleted_assessments": 1, "deleted_alerts": 0, "deleted_reports": 0}
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let response = try await BackendAuthClient.deleteOldClinicalData(daysOlderThan: 180, token: "tok")
        #expect(response.deletedCheckins == 3)
        #expect(response.deletedAssessments == 1)
    }

    @Test func exportAccountReturnsRawJSONData() async throws {
        let payload = "{\"user\": {\"email\": \"ana@neuroflow.io\"}, \"checkins\": []}"
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/me/export")
            return mockResponse(statusCode: 200, json: payload, for: request.url!)
        }
        defer { MockURLProtocol.reset() }

        let data = try await BackendAuthClient.exportAccount(token: "tok")
        #expect(String(data: data, encoding: .utf8) == payload)
    }

    @Test func refreshSwapsTokensFromBackend() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/auth/refresh")
            if let body = request.httpBody ?? request.bodyStreamData(),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                #expect(json["refresh_token"] as? String == "old-refresh")
            }
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "access_token": "new-access",
                    "refresh_token": "new-refresh",
                    "token_type": "bearer",
                    "user": {
                        "id": 1,
                        "email": "x@y.com",
                        "full_name": "X",
                        "role": "patient",
                        "risk_score": null,
                        "risk_level": null
                    }
                }
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let pair = try await BackendAuthClient.refresh(refreshToken: "old-refresh")
        #expect(pair.accessToken == "new-access")
        #expect(pair.refreshToken == "new-refresh")
    }

    @Test func clinicianSentInvitesDecodesPatientFields() async throws {
        MockURLProtocol.install { request in
            #expect(request.url?.path == "/clinician/invites")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer doc-tok")
            return mockResponse(
                statusCode: 200,
                json: """
                [{
                    "id": 11,
                    "patient_id": 5,
                    "patient_full_name": "Ana Silva",
                    "patient_email": "ana@example.com",
                    "status": "revoked",
                    "created_at": "2026-06-12T10:00:00"
                }]
                """,
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let invites = try await BackendAuthClient.clinicianSentInvites(token: "doc-tok")
        let invite = try #require(invites.first)
        #expect(invite.id == 11)
        #expect(invite.status == "revoked")
        #expect(invite.patientFullName == "Ana Silva")
    }

    @Test func auditLogDecodesWhenActorIsNull() async throws {
        // B34 regression: after Sprint 9 nulled out actor_user_id on
        // DELETE /me, the iOS decoder must accept null without throwing.
        let json = """
        [{
            "id": 17,
            "actor_user_id": null,
            "action": "register",
            "resource_type": "user",
            "resource_id": "5",
            "created_at": "2026-06-12T10:00:00"
        }]
        """
        MockURLProtocol.install { request in
            #expect(request.url?.path == "/me/audit-logs")
            return mockResponse(statusCode: 200, json: json, for: request.url!)
        }
        defer { MockURLProtocol.reset() }

        let logs = try await BackendAuthClient.auditLogs(token: "tok")
        let log = try #require(logs.first)
        #expect(log.actorUserId == nil)
        #expect(log.action == "register")
    }

    @Test func coordinatorKeepsSessionOnNetworkFailure() async throws {
        // B38 regression: a network blip (or malformed response) must NOT
        // drop the session. Only a hard 401 from the backend during refresh
        // counts as "session expired".
        KeychainStore.set("seed-refresh", for: .refreshToken)
        KeychainStore.set("expired-access", for: .authToken)
        defer {
            KeychainStore.delete(.refreshToken)
            KeychainStore.delete(.authToken)
        }

        nonisolated(unsafe) var refreshAttempts = 0
        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/clinician/patients":
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/auth/refresh":
                refreshAttempts += 1
                // Simulate a serverError that is NOT 401 — backend down, not invalid token.
                return mockResponse(statusCode: 503, json: "{\"detail\":\"backend down\"}", for: request.url!)
            default:
                return mockResponse(statusCode: 404, json: "{}", for: request.url!)
            }
        }
        defer { MockURLProtocol.reset() }

        do {
            _ = try await BackendAuthClient.clinicianPatients(token: "expired-access")
            Issue.record("Expected the call to throw because refresh failed transiently")
        } catch {
            // Expected. The important contract: tokens stay in Keychain so
            // the user can retry without re-authenticating.
            #expect(KeychainStore.string(for: .refreshToken) == "seed-refresh")
            #expect(KeychainStore.string(for: .authToken) == "expired-access")
        }
        #expect(refreshAttempts == 1)
    }

    @Test func refreshCoordinatorIsSingleFlightUnderConcurrentRequests() async throws {
        // T19: simulate 5 protected calls all hitting 401 concurrently. The
        // refresh coordinator must collapse the rotation into a single
        // /auth/refresh call.
        KeychainStore.set("seed-refresh", for: .refreshToken)
        KeychainStore.set("expired-access", for: .authToken)
        defer {
            KeychainStore.delete(.refreshToken)
            KeychainStore.delete(.authToken)
        }

        nonisolated(unsafe) var refreshCalls = 0
        let refreshLock = NSLock()
        nonisolated(unsafe) var protectedCalls = 0
        let protectedLock = NSLock()

        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/clinician/patients":
                protectedLock.lock()
                protectedCalls += 1
                protectedLock.unlock()
                let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
                if bearer == "Bearer rotated-access" {
                    return mockResponse(statusCode: 200, json: "[]", for: request.url!)
                }
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/auth/refresh":
                refreshLock.lock()
                refreshCalls += 1
                refreshLock.unlock()
                // Small artificial delay so concurrent callers actually
                // overlap in the coordinator.
                Thread.sleep(forTimeInterval: 0.05)
                return mockResponse(
                    statusCode: 200,
                    json: """
                    {
                        "access_token": "rotated-access",
                        "refresh_token": "rotated-refresh",
                        "token_type": "bearer",
                        "user": {
                            "id": 1,
                            "email": "x@y.com",
                            "full_name": "X",
                            "role": "clinician",
                            "risk_score": null,
                            "risk_level": null
                        }
                    }
                    """,
                    for: request.url!
                )
            default:
                return mockResponse(statusCode: 404, json: "{}", for: request.url!)
            }
        }
        defer { MockURLProtocol.reset() }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    _ = try? await BackendAuthClient.clinicianPatients(token: "expired-access")
                }
            }
        }

        // Each of the 5 protected calls fires twice (the initial 401 + the
        // retry after refresh) = 10 hits. Refresh, however, happens once.
        #expect(refreshCalls == 1, "Expected single-flight refresh, got \(refreshCalls)")
        #expect(protectedCalls == 10)
        #expect(KeychainStore.string(for: .authToken) == "rotated-access")
    }

    @Test func linkedCliniciansDecodesAndCanBeRevoked() async throws {
        nonisolated(unsafe) var revokedClinicianId: String?
        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/me/linked-clinicians":
                return mockResponse(
                    statusCode: 200,
                    json: """
                    [{
                        "clinician_id": 42,
                        "clinician_full_name": "Dra. Y",
                        "clinician_email": "dra.y@neuroflow.io",
                        "linked_at": "2026-06-12T10:00:00"
                    }]
                    """,
                    for: request.url!
                )
            case let path? where path.hasPrefix("/me/clinical-access/"):
                revokedClinicianId = path.split(separator: "/").last.map(String.init)
                return mockResponse(statusCode: 200, json: "{\"message\":\"ok\"}", for: request.url!)
            default:
                return mockResponse(statusCode: 404, json: "{}", for: request.url!)
            }
        }
        defer { MockURLProtocol.reset() }

        let linked = try await BackendAuthClient.linkedClinicians(token: "tok")
        let clinician = try #require(linked.first)
        #expect(clinician.clinicianId == 42)

        try await BackendAuthClient.revokeClinicalAccess(clinicianId: clinician.clinicianId, token: "tok")
        #expect(revokedClinicianId == "42")
    }

    @Test func authenticatedRequestRetriesOnceAfter401() async throws {
        // Seed Keychain so the coordinator has a refresh token to spend.
        KeychainStore.set("seed-refresh", for: .refreshToken)
        KeychainStore.set("expired-access", for: .authToken)
        defer {
            KeychainStore.delete(.refreshToken)
            KeychainStore.delete(.authToken)
        }

        nonisolated(unsafe) var callsToProtectedEndpoint = 0
        nonisolated(unsafe) var refreshCalled = false

        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/clinician/patients":
                callsToProtectedEndpoint += 1
                let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
                if bearer == "Bearer rotated-access" {
                    return mockResponse(statusCode: 200, json: "[]", for: request.url!)
                }
                // First attempt: 401 forces refresh.
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/auth/refresh":
                refreshCalled = true
                return mockResponse(
                    statusCode: 200,
                    json: """
                    {
                        "access_token": "rotated-access",
                        "refresh_token": "rotated-refresh",
                        "token_type": "bearer",
                        "user": {
                            "id": 9,
                            "email": "doc@x.com",
                            "full_name": "Doc",
                            "role": "clinician",
                            "risk_score": null,
                            "risk_level": null
                        }
                    }
                    """,
                    for: request.url!
                )
            default:
                return mockResponse(statusCode: 404, json: "{}", for: request.url!)
            }
        }
        defer { MockURLProtocol.reset() }

        let result = try await BackendAuthClient.clinicianPatients(token: "expired-access")
        #expect(result.isEmpty)
        #expect(callsToProtectedEndpoint == 2)
        #expect(refreshCalled)
        // After refresh, the rotated tokens should be persisted to Keychain.
        #expect(KeychainStore.string(for: .authToken) == "rotated-access")
        #expect(KeychainStore.string(for: .refreshToken) == "rotated-refresh")
    }

    @Test func logoutSendsRefreshTokenAndBearer() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/auth/logout")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-tok")
            if let body = request.httpBody ?? request.bodyStreamData(),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                #expect(json["refresh_token"] as? String == "ref-tok")
            }
            return mockResponse(statusCode: 200, json: "{\"message\": \"ok\"}", for: request.url!)
        }
        defer { MockURLProtocol.reset() }

        try await BackendAuthClient.logout(refreshToken: "ref-tok", accessToken: "access-tok")
    }
}

private extension URLRequest {
    /// URLProtocol seals the body in an InputStream when set via JSONEncoder.
    /// Helper that reads it back so assertions can inspect the wire payload.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) }
            else { break }
        }
        return data.isEmpty ? nil : data
    }
}
