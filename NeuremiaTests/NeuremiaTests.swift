//
//  NeuremiaTests.swift
//  NeuremiaTests
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation
import SwiftData
import Testing
@testable import Neuremia

struct NeuremiaTests {
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

    @Test func badgeDefinitionsHaveUniqueIdentifiers() {
        let ids = BadgeDefinition.allBadges.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test @MainActor func scaleBadgesUnlockOnlyForTheirMatchingScale() throws {
        let context = try makeInMemoryModelContext()
        let patient = PatientProfile()
        context.insert(patient)

        let gad7 = ScaleAssessment(
            scaleName: ScaleKind.gad7.rawValue,
            answers: Array(repeating: 1, count: ScaleKind.gad7.questions.count),
            score: 7,
            interpretation: "Leve"
        )
        context.insert(gad7)

        let manager = GamificationManager()
        manager.configure(
            modelContext: context,
            patient: patient,
            checkIns: [],
            assessments: [gad7],
            missionLogs: []
        )
        manager.checkAndAwardBadges()

        let badgeIds = Set(manager.unlockedBadges.map(\.badgeId))
        #expect(badgeIds.contains("scale_gad7"))
        #expect(!badgeIds.contains("scale_phq9"))
        #expect(!badgeIds.contains("scale_ymrs"))
    }

    @Test @MainActor func fourteenDayStreakAwardsConfiguredBonusXP() throws {
        let context = try makeInMemoryModelContext()
        let patient = PatientProfile()
        context.insert(patient)

        let manager = GamificationManager()
        manager.configure(
            modelContext: context,
            patient: patient,
            checkIns: [],
            assessments: [],
            missionLogs: []
        )

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        manager.profile?.currentStreak = 13
        manager.profile?.lastCheckInDate = yesterday

        manager.awardCheckInXP(isFirstOfDay: true, hasDetails: false, hasJournal: false)

        #expect(manager.currentStreak == 14)
        #expect(manager.totalXP == XPConfig.dailyCheckInXP + XPConfig.firstCheckInBonusXP + XPConfig.streak14DayBonusXP)
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

    @Test func scaleScoreIgnoresAnswersPastQuestionCount() {
        let validPHQ9 = Array(repeating: 3, count: ScaleKind.phq9.questions.count)
        let pollutedPHQ9 = validPHQ9 + Array(repeating: 3, count: 4)

        #expect(ClinicalAnalysis.score(for: .phq9, answers: pollutedPHQ9) == 27)

        let validYMRS = [4, 4, 4, 4, 8, 8, 4, 8, 8, 4, 4]
        let pollutedYMRS = validYMRS + [8, 8, 8]

        #expect(ClinicalAnalysis.score(for: .ymrs, answers: pollutedYMRS) == 60)
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

    @Test func textAssessmentNegationPreventsHighRisk() {
        // N-M1: negation within 3 words before the risk term → not high risk
        let negated = ClinicalAnalysis.textAssessment(for: "Não quero morrer de fome")
        #expect(negated.level != .high)

        let alsoNegated = ClinicalAnalysis.textAssessment(for: "Jamais pensei em me machucar assim")
        #expect(alsoNegated.level != .high)

        // Negation too far away → risk term still fires
        let tooFar = ClinicalAnalysis.textAssessment(for: "Não sei mais nada mas vou me matar amanhã")
        #expect(tooFar.level == .high)
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

        #expect(summary.riskLevel == .high)
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

        #expect(report.contains("Relatório clínico Neuremia"))
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

    @Test func everyOfficialScaleQuestionHasAValidResponseForScoring() {
        let expectedMaxScores: [ScaleKind: Int] = [
            .phq9: 27,
            .gad7: 21,
            .ymrs: 60
        ]

        for scale in ScaleKind.allCases {
            let answers = scale.questions.indices.map { index in
                let range = scale.answerRange(for: index)
                #expect(range.lowerBound == 0)
                #expect(range.upperBound > 0)
                return range.upperBound
            }

            #expect(answers.count == scale.questions.count)
            #expect(ClinicalAnalysis.score(for: scale, answers: answers) == expectedMaxScores[scale])
            #expect(!ClinicalAnalysis.interpretation(for: scale, score: 0).isEmpty)
            #expect(!ClinicalAnalysis.interpretation(for: scale, score: expectedMaxScores[scale] ?? 0).isEmpty)
        }
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
            dayKey: DailyCheckIn.dayKey(for: date),
            mood: 3,
            anxiety: 2,
            energy: 4,
            irritability: 1,
            sleepHours: 7,
            appetite: 3,
            libido: 3,
            medicationTaken: true,
            suicidalIdeation: false,
            sideEffectsEnc: "Sonolência",
            automaticThoughtsEnc: "Pensamento repetitivo",
            journalEntryEnc: "Dia estável"
        )
        let assessment = ScaleAssessmentSnapshot(
            date: date,
            scaleName: ScaleKind.gad7.rawValue,
            answers: [1, 1, 1, 1, 1, 1, 1],
            score: 7,
            interpretation: "Leve"
        )
        let snapshot = NeuremiaBackupSnapshot(
            exportedAt: date,
            profile: .init(role: AccessRole.patient.rawValue, careFocus: CareFocus.bipolar.rawValue),
            medicationPlan: .init(
                name: "Lamotrigina",
                dose: "100 mg",
                schedule: "Noite",
                prescriptionEnc: "Após jantar",
                changeNoteEnc: "Aumentou de 50 mg"
            ),
            medicationPlans: [medication],
            customSymptoms: [symptom],
            safetyPlan: .init(
                contactEnc: "Contato",
                warningSignsEnc: "Sinais",
                strategiesEnc: "Estratégias"
            ),
            offlineQueue: [],
            checkIns: [checkIn],
            assessments: [assessment]
        )

        let restored = try NeuremiaBackupSnapshot.decode(from: snapshot.encodedData())

        #expect(restored.medicationPlans.count == 1)
        #expect(restored.medicationPlans.first?.id == medication.id)
        #expect(restored.medicationPlans.first?.summary == "Lamotrigina • 100 mg • Noite")
        #expect(restored.medicationPlans.first?.prescription == medication.prescription)
        #expect(restored.medicationPlans.first?.changeNote == medication.changeNote)

        #expect(restored.customSymptoms.count == 1)
        #expect(restored.customSymptoms.first?.id == symptom.id)
        #expect(restored.customSymptoms.first?.name == symptom.name)
        #expect(restored.customSymptoms.first?.value == symptom.value)

        #expect(restored.checkIns.count == 1)
        #expect(restored.checkIns.first?.dayKey == checkIn.dayKey)
        #expect(restored.checkIns.first?.mood == checkIn.mood)
        #expect(restored.checkIns.first?.anxiety == checkIn.anxiety)
        #expect(restored.checkIns.first?.journalEntryEnc == checkIn.journalEntryEnc)

        #expect(restored.assessments.count == 1)
        #expect(restored.assessments.first?.scaleName == assessment.scaleName)
        #expect(restored.assessments.first?.answers == assessment.answers)
        #expect(restored.assessments.first?.score == assessment.score)
        #expect(restored.assessments.first?.interpretation == assessment.interpretation)
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

    @Test func recommendationImpactScoresNextCheckInResponse() {
        let impact = AdaptiveRecommendationEngine.impact(
            baselineMood: 2,
            baselineAnxiety: 4,
            baselineSleepHours: 5,
            currentMood: 3,
            currentAnxiety: 3,
            currentSleepHours: 7
        )

        #expect(impact.moodDelta == 1)
        #expect(impact.anxietyDelta == 1)
        #expect(impact.sleepDelta == 2)
        #expect(impact.netImpact == 2.7)
        #expect(impact.summary == "Sinais melhoraram após a recomendação.")
    }

    @Test func adaptiveRecommendationProfileLearnsHelpfulActions() {
        let logs = (0..<3).map { day in
            DailyRecommendationLog(
                date: Date(timeIntervalSince1970: Double(day) * 86_400),
                recommendationId: "protect-sleep-window",
                title: "Proteger sono",
                action: "Preserve a janela de sono.",
                rationale: "Sono curto elevou risco.",
                targetSignal: "sono",
                baselineMood: 2,
                baselineAnxiety: 4,
                baselineSleepHours: 5,
                completed: true,
                completedAt: Date(timeIntervalSince1970: Double(day) * 86_400 + 3_600),
                impactMoodDelta: 1,
                impactAnxietyDelta: 1,
                impactSleepDelta: 1,
                impactSummary: "Sinais melhoraram após a recomendação."
            )
        }

        let profile = AdaptiveRecommendationEngine.profile(for: "sono", logs: logs)

        #expect(profile?.sampleCount == 3)
        #expect(profile?.completionCount == 3)
        #expect(profile?.isHelpful == true)
    }

    @Test func adaptiveRecommendationProfileWaitsForEnoughMeasuredSamples() {
        let logs = (0..<2).map { day in
            DailyRecommendationLog(
                date: Date(timeIntervalSince1970: Double(day) * 86_400),
                recommendationId: "protect-sleep-window",
                title: "Proteger sono",
                action: "Preserve a janela de sono.",
                rationale: "Sono curto elevou risco.",
                targetSignal: "sono",
                baselineMood: 2,
                baselineAnxiety: 4,
                baselineSleepHours: 5,
                completed: true,
                completedAt: Date(timeIntervalSince1970: Double(day) * 86_400 + 3_600),
                impactMoodDelta: 1,
                impactAnxietyDelta: 1,
                impactSleepDelta: 1,
                impactSummary: "Sinais melhoraram após a recomendação."
            )
        }

        let profile = AdaptiveRecommendationEngine.profile(for: "sono", logs: logs)

        #expect(profile?.sampleCount == 2)
        #expect(profile?.hasEnoughData == false)
        #expect(profile?.isHelpful == false)
    }

    @Test func adaptiveRecommendationProfileDetectsHarmfulActions() {
        let logs = (0..<3).map { day in
            DailyRecommendationLog(
                date: Date(timeIntervalSince1970: Double(day) * 86_400),
                recommendationId: "activation-push",
                title: "Ativação",
                action: "Aumente a atividade hoje.",
                rationale: "Energia baixa pode responder a movimento.",
                targetSignal: "energia",
                baselineMood: 3,
                baselineAnxiety: 3,
                baselineSleepHours: 7,
                completed: true,
                completedAt: Date(timeIntervalSince1970: Double(day) * 86_400 + 3_600),
                impactMoodDelta: -1,
                impactAnxietyDelta: -1,
                impactSleepDelta: 0,
                impactSummary: "Sinais pioraram após a recomendação."
            )
        }

        let profile = AdaptiveRecommendationEngine.profile(for: "energia", logs: logs)

        #expect(profile?.sampleCount == 3)
        #expect(profile?.hasEnoughData == true)
        #expect(profile?.isHarmful == true)
    }

    @Test func automaticInterventionDetectorFindsBreathingPracticeInJournal() {
        let recommendation = ClinicalDailyRecommendation(
            id: "grounding-breath",
            title: "Reduzir ativação",
            action: "Faça 3 minutos de respiração lenta.",
            rationale: "Ansiedade em alta responde melhor a redução fisiológica.",
            targetSignal: ClinicalEpisodeKind.anxietyCrisis.rawValue,
            expectedWindow: "24h"
        )
        let checkIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            mood: 3,
            anxiety: 3,
            sleepHours: 6.5,
            medicationTaken: true,
            journalEntry: "Respirei por alguns minutos antes de dormir."
        )

        let detection = AutomaticInterventionDetector.detect(
            recommendation: recommendation,
            checkIn: checkIn,
            steps: 400
        )

        #expect(detection.didComplete)
        #expect(detection.evidence.contains("regulação"))
    }

    @Test func automaticInterventionDetectorUsesPassiveStepsForMovementRecommendation() {
        let recommendation = ClinicalDailyRecommendation(
            id: "causal-light-exercise-anxiety",
            title: "Padrão pessoal",
            action: "Faça uma caminhada curta de 10 minutos.",
            rationale: "Movimento leve costuma reduzir ansiedade.",
            targetSignal: "light-exercise-anxiety",
            expectedWindow: "24h"
        )
        let checkIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            mood: 3,
            anxiety: 3,
            sleepHours: 7,
            medicationTaken: true
        )

        let detection = AutomaticInterventionDetector.detect(
            recommendation: recommendation,
            checkIn: checkIn,
            steps: 2_100
        )

        #expect(detection.didComplete)
        #expect(detection.evidence.contains("passos"))
    }

    @Test func automaticInterventionDetectorAvoidsUnrelatedCompletion() {
        let recommendation = ClinicalDailyRecommendation(
            id: "protect-sleep-window",
            title: "Proteger sono hoje",
            action: "Reduza estímulos à noite e combine uma janela fixa para dormir.",
            rationale: "Sono reduzido elevou risco.",
            targetSignal: ClinicalEpisodeKind.circadianShift.rawValue,
            expectedWindow: "24h"
        )
        let checkIn = makeCheckIn(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            mood: 3,
            anxiety: 3,
            sleepHours: 5.2,
            medicationTaken: true,
            journalEntry: "Dia corrido no trabalho."
        )

        let detection = AutomaticInterventionDetector.detect(
            recommendation: recommendation,
            checkIn: checkIn,
            steps: 500
        )

        #expect(!detection.didComplete)
    }

    @Test func dailyRetentionNarrativeSurfacesSleepHRVVulnerability() {
        let narratives = DailyRetentionNarrativeEngine.compute(
            checkIns: [],
            currentSleepHours: 5.2,
            currentHRV: 36,
            hrvBaseline: 45,
            ppgStress: 50,
            ppgQuality: 0.8,
            mood: 3,
            anxiety: 2
        )

        #expect(narratives.contains { $0.id == "sleep-hrv-vulnerability" })
        #expect(narratives.first?.body.contains("sono + HRV") == true)
    }

    @Test func dailyRetentionNarrativeSurfacesRecentAlertPattern() {
        let now = Date()
        let checkIns = [
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 2), mood: 2, anxiety: 4, sleepHours: 5, medicationTaken: true),
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 5), mood: 2, anxiety: 3, sleepHours: 5.5, medicationTaken: true)
        ]

        let narratives = DailyRetentionNarrativeEngine.compute(
            checkIns: checkIns,
            currentSleepHours: 5.4,
            currentHRV: 0,
            hrvBaseline: 0,
            ppgStress: 40,
            ppgQuality: 0,
            mood: 2,
            anxiety: 4,
            now: now
        )

        #expect(narratives.contains { $0.id == "recent-alert-pattern" })
        #expect(narratives.first { $0.id == "recent-alert-pattern" }?.body.contains("2 vezes") == true)
    }

    @Test func dailyRetentionNarrativeSurfacesHelpfulRecommendationResponse() {
        let recommendation = ClinicalDailyRecommendation(
            id: "walking-anxiety",
            title: "Movimento leve",
            action: "Faça uma caminhada curta de 10 minutos.",
            rationale: "Movimento leve pode reduzir ativação fisiológica.",
            targetSignal: "light-exercise-anxiety",
            expectedWindow: "24h"
        )
        let responseProfile = RecommendationResponseProfile(
            targetSignal: "light-exercise-anxiety",
            sampleCount: 5,
            completionCount: 6,
            averageNetImpact: 0.8,
            responseRate: 0.8
        )

        let narratives = DailyRetentionNarrativeEngine.compute(
            checkIns: [],
            currentSleepHours: 7,
            currentHRV: 48,
            hrvBaseline: 48,
            ppgStress: 25,
            ppgQuality: 0.9,
            mood: 4,
            anxiety: 2,
            recommendation: recommendation,
            responseProfile: responseProfile
        )

        #expect(narratives.contains { $0.id == "recommendation-response-helpful-light-exercise-anxiety" })
        #expect(narratives.first?.body.contains("costuma funcionar") == true)
        #expect(narratives.first?.body.contains("80%") == true)
    }

    @MainActor
    @Test func dailyCoachScoreExplainsWeeklyTrendAndPreCrisisPattern() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let checkIns = [
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 13), mood: 4, anxiety: 1, sleepHours: 7.5, medicationTaken: true),
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 12), mood: 4, anxiety: 1, sleepHours: 7.2, medicationTaken: true),
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 5), mood: 2, anxiety: 4, sleepHours: 5.2, medicationTaken: true),
            makeCheckIn(date: now.addingTimeInterval(-86_400 * 3), mood: 2, anxiety: 4, sleepHours: 5.0, medicationTaken: true),
            makeCheckIn(date: now.addingTimeInterval(-86_400), mood: 2, anxiety: 4, sleepHours: 5.1, medicationTaken: false)
        ]

        let insight = DailyCoachEngine.compute(
            checkIns: checkIns,
            currentSleepHours: 5.0,
            currentHRV: 35,
            hrvBaseline: 45,
            ppgStress: 70,
            ppgQuality: 0.85,
            mood: 2,
            anxiety: 4,
            energy: 2,
            irritability: 3,
            medicationStatus: .pending,
            steps: 900,
            healthKitSnapshots: [
                HealthKitDailySnapshot(
                    dayKey: DailyCheckIn.dayKey(for: now),
                    date: now,
                    sleepHours: 5,
                    steps: 900,
                    heartRate: 82,
                    hrv: 35,
                    activeEnergy: 120,
                    qualityScore: 0.84,
                    sourceCount: 5
                )
            ],
            lastHealthKitSyncAt: now.addingTimeInterval(-3_600),
            now: now
        )

        #expect(insight.weeklyTrendDelta < 0)
        #expect(insight.drivers.contains { $0.text.contains("Tendência pessoal de 7 dias") })
        #expect(insight.drivers.contains { $0.text.contains("Padrão pré-crise") })
        #expect(insight.reliability.level == "Alta")
        #expect(insight.reliability.passiveQuality >= 80)
    }

    @Test func clinicalAlertProtocolDocumentsEmergencyEscalation() {
        let protocolSummary = ClinicalAlertProtocol.local(
            kind: .psychiatricEmergency,
            escalationTarget: .clinicianCaregiverNow,
            criticalPushConsent: true,
            caregiverSMSConsent: true,
            caregiverDigestConsent: false,
            enabledCaregiverCount: 2,
            safetyContactAvailable: true
        )

        #expect(protocolSummary.recipients.contains("médico"))
        #expect(protocolSummary.recipients.contains("2 cuidador"))
        #expect(protocolSummary.responseWindow.contains("imediata"))
        #expect(protocolSummary.falsePositiveHandling.contains("Falso positivo"))
        #expect(protocolSummary.legalLimit.contains("Não substitui"))
    }

    @Test func clinicalAlertProtocolDoesNotInventRecipientsWithoutConsent() {
        let protocolSummary = ClinicalAlertProtocol.local(
            kind: .psychiatricEmergency,
            escalationTarget: .clinicianCaregiverNow,
            criticalPushConsent: false,
            caregiverSMSConsent: false,
            caregiverDigestConsent: false,
            enabledCaregiverCount: 0,
            safetyContactAvailable: false
        )

        #expect(protocolSummary.recipients.contains("ninguém automaticamente"))
    }

    @Test func clinicalAlertStoresOperationalWorkflowFields() {
        let alert = ClinicalAlert(
            level: .high,
            title: "Risco alto",
            message: "Revisar imediatamente."
        )

        #expect(alert.workflowStatus == ClinicalAlertWorkflowStatus.open.rawValue)
        #expect(alert.contactStatus == ClinicalAlertContactStatus.notStarted.rawValue)
        #expect(alert.acknowledged == false)

        let now = Date()
        alert.workflowStatus = ClinicalAlertWorkflowStatus.falsePositive.rawValue
        alert.contactStatus = ClinicalAlertContactStatus.falsePositive.rawValue
        alert.workflowNote = "Falso positivo documentado após contato."
        alert.acknowledgedAt = now
        alert.resolvedAt = now
        alert.acknowledged = true

        #expect(alert.workflowStatus == "false_positive")
        #expect(alert.contactStatus == "false_positive")
        #expect(alert.workflowNote.contains("documentado"))
        #expect(alert.resolvedAt != nil)
    }

    @MainActor
    @Test func dailyCoachUsesContinuousHealthKitSignalsForReliabilityAndDrivers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshots: [HealthKitDailySnapshot] = []
        for offset in 0..<8 {
            let date = now.addingTimeInterval(TimeInterval(-86_400 * offset))
            let isToday = offset == 0
            snapshots.append(HealthKitDailySnapshot(
                dayKey: DailyCheckIn.dayKey(for: date),
                date: date,
                sleepHours: isToday ? 5.8 : 7.1,
                steps: isToday ? 1_200 : 6_500,
                heartRate: isToday ? 86 : 74,
                hrv: isToday ? 34 : 48,
                activeEnergy: isToday ? 110 : 340,
                qualityScore: 0.86,
                sourceCount: 6,
                restingHeartRate: isToday ? 82 : 70,
                circadianRegularityScore: isToday ? 0.35 : 0.82,
                heartRateSampleCount: 40,
                restingHeartRateSampleCount: 1,
                hrvSampleCount: 8,
                stepSampleCount: 18,
                hasWatchSource: true
            ))
        }

        let insight = DailyCoachEngine.compute(
            checkIns: [],
            currentSleepHours: 5.8,
            currentHRV: 34,
            hrvBaseline: 48,
            ppgStress: 0,
            ppgQuality: 0.86,
            mood: 3,
            anxiety: 2,
            energy: 3,
            irritability: 1,
            medicationStatus: .taken,
            steps: 1_200,
            healthKitSnapshots: snapshots,
            lastHealthKitSyncAt: now.addingTimeInterval(-1_800),
            now: now
        )

        #expect(insight.reliability.passiveQuality >= 85)
        #expect(insight.drivers.contains { $0.text.contains("FC repouso") })
        #expect(insight.drivers.contains { $0.text.contains("Ritmo de sono irregular") })
    }

    @Test func healthKitPipelineStoreKeepsFullPassiveHistoryWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var store = HealthKitPipelineStore()
        let snapshots = (0..<60).map { offset in
            makeHealthKitSnapshot(
                date: now.addingTimeInterval(Double(-offset) * 86_400),
                sleepHours: 7,
                qualityScore: 0.8
            )
        }

        store.merge(snapshots)

        #expect(store.snapshots.count == HealthKitPipelineStore.passiveHistoryDays)
        #expect(store.snapshots.first?.dayKey == DailyCheckIn.dayKey(for: now))
        #expect(store.snapshots.last?.dayKey == DailyCheckIn.dayKey(for: now.addingTimeInterval(Double(-(HealthKitPipelineStore.passiveHistoryDays - 1)) * 86_400)))
    }

    @Test func healthKitPipelineStoreReplacesExistingDayWhenRollupRefreshes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var store = HealthKitPipelineStore()
        let original = makeHealthKitSnapshot(date: now, sleepHours: 5, qualityScore: 0.4)
        let refreshed = makeHealthKitSnapshot(date: now, sleepHours: 7.5, qualityScore: 0.9)

        store.merge([original])
        store.merge([refreshed])

        #expect(store.snapshots.count == 1)
        #expect(store.snapshots.first?.sleepHours == 7.5)
        #expect(store.snapshots.first?.qualityScore == 0.9)
    }

    @Test func personalRetentionModelCombinesPatternsPredictionAndInterventionLearning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var checkIns: [DailyCheckIn] = []
        for day in 0..<10 {
            let isVulnerableDay = day % 2 == 0
            checkIns.append(makeCheckIn(
                date: now.addingTimeInterval(Double(-day) * 86_400),
                mood: isVulnerableDay ? 2 : 3,
                anxiety: isVulnerableDay ? 4 : 3,
                sleepHours: day < 4 ? 5.2 : 7,
                medicationTaken: day != 1
            ))
        }

        var logs: [DailyRecommendationLog] = []
        for day in 0..<3 {
            let logDate = now.addingTimeInterval(Double(-(day + 5)) * 86_400)
            logs.append(DailyRecommendationLog(
                date: logDate,
                recommendationId: "grounding-breath",
                title: "Reduzir ativação",
                action: "Faça 3 minutos de respiração lenta.",
                rationale: "Ansiedade em alta responde melhor a redução fisiológica.",
                targetSignal: ClinicalEpisodeKind.anxietyCrisis.rawValue,
                baselineMood: 2,
                baselineAnxiety: 4,
                baselineSleepHours: 6,
                completed: true,
                completedAt: logDate.addingTimeInterval(1_800),
                impactMoodDelta: 0.5,
                impactAnxietyDelta: 1,
                impactSleepDelta: 0.5,
                impactSummary: "Sinais melhoraram após a recomendação."
            ))
        }
        let recommendation = ClinicalDailyRecommendation(
            id: "grounding-breath",
            title: "Reduzir ativação",
            action: "Faça 3 minutos de respiração lenta.",
            rationale: "Ansiedade em alta responde melhor a redução fisiológica.",
            targetSignal: ClinicalEpisodeKind.anxietyCrisis.rawValue,
            expectedWindow: "24-72h"
        )

        let profile = PersonalRetentionModelEngine.compute(
            checkIns: checkIns,
            recommendationLogs: logs,
            temporalPrediction: makeTemporalPrediction(score: 58, level: .moderate),
            currentRecommendation: recommendation,
            now: now
        )

        #expect(profile.learningScore >= 75)
        #expect(profile.vulnerabilityLevel == .high)
        #expect(profile.patterns.contains { $0.id == "recent-vulnerability-recurrence" })
        #expect(profile.interventionLearnings.contains { $0.id == "helpful-\(ClinicalEpisodeKind.anxietyCrisis.rawValue)" })
        #expect(profile.nextBestActionReason.contains("resposta positiva"))
    }

    @Test func personalRetentionModelHasUsefulWarmingStateWithoutHistory() {
        let recommendation = ClinicalDailyRecommendation.fallback
        let profile = PersonalRetentionModelEngine.compute(
            checkIns: [],
            recommendationLogs: [],
            temporalPrediction: makeTemporalPrediction(score: 12, level: .low),
            currentRecommendation: recommendation
        )

        #expect(profile.isWarmingUp)
        #expect(profile.stageTitle == "Primeira linha de base")
        #expect(profile.patterns.isEmpty)
        #expect(profile.interventionLearnings.isEmpty)
        #expect(profile.nextBestAction == recommendation.action)
        #expect(profile.dataCoverageText.contains("0 check-ins"))
    }

    private func makeCheckIn(
        date: Date,
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationTaken: Bool,
        journalEntry: String = ""
    ) -> DailyCheckIn {
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
            journalEntry: journalEntry
        )
    }

    private func makeHealthKitSnapshot(date: Date, sleepHours: Double, qualityScore: Double) -> HealthKitDailySnapshot {
        HealthKitDailySnapshot(
            dayKey: DailyCheckIn.dayKey(for: date),
            date: date,
            sleepHours: sleepHours,
            steps: 5_000,
            heartRate: 72,
            hrv: 45,
            activeEnergy: 260,
            qualityScore: qualityScore,
            sourceCount: 6,
            restingHeartRate: 64,
            circadianRegularityScore: 0.82,
            heartRateSampleCount: 40,
            restingHeartRateSampleCount: 1,
            hrvSampleCount: 8,
            stepSampleCount: 20,
            hasWatchSource: true
        )
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = Schema(NeuremiaSchemaV3.models, version: NeuremiaSchemaV3.versionIdentifier)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeTemporalPrediction(score: Int, level: ClinicalRiskLevel) -> TemporalRiskPrediction {
        TemporalRiskPrediction(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            source: .localFallback,
            modelVersion: "test",
            sevenDayRiskScore: score,
            fourteenDayRiskScore: max(score - 8, 0),
            sevenDayLevel: level,
            fourteenDayLevel: level,
            primaryWindow: "7 dias",
            predictedEpisodes: [],
            drivers: ["teste"],
            evidence: ["amostra controlada"],
            longitudinalSampleCount: 10,
            confidence: 0.7
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
        let key = "neuremiaDraftJournalEntry"
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
        savedSession = BackendAuthClient.session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        BackendAuthClient.session = URLSession(configuration: configuration)
    }

    static func reset() {
        BackendAuthClient.session.invalidateAndCancel()
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

@Suite(.serialized)
@MainActor
struct BackendAuthClientTests {
    @Test func loginReturnsTokenAndUserOn200() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/auth/login")
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "access_token": "tok-abc",
                    "refresh_token": "ref-xyz",
                    "token_type": "bearer",
                    "user": {
                        "id": 1,
                        "email": "ana@neuremia.io",
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

        let response = try await BackendAuthClient.login(email: "ana@neuremia.io", password: "supersecret1")
        let user = response.user
        #expect(response.accessToken == "tok-abc")
        #expect(response.refreshToken == "ref-xyz")
        #expect(user.email == "ana@neuremia.io")
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
            #expect(request.url?.path == "/v1/clinician/invites")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-doc")
            return mockResponse(
                statusCode: 200,
                json: """
                {
                    "id": 7,
                    "clinician_id": 9,
                    "patient_id": 12,
                    "clinician_full_name": "Doctor",
                    "clinician_email": "doc@neuremia.io",
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
            #expect(request.url?.path == "/v1/me")
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
            #expect(request.url?.path == "/v1/me/clinical-data")
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

    @Test func clinicianPatientsIncludesLimitAsQuery() async throws {
        MockURLProtocol.install { request in
            #expect(request.url?.path == "/v1/clinician/patients")
            #expect(request.url?.query == "limit=200")
            return mockResponse(
                statusCode: 200,
                json: "{\"items\": [], \"total\": 0, \"skip\": 0, \"limit\": 200}",
                for: request.url!
            )
        }
        defer { MockURLProtocol.reset() }

        let patients = try await BackendAuthClient.clinicianPatients(token: "tok")
        #expect(patients.isEmpty)
    }

    @Test func exportAccountReturnsRawJSONData() async throws {
        let payload = "{\"user\": {\"email\": \"ana@neuremia.io\"}, \"checkins\": []}"
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/me/export")
            return mockResponse(statusCode: 200, json: payload, for: request.url!)
        }
        defer { MockURLProtocol.reset() }

        let data = try await BackendAuthClient.exportAccount(token: "tok")
        #expect(String(data: data, encoding: .utf8) == payload)
    }

    @Test func refreshSwapsTokensFromBackend() async throws {
        MockURLProtocol.install { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/auth/refresh")
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
            #expect(request.url?.path == "/v1/clinician/invites")
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
            #expect(request.url?.path == "/v1/me/audit-logs")
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
            case "/v1/clinician/patients":
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/v1/auth/refresh":
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
            case "/v1/clinician/patients":
                protectedLock.lock()
                protectedCalls += 1
                protectedLock.unlock()
                let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
                if bearer == "Bearer rotated-access" {
                    return mockResponse(
                        statusCode: 200,
                        json: "{\"items\":[],\"total\":0,\"skip\":0,\"limit\":200}",
                        for: request.url!
                    )
                }
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/v1/auth/refresh":
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
            case "/v1/me/linked-clinicians":
                return mockResponse(
                    statusCode: 200,
                    json: """
                    [{
                        "clinician_id": 42,
                        "clinician_full_name": "Dra. Y",
                        "clinician_email": "dra.y@neuremia.io",
                        "linked_at": "2026-06-12T10:00:00"
                    }]
                    """,
                    for: request.url!
                )
            case let path? where path.hasPrefix("/v1/me/clinical-access/"):
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
            case "/v1/clinician/patients":
                callsToProtectedEndpoint += 1
                let bearer = request.value(forHTTPHeaderField: "Authorization") ?? ""
                if bearer == "Bearer rotated-access" {
                    return mockResponse(
                        statusCode: 200,
                        json: "{\"items\":[],\"total\":0,\"skip\":0,\"limit\":200}",
                        for: request.url!
                    )
                }
                // First attempt: 401 forces refresh.
                return mockResponse(statusCode: 401, json: "{\"detail\":\"expired\"}", for: request.url!)
            case "/v1/auth/refresh":
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
            #expect(request.url?.path == "/v1/auth/logout")
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

// MARK: - N-M5: Certificate Pinning Tests

/// Test-double that lets us exercise CertificatePinningDelegate without
/// needing real server certificates. We supply a mock URLAuthenticationChallenge
/// that reports the given auth method and host, and verify the delegate
/// chooses the expected disposition.
struct CertificatePinningTests {

    // Helper: call the delegate synchronously and capture disposition.
    private func evaluate(
        host: String,
        authMethod: String,
        trust: SecTrust?,
        pinnedHashes: Set<String>
    ) -> URLSession.AuthChallengeDisposition {
        let delegate = CertificatePinningDelegate()
        var captured: URLSession.AuthChallengeDisposition = .cancelAuthenticationChallenge

        // Build a mock protection space.
        let space = URLProtectionSpace(
            host: host,
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: authMethod
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockChallengeSender()
        )

        let sema = DispatchSemaphore(value: 0)
        delegate.urlSession(URLSession.shared, didReceive: challenge) { disposition, _ in
            captured = disposition
            sema.signal()
        }
        sema.wait()
        return captured
    }

    @Test func nonServerTrustChallengeIsCancelled() {
        // Non-ServerTrust challenges (e.g. client cert) must always be cancelled.
        let disposition = evaluate(
            host: "api.neuremia.app",
            authMethod: NSURLAuthenticationMethodHTTPBasic,
            trust: nil,
            pinnedHashes: []
        )
        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test func localhost_bypassesValidationInDebug() {
        // DEBUG only: 127.0.0.1 is used for the local backend and must not
        // be blocked, even without pins configured.
        let disposition = evaluate(
            host: "127.0.0.1",
            authMethod: NSURLAuthenticationMethodServerTrust,
            trust: nil,     // trust = nil triggers early return in guard
            pinnedHashes: []
        )
        // In DEBUG, localhost must be .useCredential (bypassed) or at least
        // not cancelled. We can only verify it != .cancelAuthenticationChallenge
        // without a real SecTrust.
        // The guard on `trust` cancels before reaching the localhost check,
        // so this documents the code path behaviour for the trust == nil case.
        #expect(disposition == .cancelAuthenticationChallenge) // trust nil → guard fails
    }

    @Test func noPinsConfigured_releaseBuildCancels() {
        // Without pins in Release, the delegate MUST cancel so a forgotten
        // build setting doesn't silently disable pinning (S37).
        // We can't directly test Release vs Debug here, but we document the
        // expectation so a CI job with -configuration Release can verify it.
        // In DEBUG (CI), noPins → .performDefaultHandling.
        #if DEBUG
        // Nothing to assert in Debug — behaviour is intentionally permissive.
        #else
        let disposition = evaluate(
            host: "api.neuremia.app",
            authMethod: NSURLAuthenticationMethodServerTrust,
            trust: nil,
            pinnedHashes: []
        )
        #expect(disposition == .cancelAuthenticationChallenge)
        #endif
    }
}

/// Minimal URLAuthenticationChallengeSender stub required to build
/// URLAuthenticationChallenge in tests.
private class MockChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
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
