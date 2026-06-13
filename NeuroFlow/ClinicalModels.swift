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

 : explicit relationships with cascade-delete so that removing a
    // PatientProfile also removes all associated clinical records and queries
    // scoped to a profile never bleed into records belonging to another user.
    @Relationship(deleteRule: .cascade) var checkIns: [DailyCheckIn] = []
    @Relationship(deleteRule: .cascade) var assessments: [ScaleAssessment] = []
    @Relationship(deleteRule: .cascade) var alerts: [ClinicalAlert] = []
    @Relationship(deleteRule: .cascade) var reports: [ClinicalReport] = []

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
    /// Calendar-day key ("YYYY-MM-DD" in the device's current calendar).
    /// Declared unique so SwiftData enforces one check-in per day at the
    /// store level, mirroring the one-per-day business rule enforced in code.
    @Attribute(.unique) var dayKey: String
    var date: Date
    var patient: PatientProfile?
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
        self.dayKey = DailyCheckIn.dayKey(for: date)
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

    // N-C4: always derive dayKey in UTC so that timezone changes (DST,
    // international travel) never produce two different keys for what the
    // clinical record considers the same calendar day.
    static func dayKey(for date: Date) -> String {
        var utcCalendar = Calendar(identifier: .iso8601)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)
        let c = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

@Model
final class ScaleAssessment {
    var scaleName: String
    var date: Date
    var patient: PatientProfile?
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
    var patient: PatientProfile?
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
    var patient: PatientProfile?
    // N-M4: fields required for medical-legal validity
    var clinicianName: String
    var periodStart: Date
    var periodEnd: Date
    var scalesIncluded: [String]
    var algorithmVersion: String

    init(
        date: Date = Date(),
        summary: String,
        riskLevel: ClinicalRiskLevel,
        clinicianName: String = "",
        periodStart: Date = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(),
        periodEnd: Date = Date(),
        scalesIncluded: [String] = [],
        algorithmVersion: String = "2.0"
    ) {
        self.date = date
        self.summary = summary
        self.riskLevel = riskLevel.rawValue
        self.clinicianName = clinicianName
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.scalesIncluded = scalesIncluded
        self.algorithmVersion = algorithmVersion
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

// Unified backup envelope — single source of truth for export/import.
// PHI text fields (journalEntry, automaticThoughts, sideEffects, prescription,
// changeNote, safetyPlan fields) are stored as AES-GCM base-64 ciphertext
// produced by DraftStore.encryptString(_:). Legacy plaintext imports are
// handled transparently by decryptField(_:) in ContentView.
struct NeuroFlowBackupSnapshot: Codable {
    struct Profile: Codable {
        let role: String
        let careFocus: String
    }
    struct MedicationPlanCurrent: Codable {
        let name: String
        let dose: String
        let schedule: String
        let prescriptionEnc: String   // encrypted
        let changeNoteEnc: String     // encrypted
    }
    struct SafetyPlan: Codable {
        let contactEnc: String        // encrypted
        let warningSignsEnc: String   // encrypted
        let strategiesEnc: String     // encrypted
    }

    let exportedAt: Date
    /// Increment whenever the snapshot schema changes so importers can
    /// gracefully handle older files.
    let schemaVersion: Int
    let profile: Profile
    let medicationPlan: MedicationPlanCurrent
    let medicationPlans: [MedicationPlanEntry]
    let customSymptoms: [CustomSymptomEntry]
    let safetyPlan: SafetyPlan
    let offlineQueue: [OfflineSyncItem]
    let checkIns: [DailyCheckInSnapshot]
    let assessments: [ScaleAssessmentSnapshot]

    init(
        exportedAt: Date = Date(),
        schemaVersion: Int = 2,
        profile: Profile,
        medicationPlan: MedicationPlanCurrent,
        medicationPlans: [MedicationPlanEntry],
        customSymptoms: [CustomSymptomEntry],
        safetyPlan: SafetyPlan,
        offlineQueue: [OfflineSyncItem],
        checkIns: [DailyCheckInSnapshot],
        assessments: [ScaleAssessmentSnapshot]
    ) {
        self.exportedAt = exportedAt
        self.schemaVersion = schemaVersion
        self.profile = profile
        self.medicationPlan = medicationPlan
        self.medicationPlans = medicationPlans
        self.customSymptoms = customSymptoms
        self.safetyPlan = safetyPlan
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
    let dayKey: String
    let mood: Double
    let anxiety: Double
    let energy: Double
    let irritability: Double
    let sleepHours: Double
    let appetite: Double
    let libido: Double
    let medicationTaken: Bool
    let suicidalIdeation: Bool
    // PHI free-text fields stored as AES-GCM base-64 ciphertext.
    let sideEffectsEnc: String
    let automaticThoughtsEnc: String
    let journalEntryEnc: String
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


enum NeuroFlowSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        PatientProfile.self,
        DailyCheckIn.self,
        ScaleAssessment.self,
        ClinicalAlert.self,
        ClinicalReport.self,
    ]
}

enum NeuroFlowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [NeuroFlowSchemaV1.self]
    static var stages: [MigrationStage] = []
}
