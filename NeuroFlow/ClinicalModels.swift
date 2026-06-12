//
//  ClinicalModels.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation
import SwiftData

@Model
final class PatientProfile {
    var name: String
    var clinicianName: String
    var consentAccepted: Bool
    var shareWithClinician: Bool
    var activeRole: String
    var createdAt: Date

    init(name: String = "Paciente", clinicianName: String = "Médico assistente", consentAccepted: Bool = false, shareWithClinician: Bool = false, activeRole: String = AccessRole.patient.rawValue, createdAt: Date = Date()) {
        self.name = name
        self.clinicianName = clinicianName
        self.consentAccepted = consentAccepted
        self.shareWithClinician = shareWithClinician
        self.activeRole = activeRole
        self.createdAt = createdAt
    }
}

@Model
final class DailyCheckIn {
    var date: Date
    var mood: Double
    var anxiety: Double
    var energy: Double
    var irritability: Double
    var sleepHours: Double
    var appetite: Double
    var libido: Double
    var medicationTaken: Bool
    var sideEffects: String
    var automaticThoughts: String
    var suicidalIdeation: Bool
    var journalEntry: String

    init(date: Date = Date(), mood: Double, anxiety: Double, energy: Double, irritability: Double, sleepHours: Double, appetite: Double, libido: Double, medicationTaken: Bool, sideEffects: String, automaticThoughts: String, suicidalIdeation: Bool, journalEntry: String) {
        self.date = date
        self.mood = mood
        self.anxiety = anxiety
        self.energy = energy
        self.irritability = irritability
        self.sleepHours = sleepHours
        self.appetite = appetite
        self.libido = libido
        self.medicationTaken = medicationTaken
        self.sideEffects = sideEffects
        self.automaticThoughts = automaticThoughts
        self.suicidalIdeation = suicidalIdeation
        self.journalEntry = journalEntry
    }
}

@Model
final class ScaleAssessment {
    var scaleName: String
    var date: Date
    var answers: [Int]
    var score: Int
    var interpretation: String

    init(scaleName: String, date: Date = Date(), answers: [Int], score: Int, interpretation: String) {
        self.scaleName = scaleName
        self.date = date
        self.answers = answers
        self.score = score
        self.interpretation = interpretation
    }
}

@Model
final class ClinicalAlert {
    var date: Date
    var level: String
    var title: String
    var message: String
    var acknowledged: Bool

    init(date: Date = Date(), level: ClinicalRiskLevel, title: String, message: String, acknowledged: Bool = false) {
        self.date = date
        self.level = level.rawValue
        self.title = title
        self.message = message
        self.acknowledged = acknowledged
    }
}

@Model
final class ClinicalReport {
    var date: Date
    var summary: String
    var riskLevel: String

    init(date: Date = Date(), summary: String, riskLevel: ClinicalRiskLevel) {
        self.date = date
        self.summary = summary
        self.riskLevel = riskLevel.rawValue
    }
}

enum ClinicalRiskLevel: String, CaseIterable {
    case low = "Leve"
    case moderate = "Moderado"
    case high = "Alto"

    var sortOrder: Int {
        switch self {
        case .low:
            0
        case .moderate:
            1
        case .high:
            2
        }
    }

    var alertTitle: String {
        switch self {
        case .low:
            "Monitoramento estável"
        case .moderate:
            "Piora clínica possível"
        case .high:
            "Risco clínico alto"
        }
    }
}

enum AccessRole: String, CaseIterable, Identifiable {
    case patient = "Paciente"
    case clinician = "Médico"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .patient:
            "person"
        case .clinician:
            "stethoscope"
        }
    }
}

enum ScaleKind: String, CaseIterable, Identifiable {
    case phq9 = "PHQ-9"
    case gad7 = "GAD-7"
    case ymrs = "YMRS"

    var id: String { rawValue }

    var focus: String {
        switch self {
        case .phq9:
            "Sintomas depressivos"
        case .gad7:
            "Ansiedade generalizada"
        case .ymrs:
            "Sintomas maníacos"
        }
    }

    var administrationNote: String {
        switch self {
        case .phq9, .gad7:
            "Responder considerando as últimas duas semanas. Cada item vai de 0 a 3."
        case .ymrs:
            "Escala originalmente administrada por clínico, baseada em entrevista/observação recente. Total real: 11 itens, 0 a 60 pontos."
        }
    }

    var questions: [String] {
        switch self {
        case .phq9:
            [
                "Pouco interesse ou prazer em fazer as coisas",
                "Sentir-se para baixo, deprimido ou sem esperança",
                "Problemas para dormir ou dormir demais",
                "Cansaço ou pouca energia",
                "Falta de apetite ou comer demais",
                "Sentir-se mal consigo mesmo",
                "Dificuldade de concentração",
                "Lentidão ou agitação percebida por outras pessoas",
                "Pensamentos de morte ou autolesão"
            ]
        case .gad7:
            [
                "Sentir-se nervoso, ansioso ou no limite",
                "Não conseguir controlar as preocupações",
                "Preocupar-se demais com diferentes coisas",
                "Dificuldade para relaxar",
                "Inquietação",
                "Irritar-se facilmente",
                "Medo de que algo terrível aconteça"
            ]
        case .ymrs:
            [
                "Humor elevado",
                "Aumento de energia ou atividade motora",
                "Interesse sexual aumentado",
                "Sono reduzido",
                "Irritabilidade",
                "Fala: velocidade e quantidade",
                "Linguagem ou alteração do pensamento",
                "Conteúdo do pensamento",
                "Comportamento disruptivo ou agressivo",
                "Aparência",
                "Insight"
            ]
        }
    }

    func answerRange(for questionIndex: Int) -> ClosedRange<Int> {
        switch self {
        case .phq9, .gad7:
            0...3
        case .ymrs:
            [4, 5, 7, 8].contains(questionIndex) ? 0...8 : 0...4
        }
    }
}

struct LongitudinalSummary {
    let riskLevel: ClinicalRiskLevel
    let moodTrend: Double
    let anxietyTrend: Double
    let sleepTrend: Double
    let averageSleep: Double
    let medicationAdherence: Double
    let textRisk: ClinicalRiskLevel
    let textAssessment: TextRiskAssessment
    let analyzedCheckInCount: Int
    let firstMood: Double?
    let latestMood: Double?
    let firstAnxiety: Double?
    let latestAnxiety: Double?
    let firstSleep: Double?
    let latestSleep: Double?
    let signals: [String]

    var cadence: String {
        switch riskLevel {
        case .low:
            "Quinzenal"
        case .moderate, .high:
            "Semanal"
        }
    }
}

struct TextRiskAssessment {
    let level: ClinicalRiskLevel
    let detectedTerms: [String]
    let explanation: String

    var recommendation: String {
        switch level {
        case .low:
            "Manter monitoramento longitudinal e revisar contexto clínico em consulta."
        case .moderate:
            "Revisar sofrimento atual, fatores de proteção, sono, impulsividade e adesão ao tratamento."
        case .high:
            "Acionar revisão clínica prioritária, avaliar risco suicida e considerar plano de segurança."
        }
    }
}

struct NeuroFlowBackupSnapshot: Codable {
    let exportedAt: Date
    let medicationPlans: [MedicationPlanEntry]
    let customSymptoms: [CustomSymptomEntry]
    let offlineQueue: [OfflineSyncItem]
    let checkIns: [DailyCheckInSnapshot]
    let assessments: [ScaleAssessmentSnapshot]

    init(
        exportedAt: Date = Date(),
        medicationPlans: [MedicationPlanEntry],
        customSymptoms: [CustomSymptomEntry],
        offlineQueue: [OfflineSyncItem],
        checkIns: [DailyCheckInSnapshot],
        assessments: [ScaleAssessmentSnapshot]
    ) {
        self.exportedAt = exportedAt
        self.medicationPlans = medicationPlans
        self.customSymptoms = customSymptoms
        self.offlineQueue = offlineQueue
        self.checkIns = checkIns
        self.assessments = assessments
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> NeuroFlowBackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NeuroFlowBackupSnapshot.self, from: data)
    }
}

struct DailyCheckInSnapshot: Codable, Equatable {
    let date: Date
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
}

struct ScaleAssessmentSnapshot: Codable, Equatable {
    let date: Date
    let scaleName: String
    let answers: [Int]
    let score: Int
    let interpretation: String
}

enum MonthlyReportSummary {
    static func lines(for checkIns: [DailyCheckIn], now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let monthEntries = checkIns.filter {
            calendar.isDate($0.date, equalTo: now, toGranularity: .month)
        }
        guard !monthEntries.isEmpty else {
            return ["Sem registros no mês atual."]
        }

        let moodAverage = monthEntries.map(\.mood).reduce(0, +) / Double(monthEntries.count)
        let anxietyAverage = monthEntries.map(\.anxiety).reduce(0, +) / Double(monthEntries.count)
        let sleepAverage = monthEntries.map(\.sleepHours).reduce(0, +) / Double(monthEntries.count)
        let adherence = Double(monthEntries.filter(\.medicationTaken).count) / Double(monthEntries.count) * 100

        return [
            "Registros no mês: \(monthEntries.count)",
            "Humor médio: \(String(format: "%.1f", moodAverage))/5",
            "Ansiedade média: \(String(format: "%.1f", anxietyAverage))/5",
            "Sono médio: \(String(format: "%.1f", sleepAverage))h",
            "Adesão medicamentosa: \(String(format: "%.0f", adherence))%"
        ]
    }
}
