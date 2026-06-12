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

    @Test func ymrsProbableManiaInterpretation() {
        let score = ClinicalAnalysis.score(for: .ymrs, answers: [2, 2, 2, 2, 2, 2, 1, 1, 0, 0])

        #expect(score == 14)
        #expect(ClinicalAnalysis.interpretation(for: .ymrs, score: score) == "Mania provável")
    }

    @Test func textAssessmentDetectsHighRiskTerms() {
        let assessment = ClinicalAnalysis.textAssessment(for: "Estou sem saída e penso em morrer")

        #expect(assessment.level == .high)
        #expect(assessment.detectedTerms.contains("morrer"))
        #expect(!assessment.recommendation.isEmpty)
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
