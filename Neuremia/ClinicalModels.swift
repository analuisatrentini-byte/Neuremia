//
//  ClinicalModels.swift
//  Neuremia
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

    // Uses explicit relationships with cascade-delete so that removing a
    // PatientProfile also removes all associated clinical records and queries
    // scoped to a profile never bleed into records belonging to another user.
    @Relationship(deleteRule: .cascade) var checkIns: [DailyCheckIn] = []
    @Relationship(deleteRule: .cascade) var assessments: [ScaleAssessment] = []
    @Relationship(deleteRule: .cascade) var alerts: [ClinicalAlert] = []
    @Relationship(deleteRule: .cascade) var reports: [ClinicalReport] = []
    @Relationship(deleteRule: .cascade) var gamificationProfile: GamificationProfile?
    @Relationship(deleteRule: .cascade) var missionLogs: [DailyMissionLog] = []
    @Relationship(deleteRule: .cascade) var recommendationLogs: [DailyRecommendationLog] = []

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
        if let utcTimeZone = TimeZone(secondsFromGMT: 0) {
            utcCalendar.timeZone = utcTimeZone
        }
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
    var kind: String
    var escalationTarget: String
    var patient: PatientProfile?
    var title: String
    var message: String
    var acknowledged: Bool
    var workflowStatus: String = ClinicalAlertWorkflowStatus.open.rawValue
    var contactStatus: String = ClinicalAlertContactStatus.notStarted.rawValue
    var workflowNote: String = ""
    var acknowledgedAt: Date?
    var escalatedAt: Date?
    var resolvedAt: Date?

    init(
        date: Date = Date(),
        level: ClinicalRiskLevel,
        kind: ClinicalAlertKind = .psychiatricEmergency,
        escalationTarget: ClinicalEscalationTarget = .clinicianCaregiverNow,
        title: String,
        message: String,
        acknowledged: Bool = false,
        workflowStatus: ClinicalAlertWorkflowStatus = .open,
        contactStatus: ClinicalAlertContactStatus = .notStarted,
        workflowNote: String = "",
        acknowledgedAt: Date? = nil,
        escalatedAt: Date? = nil,
        resolvedAt: Date? = nil
    ) {
        self.date = date
        self.level = level.rawValue
        self.kind = kind.rawValue
        self.escalationTarget = escalationTarget.rawValue
        self.title = title
        self.message = message
        self.acknowledged = acknowledged
        self.workflowStatus = workflowStatus.rawValue
        self.contactStatus = contactStatus.rawValue
        self.workflowNote = workflowNote
        self.acknowledgedAt = acknowledgedAt
        self.escalatedAt = escalatedAt
        self.resolvedAt = resolvedAt
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

enum ClinicalAlertKind: String, CaseIterable {
    case psychiatricEmergency = "psychiatric_emergency"
    case clinicalWatch = "clinical_watch"
    case selfSignal = "self_signal"

    var label: String {
        switch self {
        case .psychiatricEmergency:
            "Ação imediata"
        case .clinicalWatch:
            "Acompanhar"
        case .selfSignal:
            "Sinal pessoal"
        }
    }
}

enum ClinicalEscalationTarget: String, CaseIterable {
    case clinicianCaregiverNow = "clinician_caregiver_now"
    case clinicianDigest = "clinician_digest"
    case patientOnly = "patient_only"
}

enum ClinicalAlertWorkflowStatus: String, CaseIterable {
    case open
    case contacted
    case escalated
    case falsePositive = "false_positive"
    case resolved

    var label: String {
        switch self {
        case .open:
            "Aberto"
        case .contacted:
            "Contato feito"
        case .escalated:
            "Escalado"
        case .falsePositive:
            "Falso positivo"
        case .resolved:
            "Resolvido"
        }
    }
}

enum ClinicalAlertContactStatus: String, CaseIterable {
    case notStarted = "not_started"
    case pending
    case completed
    case falsePositive = "false_positive"

    var label: String {
        switch self {
        case .notStarted:
            "Contato não iniciado"
        case .pending:
            "Contato pendente"
        case .completed:
            "Contato confirmado"
        case .falsePositive:
            "Falso positivo documentado"
        }
    }
}

struct ClinicalAlertProtocol: Hashable {
    let recipients: String
    let responseWindow: String
    let acknowledgement: String
    let escalation: String
    let falsePositiveHandling: String
    let legalLimit: String

    static func local(
        kind: ClinicalAlertKind,
        escalationTarget: ClinicalEscalationTarget,
        criticalPushConsent: Bool,
        caregiverSMSConsent: Bool,
        caregiverDigestConsent: Bool,
        enabledCaregiverCount: Int,
        safetyContactAvailable: Bool
    ) -> ClinicalAlertProtocol {
        let recipients = recipientSummary(
            escalationTarget: escalationTarget,
            criticalPushConsent: criticalPushConsent,
            caregiverSMSConsent: caregiverSMSConsent,
            caregiverDigestConsent: caregiverDigestConsent,
            enabledCaregiverCount: enabledCaregiverCount,
            safetyContactAvailable: safetyContactAvailable
        )

        switch kind {
        case .psychiatricEmergency:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: imediata. Se houver risco atual, usar emergência local agora.",
                acknowledgement: "Confirmação necessária: paciente aciona apoio; clínico/cuidador registra contato quando disponível.",
                escalation: "Escalonamento: contato de segurança + cuidador autorizado + médico; sem confirmação, orientar serviço de urgência.",
                falsePositiveHandling: "Falso positivo: registrar somente após contato/revisão; manter plano de segurança visível por hoje.",
                legalLimit: "Limite: o app apoia triagem e comunicação. Não substitui emergência, avaliação clínica ou responsabilidade profissional."
            )
        case .clinicalWatch:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: revisar em até 24-48h ou antes se houver piora.",
                acknowledgement: "Confirmação necessária: marcar como revisado após leitura e plano de acompanhamento.",
                escalation: "Escalonamento: virar ação imediata se houver ideação suicida, queda intensa de humor ou perda de controle.",
                falsePositiveHandling: "Falso positivo: registrar contexto que explicou o alerta para ajustar regras e reduzir ruído.",
                legalLimit: "Limite: alerta de acompanhamento não é diagnóstico; decisão clínica exige avaliação profissional."
            )
        case .selfSignal:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: auto-observação no mesmo dia.",
                acknowledgement: "Confirmação necessária: paciente revisa e decide se compartilha com a equipe.",
                escalation: "Escalonamento: procurar apoio se o sinal persistir ou vier com risco de autolesão.",
                falsePositiveHandling: "Falso positivo: marcar como revisado se não representar risco atual.",
                legalLimit: "Limite: sinal pessoal é apoio de autocuidado, não triagem clínica definitiva."
            )
        }
    }

    static func from(alert: ClinicalAlert) -> ClinicalAlertProtocol {
        local(
            kind: ClinicalAlertKind(rawValue: alert.kind) ?? .psychiatricEmergency,
            escalationTarget: ClinicalEscalationTarget(rawValue: alert.escalationTarget) ?? .clinicianCaregiverNow,
            criticalPushConsent: false,
            caregiverSMSConsent: false,
            caregiverDigestConsent: false,
            enabledCaregiverCount: 0,
            safetyContactAvailable: false
        )
    }

    static func remote(kind: ClinicalAlertKind, escalationTarget: ClinicalEscalationTarget) -> ClinicalAlertProtocol {
        let recipients: String
        switch escalationTarget {
        case .clinicianCaregiverNow:
            recipients = "Quem recebe: canais configurados no backend para médico e cuidadores autorizados."
        case .clinicianDigest:
            recipients = "Quem recebe: médico no digest clínico configurado no backend."
        case .patientOnly:
            recipients = "Quem recebe: somente paciente."
        }

        switch kind {
        case .psychiatricEmergency:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: imediata. Se houver risco atual, orientar emergência local.",
                acknowledgement: "Confirmação necessária: registrar contato, tentativa de contato ou motivo documentado.",
                escalation: "Escalonamento: se contato falhar, acionar próximo canal autorizado e registrar no workflow.",
                falsePositiveHandling: "Falso positivo: resolver como false_positive apenas após revisão clínica documentada.",
                legalLimit: "Limite: alerta operacional não substitui avaliação clínica, emergência ou dever profissional."
            )
        case .clinicalWatch:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: revisar em até 24-48h.",
                acknowledgement: "Confirmação necessária: registrar revisão ou snooze com prazo.",
                escalation: "Escalonamento: promover para ação imediata se surgir risco de autolesão ou piora rápida.",
                falsePositiveHandling: "Falso positivo: registrar contexto para calibrar ruído do modelo.",
                legalLimit: "Limite: alerta de acompanhamento não é diagnóstico."
            )
        case .selfSignal:
            return ClinicalAlertProtocol(
                recipients: recipients,
                responseWindow: "Resposta esperada: auto-observação no mesmo dia.",
                acknowledgement: "Confirmação necessária: paciente revisa ou compartilha.",
                escalation: "Escalonamento: procurar apoio se persistir ou vier com risco.",
                falsePositiveHandling: "Falso positivo: marcar como revisado se não representar risco atual.",
                legalLimit: "Limite: sinal pessoal é apoio de autocuidado."
            )
        }
    }

    private static func recipientSummary(
        escalationTarget: ClinicalEscalationTarget,
        criticalPushConsent: Bool,
        caregiverSMSConsent: Bool,
        caregiverDigestConsent: Bool,
        enabledCaregiverCount: Int,
        safetyContactAvailable: Bool
    ) -> String {
        var recipients: [String] = []
        switch escalationTarget {
        case .clinicianCaregiverNow:
            if criticalPushConsent { recipients.append("médico por alerta crítico") }
            if caregiverSMSConsent && enabledCaregiverCount > 0 {
                recipients.append("\(enabledCaregiverCount) cuidador(es) autorizado(s)")
            }
            if safetyContactAvailable { recipients.append("contato de segurança do paciente") }
        case .clinicianDigest:
            if caregiverDigestConsent || criticalPushConsent {
                recipients.append("médico no digest clínico")
            }
        case .patientOnly:
            recipients.append("somente paciente")
        }
        if recipients.isEmpty {
            recipients.append("ninguém automaticamente; consentimento crítico não configurado")
        }
        return "Quem recebe: \(recipients.joined(separator: ", "))."
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
    let episodeForecasts: [ClinicalEpisodeForecast]
    let temporalPrediction: TemporalRiskPrediction
    let clinicalDigest: ClinicalDailyDigest
    let dailyRecommendation: ClinicalDailyRecommendation

    var cadence: String {
        switch riskLevel {
        case .low:
            "Quinzenal"
        case .moderate, .high:
            "Semanal"
        }
    }
}

enum ClinicalEpisodeKind: String, CaseIterable {
    case maniaProdrome = "Pródromo de mania"
    case depressiveRelapse = "Recaída depressiva"
    case anxietyCrisis = "Crise de ansiedade"
    case suicideRisk = "Risco suicida"
    case lowAdherence = "Baixa adesão"
    case circadianShift = "Alteração circadiana"
}

struct ClinicalEpisodeForecast: Identifiable, Hashable {
    let kind: ClinicalEpisodeKind
    let level: ClinicalRiskLevel
    let confidence: Double
    let window: String
    let drivers: [String]
    let comparison: String?

    var id: String { kind.rawValue }
}

enum TemporalPredictionSource: String, Hashable {
    case trainedBackend = "Backend treinado"
    case localFallback = "Modelo temporal local"
}

struct TemporalRiskPrediction: Identifiable, Hashable {
    let id = UUID()
    let generatedAt: Date
    let source: TemporalPredictionSource
    let modelVersion: String
    let sevenDayRiskScore: Int
    let fourteenDayRiskScore: Int
    let sevenDayLevel: ClinicalRiskLevel
    let fourteenDayLevel: ClinicalRiskLevel
    let primaryWindow: String
    let predictedEpisodes: [ClinicalEpisodeForecast]
    let drivers: [String]
    let evidence: [String]
    let longitudinalSampleCount: Int
    let confidence: Double

    var primaryScore: Int { max(sevenDayRiskScore, fourteenDayRiskScore) }
    var primaryLevel: ClinicalRiskLevel {
        sevenDayLevel.sortOrder >= fourteenDayLevel.sortOrder ? sevenDayLevel : fourteenDayLevel
    }
}

struct ClinicalDailyDigest: Identifiable, Hashable {
    let id = UUID()
    let generatedAt: Date
    let priorityScore: Int
    let priorityLevel: ClinicalRiskLevel
    let title: String
    let summary: String
    let patientQueueReason: String
    let recommendedClinicianAction: String
    let auditTrail: [String]
    let consentScope: [String]
}

struct HealthKitDailySnapshot: Codable, Identifiable, Hashable {
    let dayKey: String
    var date: Date
    var sleepHours: Double
    var steps: Int
    var heartRate: Double
    var hrv: Double
    var activeEnergy: Double
    var qualityScore: Double
    var sourceCount: Int
    var restingHeartRate: Double? = nil
    var circadianRegularityScore: Double? = nil
    var heartRateSampleCount: Int? = nil
    var restingHeartRateSampleCount: Int? = nil
    var hrvSampleCount: Int? = nil
    var stepSampleCount: Int? = nil
    var hasWatchSource: Bool? = nil

    var id: String { dayKey }
}

struct HealthKitPipelineStore: Codable {
    static let passiveHistoryDays = 45

    var snapshots: [HealthKitDailySnapshot] = []

    static func decode(from rawValue: String) -> HealthKitPipelineStore {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HealthKitPipelineStore.self, from: data) else {
            return HealthKitPipelineStore()
        }
        return decoded
    }

    func encodedString() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    mutating func merge(_ incoming: [HealthKitDailySnapshot], maxDays: Int = passiveHistoryDays) {
        var byDay = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.dayKey, $0) })
        for snapshot in incoming {
            byDay[snapshot.dayKey] = snapshot
        }
        snapshots = byDay.values
            .sorted { $0.date > $1.date }
            .prefix(maxDays)
            .map { $0 }
    }
}

struct ClinicalDailyRecommendation: Identifiable, Hashable {
    let id: String
    let title: String
    let action: String
    let rationale: String
    let targetSignal: String
    let expectedWindow: String

    static let fallback = ClinicalDailyRecommendation(
        id: "maintain-routine",
        title: "Manter rotina protegida",
        action: "Faça o check-in de hoje e preserve uma janela regular de sono.",
        rationale: "Os sinais recentes não sugerem episódio prioritário, então a meta é manter estabilidade e dados consistentes.",
        targetSignal: "estabilidade",
        expectedWindow: "próximos 2-3 dias"
    )
}

struct RecommendationResponseProfile {
    let targetSignal: String
    let sampleCount: Int
    let completionCount: Int
    let averageNetImpact: Double
    let responseRate: Double

    var hasEnoughData: Bool { sampleCount >= 3 }
    var isHelpful: Bool { hasEnoughData && averageNetImpact >= 0.45 && responseRate >= 0.55 }
    var isHarmful: Bool { hasEnoughData && averageNetImpact <= -0.35 }
    var isNeutral: Bool { hasEnoughData && !isHelpful && !isHarmful }
}

struct RecommendationImpactResult: Hashable {
    let moodDelta: Double
    let anxietyDelta: Double
    let sleepDelta: Double
    let netImpact: Double

    var summary: String {
        if netImpact >= 0.6 {
            return "Sinais melhoraram após a recomendação."
        }
        if netImpact <= -0.6 {
            return "Sinais pioraram após a recomendação; próxima sugestão deve ser ajustada."
        }
        return "Impacto ainda neutro ou pequeno."
    }
}

struct AutomaticInterventionDetection: Hashable {
    let didComplete: Bool
    let evidence: String
}

enum AdaptiveRecommendationEngine {
    static func impact(
        baselineMood: Double,
        baselineAnxiety: Double,
        baselineSleepHours: Double,
        currentMood: Double,
        currentAnxiety: Double,
        currentSleepHours: Double
    ) -> RecommendationImpactResult {
        let moodDelta = currentMood - baselineMood
        let anxietyDelta = baselineAnxiety - currentAnxiety
        let sleepDelta = currentSleepHours - baselineSleepHours
        return RecommendationImpactResult(
            moodDelta: moodDelta,
            anxietyDelta: anxietyDelta,
            sleepDelta: sleepDelta,
            netImpact: moodDelta + anxietyDelta + sleepDelta * 0.35
        )
    }

    static func profile(for targetSignal: String, logs: [DailyRecommendationLog]) -> RecommendationResponseProfile? {
        let matching = logs
            .filter { $0.completed && $0.targetSignal == targetSignal }
            .compactMap { log -> Double? in
                guard let mood = log.impactMoodDelta,
                      let anxiety = log.impactAnxietyDelta,
                      let sleep = log.impactSleepDelta else { return nil }
                return mood + anxiety + sleep * 0.35
            }

        guard !matching.isEmpty else { return nil }
        let average = matching.reduce(0, +) / Double(matching.count)
        let responseRate = Double(matching.filter { $0 >= 0.35 }.count) / Double(matching.count)
        let completionCount = logs.filter { $0.completed && $0.targetSignal == targetSignal }.count
        return RecommendationResponseProfile(
            targetSignal: targetSignal,
            sampleCount: matching.count,
            completionCount: completionCount,
            averageNetImpact: average,
            responseRate: responseRate
        )
    }
}

enum AutomaticInterventionDetector {
    static func detect(
        recommendation: ClinicalDailyRecommendation,
        checkIn: DailyCheckIn,
        steps: Int
    ) -> AutomaticInterventionDetection {
        let context = "\(recommendation.id) \(recommendation.title) \(recommendation.action) \(recommendation.targetSignal) \(checkIn.journalEntry) \(checkIn.automaticThoughts)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let signal = recommendation.targetSignal.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let action = recommendation.action.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        if matchesSleep(signal: signal, action: action), checkIn.sleepHours >= 7 {
            return AutomaticInterventionDetection(didComplete: true, evidence: "sono registrado com \(String(format: "%.1f", checkIn.sleepHours))h")
        }
        if matchesSleep(signal: signal, action: action), containsAny(context, terms: ["dormi cedo", "rotina de sono", "janela de sono", "sem cafeina", "sem cafeína", "desliguei telas", "fui deitar"]) {
            return AutomaticInterventionDetection(didComplete: true, evidence: "texto indica proteção de sono")
        }

        if matchesMovement(signal: signal, action: action), steps >= 1_500 {
            return AutomaticInterventionDetection(didComplete: true, evidence: "\(steps) passos registrados")
        }
        if matchesMovement(signal: signal, action: action), containsAny(context, terms: ["caminhei", "caminhada", "exercicio", "exercício", "atividade fisica", "atividade física", "treino leve", "alonguei"]) {
            return AutomaticInterventionDetection(didComplete: true, evidence: "texto indica movimento leve")
        }

        if matchesMedication(signal: signal, action: action), checkIn.medicationTaken {
            return AutomaticInterventionDetection(didComplete: true, evidence: "medicação marcada como tomada")
        }

        if matchesRegulation(signal: signal, action: action), containsAny(context, terms: ["respirei", "respiracao", "respiração", "grounding", "aterramento", "meditei", "pausei", "pausa de 10", "relaxamento"]) {
            return AutomaticInterventionDetection(didComplete: true, evidence: "texto indica técnica de regulação")
        }

        if matchesActivation(signal: signal, action: action), containsAny(context, terms: ["tarefa pequena", "10 minutos", "banho", "arrumei", "sai de casa", "saí de casa", "organizei", "fiz uma coisa"]) {
            return AutomaticInterventionDetection(didComplete: true, evidence: "texto indica ativação mínima")
        }

        if matchesSafety(signal: signal, action: action), containsAny(context, terms: ["avisei", "falei com", "contato de seguranca", "contato de segurança", "pessoa de confianca", "pessoa de confiança", "plano de seguranca", "plano de segurança", "apoio"]) {
            return AutomaticInterventionDetection(didComplete: true, evidence: "texto indica acionamento de apoio")
        }

        return AutomaticInterventionDetection(didComplete: false, evidence: "")
    }

    private static func matchesSleep(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["sono", "circadian", "circadiano", "sleep"])
    }

    private static func matchesMovement(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["caminhada", "movimento", "atividade", "exercise", "exercicio", "exercício"])
    }

    private static func matchesMedication(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["medicacao", "medicação", "medication", "adesao", "adesão"])
    }

    private static func matchesRegulation(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["ansiedade", "ativacao", "ativação", "respiracao", "respiração", "grounding", "aterramento", "breath"])
    }

    private static func matchesActivation(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["depress", "ativacao minima", "ativação mínima", "tarefa pequena", "activation"])
    }

    private static func matchesSafety(signal: String, action: String) -> Bool {
        containsAny("\(signal) \(action)", terms: ["seguranca", "segurança", "safety", "suicid"])
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        terms.contains { term in
            text.contains(term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
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
struct NeuremiaBackupSnapshot: Codable {
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

    static func decode(from data: Data) throws -> NeuremiaBackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NeuremiaBackupSnapshot.self, from: data)
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


// MARK: - Gamification Models

/// Badge unlocked by the user for achievements
@Model
final class Badge {
    @Attribute(.unique) var badgeId: String
    var name: String
    var badgeDescription: String
    var iconName: String
    var category: String
    var tier: String
    var xpReward: Int
    var requirement: String
    var unlockedAt: Date?

    init(
        badgeId: String,
        name: String,
        badgeDescription: String,
        iconName: String,
        category: String,
        tier: String,
        xpReward: Int,
        requirement: String,
        unlockedAt: Date? = nil
    ) {
        self.badgeId = badgeId
        self.name = name
        self.badgeDescription = badgeDescription
        self.iconName = iconName
        self.category = category
        self.tier = tier
        self.xpReward = xpReward
        self.requirement = requirement
        self.unlockedAt = unlockedAt
    }
}

/// User's gamification profile tracking XP, level, and progress
@Model
final class GamificationProfile {
    var totalXP: Int
    var currentLevel: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastCheckInDate: Date?
    var weeklyCheckInGoal: Int
    var weeklyCheckInProgress: Int
    var weeklyGoalResetDate: Date
    var patient: PatientProfile?

    @Relationship(deleteRule: .cascade) var unlockedBadges: [Badge] = []

    init(
        totalXP: Int = 0,
        currentLevel: Int = 1,
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        lastCheckInDate: Date? = nil,
        weeklyCheckInGoal: Int = 7,
        weeklyCheckInProgress: Int = 0,
        weeklyGoalResetDate: Date = Date(),
        patient: PatientProfile? = nil
    ) {
        self.totalXP = totalXP
        self.currentLevel = currentLevel
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastCheckInDate = lastCheckInDate
        self.weeklyCheckInGoal = weeklyCheckInGoal
        self.weeklyCheckInProgress = weeklyCheckInProgress
        self.weeklyGoalResetDate = weeklyGoalResetDate
        self.patient = patient
    }
}

/// Log of daily mission completions
@Model
final class DailyMissionLog {
    @Attribute(.unique) var id: String
    var date: Date
    var missionId: String
    var isCompleted: Bool
    var xpEarned: Int
    var completedAt: Date?

    init(
        id: String = UUID().uuidString,
        date: Date = Date(),
        missionId: String,
        isCompleted: Bool = false,
        xpEarned: Int = 0,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.date = date
        self.missionId = missionId
        self.isCompleted = isCompleted
        self.xpEarned = xpEarned
        self.completedAt = completedAt
    }
}

@Model
final class DailyRecommendationLog {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var patient: PatientProfile?
    var recommendationId: String
    var title: String
    var action: String
    var rationale: String
    var targetSignal: String
    var completed: Bool
    var completedAt: Date?
    var baselineMood: Double
    var baselineAnxiety: Double
    var baselineSleepHours: Double
    var impactMoodDelta: Double?
    var impactAnxietyDelta: Double?
    var impactSleepDelta: Double?
    var impactSummary: String?

    init(
        date: Date = Date(),
        recommendationId: String,
        title: String,
        action: String,
        rationale: String,
        targetSignal: String,
        baselineMood: Double,
        baselineAnxiety: Double,
        baselineSleepHours: Double,
        completed: Bool = false,
        completedAt: Date? = nil,
        impactMoodDelta: Double? = nil,
        impactAnxietyDelta: Double? = nil,
        impactSleepDelta: Double? = nil,
        impactSummary: String? = nil
    ) {
        self.date = date
        self.dayKey = DailyCheckIn.dayKey(for: date)
        self.recommendationId = recommendationId
        self.title = title
        self.action = action
        self.rationale = rationale
        self.targetSignal = targetSignal
        self.completed = completed
        self.completedAt = completedAt
        self.baselineMood = baselineMood
        self.baselineAnxiety = baselineAnxiety
        self.baselineSleepHours = baselineSleepHours
        self.impactMoodDelta = impactMoodDelta
        self.impactAnxietyDelta = impactAnxietyDelta
        self.impactSleepDelta = impactSleepDelta
        self.impactSummary = impactSummary
    }
}

// MARK: - Schema Version

enum NeuremiaSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        PatientProfile.self,
        DailyCheckIn.self,
        ScaleAssessment.self,
        ClinicalAlert.self,
        ClinicalReport.self,
        Badge.self,
        GamificationProfile.self,
        DailyMissionLog.self,
    ]
}

enum NeuremiaSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] = NeuremiaSchemaV1.models
}

enum NeuremiaSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] = NeuremiaSchemaV1.models + [
        DailyRecommendationLog.self
    ]
}

enum NeuremiaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [NeuremiaSchemaV1.self, NeuremiaSchemaV2.self, NeuremiaSchemaV3.self]
    static var stages: [MigrationStage] = [
        .lightweight(fromVersion: NeuremiaSchemaV1.self, toVersion: NeuremiaSchemaV2.self),
        .lightweight(fromVersion: NeuremiaSchemaV2.self, toVersion: NeuremiaSchemaV3.self)
    ]
}

// MARK: - Causal insights

/// A single actionable pattern like
/// "When you sleep <6h for 2 days, anxiety rises 28% next day".
struct CausalInsight: Identifiable, Hashable {
    enum Confidence: String {
        case low, moderate, high

        var label: String {
            switch self {
            case .low: "Sinal inicial"
            case .moderate: "Padrão emergente"
            case .high: "Padrão consistente"
            }
        }
    }

    enum Direction {
        case increase, decrease

        var arrow: String {
            self == .increase ? "arrow.up.right" : "arrow.down.right"
        }
    }

    let id = UUID()
    let icon: String
    let tintName: String            // "orange", "indigo", "green" — resolved in the view
    let antecedent: String          // "Quando você dorme <6h por 2 dias"
    let consequent: String          // "sua ansiedade sobe"
    let deltaPercent: Double        // signed, e.g. +28.0 or -18.5
    let direction: Direction
    let sampleSize: Int             // number of trigger occurrences observed
    let confidence: Confidence
    let recommendation: String      // one short suggestion
    let signalKey: String           // machine-readable antecedent for adaptive matching
}

/// Pure functional engine that mines a 60-day check-in window and returns
/// quantitative "antecedent → consequent" patterns. Runs entirely on-device
/// against SwiftData records already loaded in memory — no server call.
enum CausalInsightsEngine {
    /// Minimum absolute delta (in %) required to surface an insight.
    private static let minDeltaPercent: Double = 15.0
    /// Minimum trigger occurrences required to consider the pattern real.
    private static let minSampleSize: Int = 3
    /// Maximum window analysed (days back from most recent check-in).
    private static let lookbackDays: Int = 60

    static func compute(from checkIns: [DailyCheckIn]) -> [CausalInsight] {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard chronological.count >= 7 else { return [] }

        // Trim to lookback window so old data doesn't dilute recent patterns.
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? .distantPast
        let recent = chronological.filter { $0.date >= cutoff }
        guard recent.count >= 7 else { return [] }

        var insights: [CausalInsight] = []

        // Rule 1: sleep debt (2 consecutive nights <6h) → next-day anxiety
        if let i = evaluatePair(
            recent,
            trigger: { prev, curr in prev.sleepHours < 6 && curr.sleepHours < 6 },
            outcome: { $0.anxiety },
            outcomeLagDays: 1,
            icon: "moon.zzz.fill",
            tintName: "indigo",
            antecedent: "Quando você dorme menos de 6h por 2 dias",
            consequentIncrease: "sua ansiedade sobe",
            consequentDecrease: "sua ansiedade cai",
            recommendationIncrease: "Priorize dormir 7h+ hoje para conter o efeito.",
            recommendationDecrease: "Este padrão parece protetor no seu caso.",
            signalKey: "sleep-debt-anxiety"
        ) {
            insights.append(i)
        }

        // Rule 2: sleep debt (2 consecutive nights <6h) → next-day mood
        if let i = evaluatePair(
            recent,
            trigger: { prev, curr in prev.sleepHours < 6 && curr.sleepHours < 6 },
            outcome: { $0.mood },
            outcomeLagDays: 1,
            icon: "moon.zzz",
            tintName: "purple",
            antecedent: "Quando você dorme menos de 6h por 2 dias",
            consequentIncrease: "seu humor melhora",
            consequentDecrease: "seu humor cai",
            recommendationIncrease: "Padrão pouco usual — vale registrar contexto.",
            recommendationDecrease: "Recuperar sono é a alavanca de maior efeito hoje.",
            signalKey: "sleep-debt-mood"
        ) {
            insights.append(i)
        }

        // Rule 3: missed medication → next-day mood
        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.medicationTaken == false },
            outcome: { $0.mood },
            outcomeLagDays: 1,
            icon: "pills.fill",
            tintName: "green",
            antecedent: "Quando você pula a medicação",
            consequentIncrease: "seu humor melhora no dia seguinte",
            consequentDecrease: "seu humor cai no dia seguinte",
            recommendationIncrease: "Compartilhe com seu médico — pode indicar ajuste de dose.",
            recommendationDecrease: "Um lembrete no mesmo horário pode ajudar.",
            signalKey: "missed-medication-mood"
        ) {
            insights.append(i)
        }

        // Rule 4: missed medication → next-day anxiety
        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.medicationTaken == false },
            outcome: { $0.anxiety },
            outcomeLagDays: 1,
            icon: "pills",
            tintName: "mint",
            antecedent: "Quando você pula a medicação",
            consequentIncrease: "sua ansiedade sobe no dia seguinte",
            consequentDecrease: "sua ansiedade cai no dia seguinte",
            recommendationIncrease: "Consistência no horário reduz o efeito rebote.",
            recommendationDecrease: "Anote esse padrão para discutir na próxima consulta.",
            signalKey: "missed-medication-anxiety"
        ) {
            insights.append(i)
        }

        // Rule 5: short single night (<5h) → same-day energy (next check-in)
        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.sleepHours < 5 },
            outcome: { $0.energy },
            outcomeLagDays: 1,
            icon: "battery.25",
            tintName: "orange",
            antecedent: "Quando você dorme menos de 5h",
            consequentIncrease: "sua energia sobe no dia seguinte",
            consequentDecrease: "sua energia cai no dia seguinte",
            recommendationIncrease: "Padrão incomum — talvez estimulantes no dia seguinte.",
            recommendationDecrease: "Cochilo de 20min à tarde pode compensar parcialmente.",
            signalKey: "short-sleep-energy"
        ) {
            insights.append(i)
        }

        // Rule 6: high anxiety (≥4) → sleep the following night
        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.anxiety >= 4 },
            outcome: { $0.sleepHours },
            outcomeLagDays: 1,
            icon: "bed.double.fill",
            tintName: "teal",
            antecedent: "Quando sua ansiedade fica alta",
            consequentIncrease: "seu sono aumenta na noite seguinte",
            consequentDecrease: "seu sono diminui na noite seguinte",
            recommendationIncrease: "Padrão positivo de recuperação.",
            recommendationDecrease: "Rotina relaxante antes de dormir pode quebrar o ciclo.",
            signalKey: "high-anxiety-sleep"
        ) {
            insights.append(i)
        }

        // Rule 7: high irritability (≥4) → next-day mood
        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.irritability >= 4 },
            outcome: { $0.mood },
            outcomeLagDays: 1,
            icon: "flame.fill",
            tintName: "red",
            antecedent: "Quando sua irritabilidade fica alta",
            consequentIncrease: "seu humor melhora no dia seguinte",
            consequentDecrease: "seu humor cai no dia seguinte",
            recommendationIncrease: "A liberação parece te aliviar — observe o contexto.",
            recommendationDecrease: "Dias irritados costumam preceder queda — planeje autocuidado.",
            signalKey: "high-irritability-mood"
        ) {
            insights.append(i)
        }

        if let i = evaluatePair(
            recent,
            trigger: { _, curr in hasAnyTerm(in: curr.journalEntry, terms: ["exercicio", "exercício", "caminhada", "atividade fisica", "atividade física", "treino leve"]) },
            outcome: { $0.mood },
            outcomeLagDays: 1,
            icon: "figure.walk",
            tintName: "green",
            antecedent: "Quando você faz exercício leve",
            consequentIncrease: "seu humor melhora no dia seguinte",
            consequentDecrease: "seu humor cai no dia seguinte",
            recommendationIncrease: "Repita uma caminhada curta hoje; este padrão ajudou seu humor.",
            recommendationDecrease: "Exercício pode estar pesado demais nesses dias; reduza intensidade e observe.",
            signalKey: "light-exercise-mood"
        ) {
            insights.append(i)
        }

        if let i = evaluatePair(
            recent,
            trigger: { _, curr in hasAnyTerm(in: curr.journalEntry, terms: ["exercicio", "exercício", "caminhada", "atividade fisica", "atividade física", "treino leve"]) },
            outcome: { $0.anxiety },
            outcomeLagDays: 1,
            icon: "figure.walk.circle.fill",
            tintName: "teal",
            antecedent: "Quando você faz uma caminhada curta",
            consequentIncrease: "sua ansiedade sobe em 24h",
            consequentDecrease: "sua ansiedade cai em 24h",
            recommendationIncrease: "Observe intensidade e contexto; talvez precise de uma ação mais leve.",
            recommendationDecrease: "A caminhada curta tem ajudado sua ansiedade — vale repetir hoje.",
            signalKey: "light-exercise-anxiety"
        ) {
            insights.append(i)
        }

        if let i = evaluatePair(
            recent,
            trigger: { _, curr in curr.sleepHours < 6 && hasLateMeetingSignal(in: curr.journalEntry) },
            outcome: { $0.anxiety },
            outcomeLagDays: 1,
            icon: "calendar.badge.clock",
            tintName: "orange",
            antecedent: "Quando reunião tarde vem junto de pouco sono",
            consequentIncrease: "sua ansiedade sobe no dia seguinte",
            consequentDecrease: "sua ansiedade cai no dia seguinte",
            recommendationIncrease: "Evite reunião tarde hoje ou proteja uma rotina curta de desaceleração.",
            recommendationDecrease: "Esse combo não piorou seus dados recentes; continue registrando contexto.",
            signalKey: "late-meeting-sleep-anxiety"
        ) {
            insights.append(i)
        }

        if let i = evaluatePair(
            recent,
            trigger: { prev, curr in !prev.medicationTaken && !curr.medicationTaken },
            outcome: { $0.anxiety },
            outcomeLagDays: 1,
            icon: "pills.circle.fill",
            tintName: "red",
            antecedent: "Quando você perde medicação por 2 dias",
            consequentIncrease: "sua ansiedade sobe no dia seguinte",
            consequentDecrease: "sua ansiedade cai no dia seguinte",
            recommendationIncrease: "Priorize retomar o plano combinado e avise seu profissional se houver dúvida.",
            recommendationDecrease: "Leve esse padrão para consulta; ele pode indicar ajuste do plano.",
            signalKey: "two-day-medication-gap-anxiety"
        ) {
            insights.append(i)
        }

        // Sort strongest first (biggest absolute delta wins), then by confidence.
        return insights.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return confidenceRank(lhs.confidence) > confidenceRank(rhs.confidence)
            }
            return abs(lhs.deltaPercent) > abs(rhs.deltaPercent)
        }
    }

    // MARK: - Core evaluation

    /// Evaluates a rule of the form "trigger observed on days T (and T-1) →
    /// outcome measured on day T+outcomeLagDays". Compares outcome mean under
    /// the trigger against baseline mean across the whole window; emits an
    /// insight if the effect is large enough and observed enough times.
    private static func evaluatePair(
        _ recent: [DailyCheckIn],
        trigger: (DailyCheckIn, DailyCheckIn) -> Bool,
        outcome: (DailyCheckIn) -> Double,
        outcomeLagDays: Int,
        icon: String,
        tintName: String,
        antecedent: String,
        consequentIncrease: String,
        consequentDecrease: String,
        recommendationIncrease: String,
        recommendationDecrease: String,
        signalKey: String
    ) -> CausalInsight? {
        guard recent.count >= 3 else { return nil }

        var triggeredOutcomes: [Double] = []
        // Iterate over pairs (prev, curr) and look outcomeLagDays after curr.
        for i in 1..<recent.count {
            let prev = recent[i - 1]
            let curr = recent[i]
            guard consecutiveDays(prev.date, curr.date, within: 2) else { continue }
            guard trigger(prev, curr) else { continue }

            // Find the outcome record: the earliest check-in strictly after
            // `curr.date` whose day-gap is <= outcomeLagDays + 1 (tolerates a
            // missed daily log).
            guard let outcomeRecord = firstCheckIn(
                after: curr,
                in: recent,
                maxGapDays: outcomeLagDays + 1
            ) else { continue }
            triggeredOutcomes.append(outcome(outcomeRecord))
        }

        guard triggeredOutcomes.count >= minSampleSize else { return nil }

        let baseline = recent.map(outcome)
        let baselineMean = mean(baseline)
        // Avoid noisy percentages when the baseline is tiny.
        guard baselineMean > 0.5 else { return nil }

        let triggeredMean = mean(triggeredOutcomes)
        let delta = ((triggeredMean - baselineMean) / baselineMean) * 100.0
        guard abs(delta) >= minDeltaPercent else { return nil }

        let direction: CausalInsight.Direction = delta >= 0 ? .increase : .decrease
        let consequent = direction == .increase ? consequentIncrease : consequentDecrease
        let recommendation = direction == .increase ? recommendationIncrease : recommendationDecrease
        let confidence: CausalInsight.Confidence = {
            switch triggeredOutcomes.count {
            case ..<5: return .low
            case 5..<10: return .moderate
            default: return .high
            }
        }()

        return CausalInsight(
            icon: icon,
            tintName: tintName,
            antecedent: antecedent,
            consequent: consequent,
            deltaPercent: delta,
            direction: direction,
            sampleSize: triggeredOutcomes.count,
            confidence: confidence,
            recommendation: recommendation,
            signalKey: signalKey
        )
    }

    // MARK: - Helpers

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// True if `later` falls within `within` calendar days after `earlier`.
    private static func consecutiveDays(_ earlier: Date, _ later: Date, within: Int) -> Bool {
        let cal = Calendar(identifier: .iso8601)
        guard let diff = cal.dateComponents([.day], from: cal.startOfDay(for: earlier), to: cal.startOfDay(for: later)).day else {
            return false
        }
        return diff >= 1 && diff <= within
    }

    private static func firstCheckIn(
        after reference: DailyCheckIn,
        in ordered: [DailyCheckIn],
        maxGapDays: Int
    ) -> DailyCheckIn? {
        let cal = Calendar(identifier: .iso8601)
        let refDay = cal.startOfDay(for: reference.date)
        for candidate in ordered where candidate.date > reference.date {
            let candDay = cal.startOfDay(for: candidate.date)
            guard let gap = cal.dateComponents([.day], from: refDay, to: candDay).day else { continue }
            if gap >= 1 && gap <= maxGapDays {
                return candidate
            }
            if gap > maxGapDays { break }
        }
        return nil
    }

    private static func confidenceRank(_ confidence: CausalInsight.Confidence) -> Int {
        switch confidence {
        case .high: 3
        case .moderate: 2
        case .low: 1
        }
    }

    private static func hasAnyTerm(in text: String, terms: [String]) -> Bool {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return terms.contains { term in
            normalized.contains(term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
        }
    }

    private static func hasLateMeetingSignal(in text: String) -> Bool {
        hasAnyTerm(in: text, terms: ["reuniao tarde", "reunião tarde", "reuniao a noite", "reunião à noite", "call tarde", "call a noite", "plantao", "plantão"])
    }
}

// MARK: - Personal baseline

/// Individual "normal" for a single metric, learned from the user's own history
/// (30–60 day window, current week excluded so it doesn't self-compare).
///
/// The goal is to replace population thresholds ("sleep <6h is bad") with a
/// personal reference ("your normal sleep is 7.4h ± 0.9h; today you're at 5.1h,
/// which is 2.5σ below your baseline"). This is what Whoop calls a "learned
/// baseline" and it's what makes anomaly detection actually specific.
struct PersonalBaseline: Identifiable, Hashable {
    /// Which metric was learned. Determines display label, unit and which
    /// direction of drift counts as a warning sign (e.g., mood down = bad,
    /// anxiety up = bad).
    enum Metric: String, CaseIterable {
        case mood, anxiety, sleepHours, energy, irritability

        var label: String {
            switch self {
            case .mood: "Humor"
            case .anxiety: "Ansiedade"
            case .sleepHours: "Sono"
            case .energy: "Energia"
            case .irritability: "Irritabilidade"
            }
        }

        var icon: String {
            switch self {
            case .mood: "face.smiling"
            case .anxiety: "waveform.path.ecg"
            case .sleepHours: "moon.stars.fill"
            case .energy: "bolt.fill"
            case .irritability: "flame.fill"
            }
        }

        var tintName: String {
            switch self {
            case .mood: "purple"
            case .anxiety: "indigo"
            case .sleepHours: "teal"
            case .energy: "orange"
            case .irritability: "red"
            }
        }

        /// True when a *higher* value is worse for this metric. Used to decide
        /// whether the current z-score points toward decompensation.
        var higherIsWorse: Bool {
            switch self {
            case .anxiety, .irritability: true
            case .mood, .sleepHours, .energy: false
            }
        }

        var unit: String {
            self == .sleepHours ? "h" : ""
        }

        /// Format a value with the metric's natural precision. Sleep gets 1
        /// decimal, subjective scales get 1 decimal too (they're 0–5 floats).
        func format(_ value: Double) -> String {
            String(format: "%.1f%@", value, unit)
        }
    }

    /// How the current week compares to the personal baseline. Zones are in
    /// z-score space so a "yellow" for one person may correspond to a raw
    /// value that would be green for another — which is the whole point.
    enum Status: String {
        case normal        // |z| <= 1
        case watch         // 1 < |z| <= 2 in concerning direction
        case alert         // |z| > 2 in concerning direction

        var label: String {
            switch self {
            case .normal: "Dentro do seu padrão"
            case .watch: "Levemente fora"
            case .alert: "Bem fora do normal"
            }
        }
    }

    let id = UUID()
    let metric: Metric
    /// Mean over the historical window (baseline center).
    let center: Double
    /// Sample standard deviation over the historical window.
    let stdDev: Double
    /// Most recent 7-day mean (what the user is "at" right now).
    let currentMean: Double
    /// Signed z-score of currentMean vs (center, stdDev). Sign is raw
    /// (positive = above baseline). Concerning-direction handling is done at
    /// render time via `metric.higherIsWorse`.
    let zScore: Double
    /// Number of daily records used to fit the baseline (excluding current week).
    let baselineSampleSize: Int
    /// Slope of the baseline window in units per day (least squares fit).
    /// Negative slope on mood/sleep/energy is a decompensation flag.
    let driftPerDay: Double

    var status: Status {
        let concerningDeviation: Double = metric.higherIsWorse ? zScore : -zScore
        if concerningDeviation > 2 { return .alert }
        if concerningDeviation > 1 { return .watch }
        return .normal
    }

    /// Convenience — one-line summary like "Seu normal: 7.4h ± 0.9h".
    var centerCopy: String {
        "Seu normal: \(metric.format(center)) ± \(metric.format(stdDev))"
    }

    /// Convenience — "Hoje: 5.1h (2.5σ abaixo)".
    var currentCopy: String {
        let sigmaLabel: String
        if abs(zScore) < 0.5 {
            sigmaLabel = "no seu padrão"
        } else {
            let direction = zScore > 0 ? "acima" : "abaixo"
            sigmaLabel = String(format: "%.1fσ %@", abs(zScore), direction)
        }
        return "Semana atual: \(metric.format(currentMean)) (\(sigmaLabel))"
    }
}

/// Learns per-user baselines from local SwiftData check-ins. Pure — no side
/// effects, no persistence. Cheap enough to recompute on every view render.
enum PersonalBaselineEngine {
    /// Historical window used to learn the baseline (days before today).
    private static let historicalWindowDays = 60
    /// Recent window intentionally excluded from the historical window so the
    /// baseline is not contaminated by what we're measuring against.
    private static let currentWindowDays = 7
    /// Minimum historical samples required before a baseline is trustworthy.
    private static let minHistoricalSamples = 14
    /// Minimum current-week samples before we compare.
    private static let minCurrentSamples = 3

    struct Summary {
        let baselines: [PersonalBaseline]
        /// True when the user simply doesn't have enough history yet.
        let warmingUp: Bool
        /// How many more days of consistent check-ins are needed to unlock.
        let daysUntilReady: Int
    }

    static func compute(from checkIns: [DailyCheckIn], now: Date = Date()) -> Summary {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: now)

        // Split into historical (baseline) and current-week records.
        // historicalEnd is exclusive of the last `currentWindowDays` days.
        guard
            let historicalStart = cal.date(byAdding: .day, value: -historicalWindowDays, to: today),
            let historicalEnd = cal.date(byAdding: .day, value: -currentWindowDays, to: today),
            let currentStart = cal.date(byAdding: .day, value: -currentWindowDays, to: today)
        else {
            return Summary(baselines: [], warmingUp: true, daysUntilReady: minHistoricalSamples)
        }

        let historical = checkIns.filter { $0.date >= historicalStart && $0.date < historicalEnd }
        let current = checkIns.filter { $0.date >= currentStart && $0.date <= now }

        if historical.count < minHistoricalSamples {
            return Summary(
                baselines: [],
                warmingUp: true,
                daysUntilReady: max(0, minHistoricalSamples - historical.count)
            )
        }

        var baselines: [PersonalBaseline] = []
        for metric in PersonalBaseline.Metric.allCases {
            let historicalValues = historical.map { value(of: metric, in: $0) }
            let currentValues = current.map { value(of: metric, in: $0) }
            guard currentValues.count >= minCurrentSamples else { continue }

            let center = mean(historicalValues)
            let sd = stdDev(historicalValues, mean: center)
            let currentMean = mean(currentValues)
            // Avoid divide-by-zero when the user is perfectly consistent — a
            // 0.5 floor treats "extremely stable" as still learnable so a
            // sudden change still surfaces as a large-ish z-score.
            let effectiveSD = max(sd, 0.5)
            let z = (currentMean - center) / effectiveSD
            let slope = leastSquaresSlopePerDay(historical, metric: metric, cal: cal)

            baselines.append(PersonalBaseline(
                metric: metric,
                center: center,
                stdDev: sd,
                currentMean: currentMean,
                zScore: z,
                baselineSampleSize: historicalValues.count,
                driftPerDay: slope
            ))
        }

        // Show alerts first, then watch, then normal. Within a tier, biggest
        // absolute deviation wins.
        let sorted = baselines.sorted { lhs, rhs in
            if statusRank(lhs.status) != statusRank(rhs.status) {
                return statusRank(lhs.status) > statusRank(rhs.status)
            }
            return abs(lhs.zScore) > abs(rhs.zScore)
        }
        return Summary(baselines: sorted, warmingUp: false, daysUntilReady: 0)
    }

    // MARK: - Helpers

    private static func value(of metric: PersonalBaseline.Metric, in checkIn: DailyCheckIn) -> Double {
        switch metric {
        case .mood: checkIn.mood
        case .anxiety: checkIn.anxiety
        case .sleepHours: checkIn.sleepHours
        case .energy: checkIn.energy
        case .irritability: checkIn.irritability
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func stdDev(_ values: [Double], mean m: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// OLS slope in metric-units per day. Uses days-since-earliest as x so the
    /// slope is directly interpretable ("mood drops 0.03 per day").
    private static func leastSquaresSlopePerDay(
        _ records: [DailyCheckIn],
        metric: PersonalBaseline.Metric,
        cal: Calendar
    ) -> Double {
        guard records.count >= 3, let anchor = records.map({ $0.date }).min() else { return 0 }
        let anchorDay = cal.startOfDay(for: anchor)
        var xs: [Double] = []
        var ys: [Double] = []
        for record in records {
            let day = cal.startOfDay(for: record.date)
            let diff = cal.dateComponents([.day], from: anchorDay, to: day).day ?? 0
            xs.append(Double(diff))
            ys.append(value(of: metric, in: record))
        }
        let xMean = mean(xs)
        let yMean = mean(ys)
        var num = 0.0
        var den = 0.0
        for i in xs.indices {
            let dx = xs[i] - xMean
            num += dx * (ys[i] - yMean)
            den += dx * dx
        }
        return den == 0 ? 0 : num / den
    }

    private static func statusRank(_ status: PersonalBaseline.Status) -> Int {
        switch status {
        case .alert: 3
        case .watch: 2
        case .normal: 1
        }
    }
}

extension PersonalBaselineEngine.Summary {
    /// Convenience lookup — episode detectors need `(center, stdDev)` per
    /// metric to compute per-day z-scores against the same baseline the UI
    /// shows in `PersonalBaselineCard`.
    func baseline(for metric: PersonalBaseline.Metric) -> PersonalBaseline? {
        baselines.first { $0.metric == metric }
    }
}

// MARK: - Robust biometric baseline

struct HRVContextBaselineStore: Codable, Equatable {
    struct Bucket: Codable, Equatable {
        var key: String
        var label: String
        var mean: Double
        var varianceAccumulator: Double
        var samples: Int
        var lastUpdated: Date

        var stdDev: Double {
            samples > 1 ? sqrt(varianceAccumulator / Double(samples - 1)) : 0
        }

        mutating func record(_ value: Double, date: Date) {
            samples += 1
            let delta = value - mean
            mean += delta / Double(samples)
            let delta2 = value - mean
            varianceAccumulator += delta * delta2
            lastUpdated = date
        }
    }

    var buckets: [String: Bucket] = [:]

    mutating func record(
        hrv: Double,
        date: Date,
        ppgStress: Double,
        sleepHours: Double,
        medicationTaken: Bool,
        socialLoad: Int
    ) {
        let context = Self.contextLabel(ppgStress: ppgStress, sleepHours: sleepHours, medicationTaken: medicationTaken, socialLoad: socialLoad)
        let key = "\(Self.timeBand(for: date).key)-\(context.key)"
        if var bucket = buckets[key] {
            bucket.record(hrv, date: date)
            buckets[key] = bucket
        } else {
            buckets[key] = Bucket(
                key: key,
                label: "\(Self.timeBand(for: date).label) • \(context.label)",
                mean: hrv,
                varianceAccumulator: 0,
                samples: 1,
                lastUpdated: date
            )
        }
    }

    func bucket(
        for date: Date,
        ppgStress: Double,
        sleepHours: Double,
        medicationTaken: Bool,
        socialLoad: Int
    ) -> Bucket? {
        let context = Self.contextLabel(ppgStress: ppgStress, sleepHours: sleepHours, medicationTaken: medicationTaken, socialLoad: socialLoad)
        let key = "\(Self.timeBand(for: date).key)-\(context.key)"
        return buckets[key]
    }

    static func decode(from string: String) -> HRVContextBaselineStore {
        guard let data = string.data(using: .utf8),
              let store = try? JSONDecoder().decode(HRVContextBaselineStore.self, from: data) else {
            return HRVContextBaselineStore()
        }
        return store
    }

    func encodedString() -> String {
        guard let data = try? JSONEncoder().encode(self) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func timeBand(for date: Date) -> (key: String, label: String) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return ("morning", "Manhã")
        case 12..<18:
            return ("afternoon", "Tarde")
        case 18..<23:
            return ("evening", "Noite")
        default:
            return ("late", "Madrugada")
        }
    }

    static func contextLabel(ppgStress: Double, sleepHours: Double, medicationTaken: Bool, socialLoad: Int) -> (key: String, label: String) {
        if socialLoad >= 2 || ppgStress >= 70 {
            return ("high-load", "alta carga")
        }
        if sleepHours > 0 && sleepHours < 6 {
            return ("sleep-debt", "pouco sono")
        }
        if !medicationTaken {
            return ("med-pending", "medicação pendente")
        }
        return ("baseline", "rotina")
    }
}

struct BiometricBaselineSummary {
    struct Item: Identifiable, Hashable {
        enum Status {
            case stable, watch, alert
        }

        let id = UUID()
        let icon: String
        let title: String
        let value: String
        let detail: String
        let status: Status
    }

    let items: [Item]
    let responsePatterns: [CausalInsight]
    let readinessText: String
}

enum BiometricBaselineEngine {
    static func compute(
        checkIns: [DailyCheckIn],
        currentHRV: Double,
        globalHRVBaseline: Double,
        hrvStore: HRVContextBaselineStore,
        currentSleepHours: Double,
        medicationTaken: Bool,
        ppgStress: Double,
        activeTriggers: [String],
        now: Date = Date()
    ) -> BiometricBaselineSummary {
        let sorted = checkIns.sorted { $0.date < $1.date }
        var items: [BiometricBaselineSummary.Item] = []
        let socialLoad = socialLoadScore(activeTriggers: activeTriggers, latestText: sorted.last?.journalEntry ?? "")

        if let hrvBucket = hrvStore.bucket(for: now, ppgStress: ppgStress, sleepHours: currentSleepHours, medicationTaken: medicationTaken, socialLoad: socialLoad), hrvBucket.samples >= 3, currentHRV > 0 {
            let delta = ((currentHRV - hrvBucket.mean) / max(hrvBucket.mean, 1)) * 100
            items.append(.init(
                icon: "heart.text.square.fill",
                title: "HRV por horário/contexto",
                value: "\(Int(delta.rounded()))%",
                detail: "\(hrvBucket.label): normal \(String(format: "%.0f", hrvBucket.mean)) ms, \(hrvBucket.samples) amostra(s).",
                status: delta <= -15 ? .alert : delta <= -8 ? .watch : .stable
            ))
        } else if globalHRVBaseline > 0, currentHRV > 0 {
            let delta = ((currentHRV - globalHRVBaseline) / max(globalHRVBaseline, 1)) * 100
            items.append(.init(
                icon: "heart.text.square",
                title: "HRV global",
                value: "\(Int(delta.rounded()))%",
                detail: "Baseline contextual ainda calibrando; usando referência global.",
                status: delta <= -15 ? .alert : delta <= -8 ? .watch : .stable
            ))
        } else {
            items.append(.init(
                icon: "heart.text.square",
                title: "HRV contextual",
                value: "Calibrando",
                detail: "Meça HRV em horários parecidos para formar buckets por contexto.",
                status: .watch
            ))
        }

        if let weekdaySleep = weekdaySleepBaseline(from: sorted, weekday: Calendar.current.component(.weekday, from: now)), currentSleepHours > 0 {
            let delta = currentSleepHours - weekdaySleep.mean
            items.append(.init(
                icon: "calendar",
                title: "Sono típico do dia",
                value: String(format: "%+.1fh", delta),
                detail: "\(weekdayName(now)): normal \(String(format: "%.1f", weekdaySleep.mean))h com \(weekdaySleep.samples) registro(s).",
                status: delta <= -1.5 ? .alert : delta <= -0.75 ? .watch : .stable
            ))
        }

        let circadian = circadianVariability(from: sorted)
        items.append(.init(
            icon: "clock.arrow.2.circlepath",
            title: "Variabilidade circadiana",
            value: "\(circadian.score)/100",
            detail: circadian.detail,
            status: circadian.score >= 65 ? .alert : circadian.score >= 40 ? .watch : .stable
        ))

        items.append(.init(
            icon: "person.2.wave.2.fill",
            title: "Carga social/eventos",
            value: "\(socialLoad)/4",
            detail: socialLoadDetail(activeTriggers: activeTriggers),
            status: socialLoad >= 3 ? .alert : socialLoad >= 2 ? .watch : .stable
        ))

        let responses = CausalInsightsEngine.compute(from: sorted).filter { insight in
            ["missed-medication-mood", "missed-medication-anxiety", "two-day-medication-gap-anxiety", "sleep-debt-anxiety", "sleep-debt-mood", "light-exercise-mood", "late-meeting-sleep-anxiety"].contains(insight.signalKey)
        }

        let readiness = hrvStore.buckets.values.reduce(0) { $0 + $1.samples } >= 6 && sorted.count >= 14
            ? "Baseline biométrico pronto para comparação individual."
            : "Baseline biométrico em calibração; quanto mais check-ins e leituras em horários parecidos, melhor."

        return BiometricBaselineSummary(items: items, responsePatterns: Array(responses.prefix(3)), readinessText: readiness)
    }

    private static func weekdaySleepBaseline(from checkIns: [DailyCheckIn], weekday: Int) -> (mean: Double, samples: Int)? {
        let values = checkIns.filter { Calendar.current.component(.weekday, from: $0.date) == weekday }.map(\.sleepHours)
        guard values.count >= 2 else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.count)
    }

    private static func circadianVariability(from checkIns: [DailyCheckIn]) -> (score: Int, detail: String) {
        let recent = Array(checkIns.suffix(14))
        guard recent.count >= 5 else {
            return (0, "Ainda sem dados suficientes para estimar regularidade.")
        }
        let sleepValues = recent.map(\.sleepHours)
        let sleepMean = sleepValues.reduce(0, +) / Double(sleepValues.count)
        let variance = sleepValues.reduce(0.0) { $0 + pow($1 - sleepMean, 2) } / Double(max(sleepValues.count - 1, 1))
        let sleepSD = sqrt(variance)
        let shortNights = recent.filter { $0.sleepHours < 6 }.count
        let score = Int(min(100, (sleepSD / 2.5) * 55 + (Double(shortNights) / Double(recent.count)) * 45).rounded())
        return (score, "\(String(format: "%.1f", sleepSD))h de variação; \(shortNights) noite(s) <6h nos últimos 14 registros.")
    }

    private static func socialLoadScore(activeTriggers: [String], latestText: String) -> Int {
        var score = 0
        if activeTriggers.contains(where: { $0.localizedCaseInsensitiveContains("conflito") || $0.localizedCaseInsensitiveContains("estresse") }) { score += 1 }
        if activeTriggers.contains(where: { $0.localizedCaseInsensitiveContains("mudança") || $0.localizedCaseInsensitiveContains("rotina") }) { score += 1 }
        if activeTriggers.contains(where: { $0.localizedCaseInsensitiveContains("álcool") || $0.localizedCaseInsensitiveContains("alcool") }) { score += 1 }
        if containsAny(latestText, terms: ["reuniao", "reunião", "evento", "festa", "plantao", "plantão", "conflito"]) { score += 1 }
        return min(score, 4)
    }

    private static func socialLoadDetail(activeTriggers: [String]) -> String {
        if activeTriggers.isEmpty {
            return "Sem gatilho social/evento marcado hoje."
        }
        return "Gatilhos ativos: \(activeTriggers.prefix(3).joined(separator: ", "))."
    }

    private static func containsAny(_ text: String, terms: [String]) -> Bool {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return terms.contains { normalized.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) }
    }

    private static func weekdayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).capitalized
    }
}

// MARK: - Early episode detection

/// A single detected prodromal / episode pattern (mania, depressive relapse,
/// anxiety escalation, suicide-risk emergence, adherence failure, circadian
/// disruption). Each signal names its evidence explicitly so a clinician can
/// audit *why* the app raised it — no black-box scoring.
struct EpisodeRiskSignal: Identifiable, Hashable {
    /// Which prodromal syndrome the detector is flagging. Mirrors the
    /// clinically distinct trajectories from DSM-5 / CANMAT prodromes, not
    /// a single "risk" bucket.
    enum Kind: String {
        case mania                  // hypomanic / manic onset
        case depression             // sustained depressive relapse
        case anxiety                // sustained anxiety crisis
        case suicide                // suicidal ideation surface
        case adherence              // medication non-adherence pattern
        case circadian              // sleep instability / rhythm break

        var label: String {
            switch self {
            case .mania: "Sinais de virada maníaca"
            case .depression: "Padrão depressivo em curso"
            case .anxiety: "Escalada de ansiedade"
            case .suicide: "Sinal de ideação suicida"
            case .adherence: "Adesão à medicação em queda"
            case .circadian: "Instabilidade circadiana"
            }
        }

        var icon: String {
            switch self {
            case .mania: "bolt.badge.a.fill"
            case .depression: "cloud.rain.fill"
            case .anxiety: "waveform.path.ecg.rectangle"
            case .suicide: "cross.case.fill"
            case .adherence: "pills.circle"
            case .circadian: "moon.circle"
            }
        }

        var tintName: String {
            switch self {
            case .mania: "orange"
            case .depression: "indigo"
            case .anxiety: "red"
            case .suicide: "pink"
            case .adherence: "yellow"
            case .circadian: "teal"
            }
        }
    }

    /// How advanced the pattern is. `active` corresponds to a full-blown
    /// episode window; `emerging` to a persistent prodrome; `early` to a
    /// signal that should be watched but is not yet reliable.
    enum Severity: String {
        case early, emerging, active

        var label: String {
            switch self {
            case .early: "Sinal inicial"
            case .emerging: "Padrão emergente"
            case .active: "Padrão ativo"
            }
        }

        /// Whether this signal should be routed to a clinician. `active`
        /// suicide gets special treatment upstream — this is the *default*
        /// for the other kinds.
        var deservesClinicianReview: Bool {
            self != .early
        }
    }

    let id = UUID()
    let kind: Kind
    let severity: Severity
    /// Human-readable list of evidence lines ("Sono 2.1σ abaixo em 4 de 7 dias").
    /// Ordered by importance so the top item is the strongest signal.
    let evidence: [String]
    /// One-sentence action tailored to the kind. Not medical advice — a nudge.
    let recommendation: String
    /// Number of daily records that contributed to this detection.
    let windowDays: Int
}

/// Detects prodromal / episode patterns by scanning the last 14 days of
/// check-ins and combining raw thresholds with personal-baseline z-scores.
/// Runs entirely on-device against records already in memory.
enum EpisodeRiskEngine {
    private static let windowDays = 14
    private static let recentWindowDays = 7

    static func compute(from checkIns: [DailyCheckIn], now: Date = Date()) -> [EpisodeRiskSignal] {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: now)
        guard let cutoff = cal.date(byAdding: .day, value: -windowDays, to: today) else { return [] }

        let window = checkIns
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
        // Suicide detector uses a longer horizon so a 30-day ideation event
        // still gets flagged even after the window rolls forward.
        let baselines = PersonalBaselineEngine.compute(from: checkIns, now: now)

        guard window.count >= 3 else {
            // Even with sparse recent data, suicide signal is worth surfacing
            // whenever it's ever been reported.
            return [detectSuicide(from: checkIns, now: now)].compactMap { $0 }
        }

        var signals: [EpisodeRiskSignal] = []
        if let s = detectMania(window: window, baselines: baselines) { signals.append(s) }
        if let s = detectDepression(window: window, baselines: baselines) { signals.append(s) }
        if let s = detectAnxiety(window: window, baselines: baselines) { signals.append(s) }
        if let s = detectSuicide(from: checkIns, now: now) { signals.append(s) }
        if let s = detectAdherence(window: window) { signals.append(s) }
        if let s = detectCircadian(window: window, baselines: baselines) { signals.append(s) }

        return signals.sorted { severityRank($0.severity) > severityRank($1.severity) }
    }

    // MARK: - Mania

    private static func detectMania(
        window: [DailyCheckIn],
        baselines: PersonalBaselineEngine.Summary
    ) -> EpisodeRiskSignal? {
        let last7 = Array(window.suffix(recentWindowDays))
        guard last7.count >= 3 else { return nil }

        // Prodromal mania (DSM-5 / CANMAT): sleep drop + activation
        // (energy/mood elevation or irritability) sustained for several days.
        var sleepDropDays = 0
        var activationDays = 0
        var bothSameDayDays = 0

        for ci in last7 {
            let sleepFlag = isSleepReduced(ci, baseline: baselines.baseline(for: .sleepHours))
            let activationFlag = isActivationHigh(ci, baselines: baselines)
            if sleepFlag { sleepDropDays += 1 }
            if activationFlag { activationDays += 1 }
            if sleepFlag && activationFlag { bothSameDayDays += 1 }
        }

        guard sleepDropDays >= 2 && activationDays >= 2 else { return nil }

        let severity: EpisodeRiskSignal.Severity
        if bothSameDayDays >= 4 {
            severity = .active
        } else if bothSameDayDays >= 2 {
            severity = .emerging
        } else {
            severity = .early
        }

        var evidence: [String] = []
        evidence.append("Sono reduzido em \(sleepDropDays) de \(last7.count) dias.")
        evidence.append("Energia/humor/irritabilidade elevados em \(activationDays) dias.")
        if bothSameDayDays >= 2 {
            evidence.append("Sono baixo E ativação alta no mesmo dia: \(bothSameDayDays) vez(es).")
        }

        return EpisodeRiskSignal(
            kind: .mania,
            severity: severity,
            evidence: evidence,
            recommendation: "Combine com seu psiquiatra: virada afetiva pode exigir ajuste rápido. Priorize sono regular.",
            windowDays: last7.count
        )
    }

    // MARK: - Depression

    private static func detectDepression(
        window: [DailyCheckIn],
        baselines: PersonalBaselineEngine.Summary
    ) -> EpisodeRiskSignal? {
        let last7 = Array(window.suffix(recentWindowDays))
        guard last7.count >= 3 else { return nil }

        var lowMoodDays = 0
        var lowEnergyDays = 0
        var bothSameDayDays = 0

        for ci in last7 {
            let moodLow = isMoodLow(ci, baseline: baselines.baseline(for: .mood))
            let energyLow = isEnergyLow(ci, baseline: baselines.baseline(for: .energy))
            if moodLow { lowMoodDays += 1 }
            if energyLow { lowEnergyDays += 1 }
            if moodLow && energyLow { bothSameDayDays += 1 }
        }

        guard lowMoodDays >= 3 else { return nil }

        let severity: EpisodeRiskSignal.Severity
        if bothSameDayDays >= 5 {
            severity = .active
        } else if bothSameDayDays >= 3 {
            severity = .emerging
        } else {
            severity = .early
        }

        var evidence: [String] = []
        evidence.append("Humor baixo em \(lowMoodDays) de \(last7.count) dias.")
        evidence.append("Energia baixa em \(lowEnergyDays) dias.")
        if bothSameDayDays >= 3 {
            evidence.append("Combinação humor baixo + energia baixa em \(bothSameDayDays) dias.")
        }

        return EpisodeRiskSignal(
            kind: .depression,
            severity: severity,
            evidence: evidence,
            recommendation: "Traga esse padrão para a próxima consulta. Ativação comportamental leve (caminhada curta, luz da manhã) pode ajudar entre sessões.",
            windowDays: last7.count
        )
    }

    // MARK: - Anxiety

    private static func detectAnxiety(
        window: [DailyCheckIn],
        baselines: PersonalBaselineEngine.Summary
    ) -> EpisodeRiskSignal? {
        let last7 = Array(window.suffix(recentWindowDays))
        guard last7.count >= 3 else { return nil }

        var highAnxietyDays = 0
        var consecutiveMax = 0
        var currentStreak = 0
        for ci in last7 {
            let anxietyHigh = isAnxietyHigh(ci, baseline: baselines.baseline(for: .anxiety))
            if anxietyHigh {
                highAnxietyDays += 1
                currentStreak += 1
                consecutiveMax = max(consecutiveMax, currentStreak)
            } else {
                currentStreak = 0
            }
        }

        guard highAnxietyDays >= 3 else { return nil }

        let severity: EpisodeRiskSignal.Severity
        if consecutiveMax >= 5 {
            severity = .active
        } else if consecutiveMax >= 3 {
            severity = .emerging
        } else {
            severity = .early
        }

        var evidence: [String] = []
        evidence.append("Ansiedade alta em \(highAnxietyDays) de \(last7.count) dias.")
        if consecutiveMax >= 3 {
            evidence.append("Sequência de \(consecutiveMax) dia(s) consecutivo(s) com ansiedade alta.")
        }

        return EpisodeRiskSignal(
            kind: .anxiety,
            severity: severity,
            evidence: evidence,
            recommendation: "Vale registrar gatilhos no diário e revisar plano de manejo com sua equipe.",
            windowDays: last7.count
        )
    }

    // MARK: - Suicide risk

    private static func detectSuicide(from checkIns: [DailyCheckIn], now: Date = Date()) -> EpisodeRiskSignal? {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: now)
        guard let cutoff30 = cal.date(byAdding: .day, value: -30, to: today) else { return nil }
        let recent = checkIns.filter { $0.suicidalIdeation && $0.date >= cutoff30 }
        guard !recent.isEmpty else { return nil }

        let in7d = cal.date(byAdding: .day, value: -7, to: today)
            .map { c in recent.filter { $0.date >= c }.count } ?? 0

        let severity: EpisodeRiskSignal.Severity
        if in7d >= 2 {
            severity = .active
        } else if in7d >= 1 {
            severity = .emerging
        } else {
            severity = .early
        }

        var evidence: [String] = []
        evidence.append("\(recent.count) registro(s) com ideação nos últimos 30 dias.")
        if in7d > 0 {
            evidence.append("\(in7d) registro(s) nos últimos 7 dias.")
        }

        return EpisodeRiskSignal(
            kind: .suicide,
            severity: severity,
            evidence: evidence,
            recommendation: "Ative seu plano de segurança. CVV 188 (BR), 988 (EUA). Compartilhe com sua rede de cuidado agora.",
            windowDays: 30
        )
    }

    // MARK: - Adherence

    private static func detectAdherence(window: [DailyCheckIn]) -> EpisodeRiskSignal? {
        guard window.count >= 5 else { return nil }
        let missed = window.filter { !$0.medicationTaken }.count
        let adherence = 1.0 - Double(missed) / Double(window.count)
        guard adherence < 0.8 else { return nil }

        let severity: EpisodeRiskSignal.Severity
        if adherence < 0.5 {
            severity = .active
        } else if adherence < 0.7 {
            severity = .emerging
        } else {
            severity = .early
        }

        let percent = Int((adherence * 100).rounded())
        return EpisodeRiskSignal(
            kind: .adherence,
            severity: severity,
            evidence: [
                "Adesão de \(percent)% em \(window.count) dias.",
                "\(missed) dose(s) marcadas como não tomadas."
            ],
            recommendation: "Alarme fixo no mesmo horário ou porta-comprimidos semanal costumam recuperar adesão. Conte pro seu médico se houver efeito colateral.",
            windowDays: window.count
        )
    }

    // MARK: - Circadian

    private static func detectCircadian(
        window: [DailyCheckIn],
        baselines: PersonalBaselineEngine.Summary
    ) -> EpisodeRiskSignal? {
        guard window.count >= 5 else { return nil }
        let sleepValues = window.map(\.sleepHours)
        let mean = sleepValues.reduce(0, +) / Double(sleepValues.count)
        guard mean > 0 else { return nil }
        let variance = sleepValues.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sleepValues.count)
        let sd = variance.squareRoot()
        let cv = sd / mean

        // Compare CV against a threshold that adapts to personal sleep
        // amplitude: someone whose baseline sleep std is already 1.5h needs a
        // larger current CV to count as "disrupted".
        let baselineSD = baselines.baseline(for: .sleepHours)?.stdDev ?? 0
        let elevatedFactor = baselineSD > 0 ? sd / max(baselineSD, 0.5) : 1.0

        guard cv >= 0.28 || elevatedFactor >= 1.6 else { return nil }

        let severity: EpisodeRiskSignal.Severity
        if cv >= 0.40 || elevatedFactor >= 2.2 {
            severity = .active
        } else if cv >= 0.33 || elevatedFactor >= 1.9 {
            severity = .emerging
        } else {
            severity = .early
        }

        var evidence: [String] = []
        evidence.append(String(format: "Variação de sono: %.1fh em %.1fh de média (CV %.0f%%).", sd, mean, cv * 100))
        if elevatedFactor >= 1.6 {
            evidence.append(String(format: "%.1fx acima da sua amplitude habitual.", elevatedFactor))
        }

        return EpisodeRiskSignal(
            kind: .circadian,
            severity: severity,
            evidence: evidence,
            recommendation: "Rotina de horário fixo pra dormir/acordar + luz natural pela manhã ajuda a reancorar o ritmo.",
            windowDays: window.count
        )
    }

    // MARK: - Per-metric flags (raw + z-score with baseline fallback)

    /// Sleep reduction: <5h raw OR z ≤ -1.5 vs. personal baseline.
    private static func isSleepReduced(_ ci: DailyCheckIn, baseline: PersonalBaseline?) -> Bool {
        if ci.sleepHours < 5 { return true }
        guard let b = baseline else { return false }
        let z = (ci.sleepHours - b.center) / max(b.stdDev, 0.5)
        return z <= -1.5
    }

    /// "Activation" — any of energy/mood/irritability elevated over baseline
    /// or hard raw threshold. Mania prodrome definition.
    private static func isActivationHigh(_ ci: DailyCheckIn, baselines: PersonalBaselineEngine.Summary) -> Bool {
        let energyHigh: Bool = {
            if let b = baselines.baseline(for: .energy) {
                return (ci.energy - b.center) / max(b.stdDev, 0.5) >= 1.5
            }
            return ci.energy >= 4.5
        }()
        let moodElevated: Bool = {
            if let b = baselines.baseline(for: .mood) {
                return (ci.mood - b.center) / max(b.stdDev, 0.5) >= 1.5
            }
            return ci.mood >= 4.5
        }()
        let irritabilityHigh: Bool = {
            if let b = baselines.baseline(for: .irritability) {
                return (ci.irritability - b.center) / max(b.stdDev, 0.5) >= 1.5
            }
            return ci.irritability >= 4
        }()
        return energyHigh || moodElevated || irritabilityHigh
    }

    private static func isMoodLow(_ ci: DailyCheckIn, baseline: PersonalBaseline?) -> Bool {
        if ci.mood <= 2 { return true }
        guard let b = baseline else { return false }
        return (ci.mood - b.center) / max(b.stdDev, 0.5) <= -1.5
    }

    private static func isEnergyLow(_ ci: DailyCheckIn, baseline: PersonalBaseline?) -> Bool {
        if ci.energy <= 2 { return true }
        guard let b = baseline else { return false }
        return (ci.energy - b.center) / max(b.stdDev, 0.5) <= -1.0
    }

    private static func isAnxietyHigh(_ ci: DailyCheckIn, baseline: PersonalBaseline?) -> Bool {
        if ci.anxiety >= 4 { return true }
        guard let b = baseline else { return false }
        return (ci.anxiety - b.center) / max(b.stdDev, 0.5) >= 1.5
    }

    private static func severityRank(_ s: EpisodeRiskSignal.Severity) -> Int {
        switch s {
        case .active: 3
        case .emerging: 2
        case .early: 1
        }
    }
}

// MARK: - Episode prediction (k-NN over the patient's own history)

/// Predictive layer: instead of describing what already happened, projects the
/// next 7 days and — if the patient has prior episodes on file — surfaces the
/// closest historical antecedent-window analogue ("this looks like the 14
/// days before your February relapse").
///
/// Design notes: this is deliberately *not* an LSTM/Transformer. Those would
/// require a multi-patient training set, offline training pipeline and model
/// hosting. Here we use k-nearest-neighbours over the individual's own
/// longitudinal trajectory + linear slope extrapolation — same UX contract,
/// interpretable, on-device.
struct EpisodePrediction {
    enum State {
        case warmingUp(daysUntilReady: Int)
        case noPastEpisodes         // enough history, no past episodes to match
        case ready                  // has past episodes, produced a prediction
    }

    struct HistoricalMatch: Identifiable, Hashable {
        let id = UUID()
        let kind: EpisodeRiskSignal.Kind
        let episodeStart: Date
        /// Human label like "fevereiro de 2026".
        let episodeLabel: String
        /// Similarity of current 14-day window to the antecedent window that
        /// preceded this past episode. 0-100.
        let similarityPercent: Int
        /// How many days before the past episode start the antecedent window ended.
        let daysBeforeEpisode: Int
    }

    struct MetricForecast: Identifiable, Hashable {
        enum Direction { case worsening, improving, stable }
        let id = UUID()
        let metric: PersonalBaseline.Metric
        /// Recent-window mean of the metric (what the person is "at" now).
        let currentValue: Double
        /// Projected mean 7 days ahead if the current 14-day slope persists.
        let projected7d: Double
        /// R² of the slope fit (0-1). Low R² = noisy trajectory, weak forecast.
        let fitQuality: Double
        let direction: Direction
    }

    enum RiskBand: String {
        case low, moderate, high

        var label: String {
            switch self {
            case .low: "Baixo"
            case .moderate: "Moderado"
            case .high: "Alto"
            }
        }
    }

    let state: State
    /// Estimated probability of clinically meaningful worsening in the next 7
    /// days, on [0, 1]. Nil when state != .ready.
    let probabilityWorsening7d: Double?
    /// Bucketed risk band derived from `probabilityWorsening7d`.
    let riskBand: RiskBand?
    /// Best-matching historical antecedent window (may be nil even in .ready).
    let bestMatch: HistoricalMatch?
    /// 7-day forecast per key metric.
    let forecasts: [MetricForecast]
}

enum EpisodePredictionEngine {
    /// How many days of history are required before we run any prediction.
    private static let minHistoryDays = 30
    /// The rolling window used to build a feature vector for a point in time.
    private static let windowDays = 14
    /// Similarity threshold below which we treat a match as noise.
    private static let matchThreshold = 0.55

    static func compute(from checkIns: [DailyCheckIn], now: Date = Date()) -> EpisodePrediction {
        let cal = Calendar(identifier: .iso8601)
        let today = cal.startOfDay(for: now)
        let sorted = checkIns.sorted { $0.date < $1.date }

        guard let oldest = sorted.first?.date else {
            return EpisodePrediction(
                state: .warmingUp(daysUntilReady: minHistoryDays),
                probabilityWorsening7d: nil, riskBand: nil, bestMatch: nil, forecasts: []
            )
        }
        let daysOfHistory = cal.dateComponents([.day], from: cal.startOfDay(for: oldest), to: today).day ?? 0
        if daysOfHistory < minHistoryDays || sorted.count < minHistoryDays / 2 {
            return EpisodePrediction(
                state: .warmingUp(daysUntilReady: max(0, minHistoryDays - daysOfHistory)),
                probabilityWorsening7d: nil, riskBand: nil, bestMatch: nil, forecasts: []
            )
        }

        // 1) Forecast is always safe to compute — pure linear extrapolation of
        //    the last 14 days.
        let recent = recentWindow(sorted, endingAt: today, days: windowDays)
        let forecasts = buildForecasts(from: recent)

        // 2) Identify past episodes and their antecedent windows.
        let baselines = PersonalBaselineEngine.compute(from: sorted, now: now)
        let pastEpisodes = identifyPastEpisodes(from: sorted, baselines: baselines, referenceDay: today, cal: cal)

        // 3) If no past episodes yet, degrade gracefully — still show forecast.
        guard !pastEpisodes.isEmpty else {
            let probability = probabilityFromForecast(forecasts)
            return EpisodePrediction(
                state: .noPastEpisodes,
                probabilityWorsening7d: probability,
                riskBand: band(for: probability),
                bestMatch: nil,
                forecasts: forecasts
            )
        }

        // 4) k-NN: extract current feature vector, compare against each
        //    antecedent vector, keep the strongest match.
        let currentVector = features(over: recent)
        var scored: [(episode: PastEpisode, similarity: Double)] = []
        for episode in pastEpisodes {
            let antecedent = antecedentWindow(before: episode.start, in: sorted, days: windowDays, cal: cal)
            guard antecedent.count >= 3 else { continue }
            let vec = features(over: antecedent)
            let sim = similarity(currentVector, vec)
            scored.append((episode, sim))
        }
        scored.sort { $0.similarity > $1.similarity }

        let bestMatch: EpisodePrediction.HistoricalMatch?
        if let top = scored.first, top.similarity >= matchThreshold {
            let matchedAntecedent = antecedentWindow(before: top.episode.start, in: sorted, days: windowDays, cal: cal)
            let antecedentEnd = matchedAntecedent.last?.date ?? top.episode.start
            let daysBefore = cal.dateComponents(
                [.day],
                from: cal.startOfDay(for: antecedentEnd),
                to: cal.startOfDay(for: top.episode.start)
            ).day ?? windowDays
            bestMatch = EpisodePrediction.HistoricalMatch(
                kind: top.episode.kind,
                episodeStart: top.episode.start,
                episodeLabel: monthYearLabel(from: top.episode.start),
                similarityPercent: Int((top.similarity * 100).rounded()),
                daysBeforeEpisode: max(1, daysBefore)
            )
        } else {
            bestMatch = nil
        }

        // 5) Compose probability: mix top-k similarity with forecast slope.
        //    Weight matches by similarity so a single close analogue dominates
        //    a bunch of weak ones — same idea as soft k-NN.
        let topK = Array(scored.prefix(3))
        let matchProbability: Double
        if topK.isEmpty {
            matchProbability = 0
        } else {
            let totalWeight = topK.reduce(0.0) { $0 + max(0, $1.similarity - matchThreshold) }
            if totalWeight <= 0 {
                matchProbability = 0
            } else {
                // Each match contributes a probability = similarity itself,
                // weighted by its excess-over-threshold. This maps sim=0.55
                // → 0 contribution, sim=1.0 → full contribution.
                let weightedSum = topK.reduce(0.0) { acc, item in
                    acc + max(0, item.similarity - matchThreshold) * item.similarity
                }
                matchProbability = weightedSum / totalWeight
            }
        }

        // Blend: 65% historical match, 35% forecast direction. This is
        // deliberate — priors from past episodes are stronger evidence than a
        // 14-day linear fit, but the forecast still nudges the score up when
        // slopes are already turning even without a strong analogue.
        let forecastComponent = probabilityFromForecast(forecasts)
        let blended = 0.65 * matchProbability + 0.35 * forecastComponent
        let probability = min(max(blended, 0.05), 0.92)

        return EpisodePrediction(
            state: .ready,
            probabilityWorsening7d: probability,
            riskBand: band(for: probability),
            bestMatch: bestMatch,
            forecasts: forecasts
        )
    }

    // MARK: - Past-episode identification

    private struct PastEpisode {
        let kind: EpisodeRiskSignal.Kind
        let start: Date          // day the episode began
        let length: Int          // consecutive active days
    }

    /// Walks through history day-by-day and flags days that individually meet
    /// per-kind criteria. Groups consecutive same-kind days into episodes.
    private static func identifyPastEpisodes(
        from sorted: [DailyCheckIn],
        baselines: PersonalBaselineEngine.Summary,
        referenceDay: Date,
        cal: Calendar
    ) -> [PastEpisode] {
        guard !sorted.isEmpty else { return [] }
        // Exclude the current 7 days — those belong to the "now" window we're
        // predicting against, not to historical ground truth.
        guard let cutoff = cal.date(byAdding: .day, value: -7, to: referenceDay) else { return [] }
        let history = sorted.filter { $0.date < cutoff }

        // Per-day flags per kind. A day can flag multiple kinds simultaneously.
        struct Flags {
            var manic = false
            var depressive = false
            var anxious = false
            var suicidal = false
        }
        let flagged: [(DailyCheckIn, Flags)] = history.map { ci in
            var f = Flags()
            let sleepLow = ci.sleepHours < 5 || zScore(ci.sleepHours, baseline: baselines.baseline(for: .sleepHours)) <= -1.5
            let energyHigh = ci.energy >= 4.5 || zScore(ci.energy, baseline: baselines.baseline(for: .energy)) >= 1.5
            let irritHigh = ci.irritability >= 4 || zScore(ci.irritability, baseline: baselines.baseline(for: .irritability)) >= 1.5
            let moodHigh = ci.mood >= 4.5 || zScore(ci.mood, baseline: baselines.baseline(for: .mood)) >= 1.5
            let moodLow = ci.mood <= 2 || zScore(ci.mood, baseline: baselines.baseline(for: .mood)) <= -1.5
            let energyLow = ci.energy <= 2 || zScore(ci.energy, baseline: baselines.baseline(for: .energy)) <= -1.0
            let anxietyHigh = ci.anxiety >= 4 || zScore(ci.anxiety, baseline: baselines.baseline(for: .anxiety)) >= 1.5

            f.manic = sleepLow && (energyHigh || irritHigh || moodHigh)
            f.depressive = moodLow && energyLow
            f.anxious = anxietyHigh
            f.suicidal = ci.suicidalIdeation
            return (ci, f)
        }

        // Group consecutive flagged days per kind.
        var episodes: [PastEpisode] = []
        for kind in [EpisodeRiskSignal.Kind.mania, .depression, .anxiety, .suicide] {
            let predicate: (Flags) -> Bool = { flags in
                switch kind {
                case .mania: flags.manic
                case .depression: flags.depressive
                case .anxiety: flags.anxious
                case .suicide: flags.suicidal
                default: false
                }
            }
            let minRunLength: Int = (kind == .suicide) ? 1 : 3
            var run: [(DailyCheckIn, Flags)] = []
            for entry in flagged {
                if predicate(entry.1) {
                    run.append(entry)
                } else if !run.isEmpty {
                    if run.count >= minRunLength, let start = run.first?.0.date {
                        episodes.append(PastEpisode(kind: kind, start: start, length: run.count))
                    }
                    run.removeAll()
                }
            }
            if run.count >= minRunLength, let start = run.first?.0.date {
                episodes.append(PastEpisode(kind: kind, start: start, length: run.count))
            }
        }
        return episodes
    }

    // MARK: - Feature vectors & similarity

    /// Compact per-window feature vector used to compare trajectories.
    private struct FeatureVector {
        let meanMood, slopeMood: Double
        let meanAnxiety, slopeAnxiety: Double
        let meanSleep, slopeSleep, cvSleep: Double
        let meanEnergy, slopeEnergy: Double
        let meanIrritability: Double
        let adherence: Double
        let anySuicidal: Double     // 0 or 1
    }

    private static func features(over records: [DailyCheckIn]) -> FeatureVector {
        let cal = Calendar(identifier: .iso8601)
        let mood = records.map(\.mood)
        let anxiety = records.map(\.anxiety)
        let sleep = records.map(\.sleepHours)
        let energy = records.map(\.energy)
        let irritability = records.map(\.irritability)

        let meanMood = mean(mood)
        let meanSleep = mean(sleep)
        let sleepSD = stdDev(sleep, mean: meanSleep)

        return FeatureVector(
            meanMood: meanMood,
            slopeMood: slope(records, cal: cal) { $0.mood },
            meanAnxiety: mean(anxiety),
            slopeAnxiety: slope(records, cal: cal) { $0.anxiety },
            meanSleep: meanSleep,
            slopeSleep: slope(records, cal: cal) { $0.sleepHours },
            cvSleep: meanSleep > 0 ? sleepSD / meanSleep : 0,
            meanEnergy: mean(energy),
            slopeEnergy: slope(records, cal: cal) { $0.energy },
            meanIrritability: mean(irritability),
            adherence: records.isEmpty ? 1.0 : Double(records.filter(\.medicationTaken).count) / Double(records.count),
            anySuicidal: records.contains(where: \.suicidalIdeation) ? 1.0 : 0.0
        )
    }

    /// Normalizes each feature to a [0,1]-ish scale, applies per-feature weights,
    /// computes Euclidean distance, converts to similarity.
    private static func similarity(_ a: FeatureVector, _ b: FeatureVector) -> Double {
        struct Dim {
            let a: Double
            let b: Double
            let scale: Double
            let weight: Double
        }
        // scale = expected value spread; weight = clinical importance.
        let dims: [Dim] = [
            .init(a: a.meanMood, b: b.meanMood, scale: 5, weight: 2.0),
            .init(a: a.slopeMood, b: b.slopeMood, scale: 0.5, weight: 1.5),
            .init(a: a.meanAnxiety, b: b.meanAnxiety, scale: 5, weight: 2.0),
            .init(a: a.slopeAnxiety, b: b.slopeAnxiety, scale: 0.5, weight: 1.5),
            .init(a: a.meanSleep, b: b.meanSleep, scale: 12, weight: 2.0),
            .init(a: a.slopeSleep, b: b.slopeSleep, scale: 1.0, weight: 1.5),
            .init(a: a.cvSleep, b: b.cvSleep, scale: 0.5, weight: 1.0),
            .init(a: a.meanEnergy, b: b.meanEnergy, scale: 5, weight: 1.2),
            .init(a: a.slopeEnergy, b: b.slopeEnergy, scale: 0.5, weight: 1.0),
            .init(a: a.meanIrritability, b: b.meanIrritability, scale: 5, weight: 1.0),
            .init(a: a.adherence, b: b.adherence, scale: 1, weight: 1.2),
            .init(a: a.anySuicidal, b: b.anySuicidal, scale: 1, weight: 2.5),
        ]
        var num = 0.0
        var totalWeight = 0.0
        for dim in dims {
            let diff = (dim.a - dim.b) / max(dim.scale, 0.001)
            num += dim.weight * diff * diff
            totalWeight += dim.weight
        }
        let rms = (num / totalWeight).squareRoot()
        // Map RMS→similarity via 1/(1+d). rms=0 → 1.0; rms=1 → 0.5; rms=2 → 0.33.
        return 1.0 / (1.0 + rms)
    }

    // MARK: - Forecast

    private static func buildForecasts(from recent: [DailyCheckIn]) -> [EpisodePrediction.MetricForecast] {
        guard recent.count >= 4 else { return [] }
        let cal = Calendar(identifier: .iso8601)
        let metrics: [(PersonalBaseline.Metric, (DailyCheckIn) -> Double)] = [
            (.mood, { $0.mood }),
            (.anxiety, { $0.anxiety }),
            (.sleepHours, { $0.sleepHours }),
            (.energy, { $0.energy }),
        ]
        return metrics.map { metric, extract in
            let values = recent.map(extract)
            let slopePerDay = slope(recent, cal: cal, value: extract)
            let currentMean = mean(values)
            let projected = currentMean + slopePerDay * 7.0
            let rSquared = coefficientOfDetermination(recent, cal: cal, value: extract)
            let direction: EpisodePrediction.MetricForecast.Direction = {
                let worseningIsUp = metric.higherIsWorse
                let signedDrift = worseningIsUp ? slopePerDay : -slopePerDay
                if signedDrift > 0.03 { return .worsening }
                if signedDrift < -0.03 { return .improving }
                return .stable
            }()
            return EpisodePrediction.MetricForecast(
                metric: metric,
                currentValue: currentMean,
                projected7d: projected,
                fitQuality: rSquared,
                direction: direction
            )
        }
    }

    /// Turn the forecast trajectory into a coarse probability of worsening,
    /// used when we have no historical match to rely on.
    private static func probabilityFromForecast(_ forecasts: [EpisodePrediction.MetricForecast]) -> Double {
        guard !forecasts.isEmpty else { return 0.15 }
        // Each worsening metric adds up to 0.20; stable adds 0.05; improving is 0.
        // R² gates the contribution — noisy fits shouldn't inflate probability.
        var p = 0.10
        for f in forecasts {
            let contribution: Double
            switch f.direction {
            case .worsening: contribution = 0.20 * f.fitQuality
            case .stable: contribution = 0.03
            case .improving: contribution = 0.0
            }
            p += contribution
        }
        return min(0.75, p)
    }

    // MARK: - Helpers

    private static func recentWindow(_ sorted: [DailyCheckIn], endingAt end: Date, days: Int) -> [DailyCheckIn] {
        let cal = Calendar(identifier: .iso8601)
        guard let start = cal.date(byAdding: .day, value: -days, to: end) else { return [] }
        return sorted.filter { $0.date >= start && $0.date <= end }
    }

    private static func antecedentWindow(before episodeStart: Date, in sorted: [DailyCheckIn], days: Int, cal: Calendar) -> [DailyCheckIn] {
        guard
            let end = cal.date(byAdding: .day, value: -1, to: episodeStart),
            let start = cal.date(byAdding: .day, value: -days, to: end)
        else { return [] }
        return sorted.filter { $0.date >= start && $0.date <= end }
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func stdDev(_ values: [Double], mean m: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    private static func slope(_ records: [DailyCheckIn], cal: Calendar, value: (DailyCheckIn) -> Double) -> Double {
        guard records.count >= 3, let anchor = records.first?.date else { return 0 }
        let anchorDay = cal.startOfDay(for: anchor)
        var xs: [Double] = []
        var ys: [Double] = []
        for r in records {
            let d = cal.dateComponents([.day], from: anchorDay, to: cal.startOfDay(for: r.date)).day ?? 0
            xs.append(Double(d))
            ys.append(value(r))
        }
        let xm = mean(xs)
        let ym = mean(ys)
        var num = 0.0, den = 0.0
        for i in xs.indices {
            let dx = xs[i] - xm
            num += dx * (ys[i] - ym)
            den += dx * dx
        }
        return den == 0 ? 0 : num / den
    }

    /// R² for a linear fit — used as forecast confidence.
    private static func coefficientOfDetermination(_ records: [DailyCheckIn], cal: Calendar, value: (DailyCheckIn) -> Double) -> Double {
        guard records.count >= 3, let anchor = records.first?.date else { return 0 }
        let anchorDay = cal.startOfDay(for: anchor)
        var xs: [Double] = []
        var ys: [Double] = []
        for r in records {
            let d = cal.dateComponents([.day], from: anchorDay, to: cal.startOfDay(for: r.date)).day ?? 0
            xs.append(Double(d))
            ys.append(value(r))
        }
        let xm = mean(xs)
        let ym = mean(ys)
        var num = 0.0, denX = 0.0, denY = 0.0
        for i in xs.indices {
            let dx = xs[i] - xm
            let dy = ys[i] - ym
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0, denY > 0 else { return 0 }
        let r = num / (denX.squareRoot() * denY.squareRoot())
        return r * r
    }

    private static func zScore(_ value: Double, baseline: PersonalBaseline?) -> Double {
        guard let b = baseline else { return 0 }
        return (value - b.center) / max(b.stdDev, 0.5)
    }

    private static func band(for probability: Double?) -> EpisodePrediction.RiskBand? {
        guard let p = probability else { return nil }
        if p >= 0.60 { return .high }
        if p >= 0.35 { return .moderate }
        return .low
    }

    private static func monthYearLabel(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "MMMM 'de' yyyy"
        return f.string(from: date).capitalized
    }
}

// MARK: - Daily coach

struct DailyCoachInsight {
    enum Band {
        case ready, strained, lowRecovery

        var label: String {
            switch self {
            case .ready: "Pronto"
            case .strained: "Atenção"
            case .lowRecovery: "Recovery baixo"
            }
        }
    }

    struct Driver: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let text: String
        let impact: Int
    }

    struct Action: Identifiable, Hashable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
        let priority: Int
    }

    struct Reliability: Hashable {
        let score: Int
        let level: String
        let passiveQuality: Int
        let checkInCoverage: Int
        let biometricRecencyHours: Int?
        let explanation: String
    }

    let recoveryScore: Int
    let band: Band
    let headline: String
    let recommendation: String
    let actions: [Action]
    let drivers: [Driver]
    let hrvDeltaPercent: Int?
    let weeklyTrendDelta: Int
    let reliability: Reliability

    var neuremiaScore: Int { recoveryScore }
}

struct DailyRetentionNarrative: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let body: String
    let tintName: String
    let priority: Int
}

struct PersonalRetentionPattern: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let evidence: String
    let tintName: String
    let priority: Int
}

struct PersonalInterventionLearning: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let evidence: String
    let tintName: String
    let priority: Int
}

struct PersonalRetentionProfile: Hashable {
    let learningScore: Int
    let stageTitle: String
    let stageDetail: String
    let vulnerabilityScore: Int
    let vulnerabilityLevel: ClinicalRiskLevel
    let predictionWindow: String
    let nextBestAction: String
    let nextBestActionReason: String
    let dataCoverageText: String
    let patterns: [PersonalRetentionPattern]
    let interventionLearnings: [PersonalInterventionLearning]

    var isWarmingUp: Bool { learningScore < 35 }
}

enum PersonalRetentionModelEngine {
    static func compute(
        checkIns: [DailyCheckIn],
        recommendationLogs: [DailyRecommendationLog],
        temporalPrediction: TemporalRiskPrediction,
        currentRecommendation: ClinicalDailyRecommendation,
        now: Date = Date()
    ) -> PersonalRetentionProfile {
        let sortedCheckIns = checkIns.sorted { $0.date > $1.date }
        let causalInsights = CausalInsightsEngine.compute(from: sortedCheckIns)
        let patterns = retentionPatterns(from: causalInsights, checkIns: sortedCheckIns, now: now)
        let interventionLearnings = interventionLearnings(from: recommendationLogs)
        let measuredImpactCount = recommendationLogs.filter { $0.completed && $0.impactSummary != nil }.count
        let completionCount = recommendationLogs.filter(\.completed).count
        let exposureCount = max(recommendationLogs.count, completionCount)
        let completionRate = exposureCount > 0 ? Double(completionCount) / Double(exposureCount) : 0
        let learningScore = min(
            100,
            sortedCheckIns.count * 4
                + measuredImpactCount * 12
                + patterns.count * 10
                + interventionLearnings.count * 12
                + Int((completionRate * 15).rounded())
        )
        let vulnerabilityScore = vulnerabilityScore(
            checkIns: sortedCheckIns,
            temporalPrediction: temporalPrediction
        )
        let vulnerabilityLevel = riskLevel(for: vulnerabilityScore)
        let stage = learningStage(
            score: learningScore,
            checkInCount: sortedCheckIns.count,
            measuredImpactCount: measuredImpactCount,
            patternCount: patterns.count
        )
        let action = nextBestAction(
            recommendation: currentRecommendation,
            interventionLearnings: interventionLearnings,
            patterns: patterns,
            temporalPrediction: temporalPrediction,
            vulnerabilityLevel: vulnerabilityLevel
        )

        return PersonalRetentionProfile(
            learningScore: learningScore,
            stageTitle: stage.title,
            stageDetail: stage.detail,
            vulnerabilityScore: vulnerabilityScore,
            vulnerabilityLevel: vulnerabilityLevel,
            predictionWindow: temporalPrediction.primaryWindow,
            nextBestAction: action.title,
            nextBestActionReason: action.reason,
            dataCoverageText: coverageText(
                checkInCount: sortedCheckIns.count,
                measuredImpactCount: measuredImpactCount,
                patternCount: patterns.count
            ),
            patterns: patterns,
            interventionLearnings: interventionLearnings
        )
    }

    private static func retentionPatterns(
        from insights: [CausalInsight],
        checkIns: [DailyCheckIn],
        now: Date
    ) -> [PersonalRetentionPattern] {
        var patterns = insights.prefix(3).map { insight in
            PersonalRetentionPattern(
                id: "causal-\(insight.signalKey)",
                icon: insight.icon,
                title: insight.antecedent,
                detail: "\(insight.consequent) \(formattedDelta(insight.deltaPercent)).",
                evidence: "\(insight.confidence.label) com \(insight.sampleSize) ocorrências.",
                tintName: insight.tintName,
                priority: insight.confidence == .high ? 95 : insight.confidence == .moderate ? 80 : 65
            )
        }

        if let recurrence = recurringVulnerabilityPattern(checkIns: checkIns, now: now) {
            patterns.append(recurrence)
        }

        return Array(patterns.sorted { $0.priority > $1.priority }.prefix(4))
    }

    private static func recurringVulnerabilityPattern(checkIns: [DailyCheckIn], now: Date) -> PersonalRetentionPattern? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let recent = checkIns.filter { $0.date >= cutoff }
        let vulnerableDays = recent.filter { $0.sleepHours < 6 || $0.mood <= 2 || $0.anxiety >= 4 }
        guard vulnerableDays.count >= 3 else { return nil }

        let lowSleepCount = vulnerableDays.filter { $0.sleepHours < 6 }.count
        let highAnxietyCount = vulnerableDays.filter { $0.anxiety >= 4 }.count
        let lowMoodCount = vulnerableDays.filter { $0.mood <= 2 }.count
        let dominant: (title: String, icon: String, tint: String)
        if lowSleepCount >= highAnxietyCount && lowSleepCount >= lowMoodCount {
            dominant = ("Sono curto costuma abrir seus dias vulneráveis", "moon.zzz.fill", "indigo")
        } else if highAnxietyCount >= lowMoodCount {
            dominant = ("Ansiedade alta aparece antes de dias frágeis", "waveform.path.ecg", "orange")
        } else {
            dominant = ("Humor baixo vem se repetindo no ciclo recente", "face.dashed", "purple")
        }

        return PersonalRetentionPattern(
            id: "recent-vulnerability-recurrence",
            icon: dominant.icon,
            title: dominant.title,
            detail: "O app encontrou \(vulnerableDays.count) dias parecidos nos últimos 14 dias.",
            evidence: "Usado para ajustar a recomendação de hoje e a janela de previsão.",
            tintName: dominant.tint,
            priority: 88
        )
    }

    private static func interventionLearnings(from logs: [DailyRecommendationLog]) -> [PersonalInterventionLearning] {
        let targetSignals = Array(Set(logs.map(\.targetSignal))).sorted()
        return targetSignals.compactMap { signal in
            guard let profile = AdaptiveRecommendationEngine.profile(for: signal, logs: logs), profile.hasEnoughData else {
                return nil
            }

            let rate = Int((profile.responseRate * 100).rounded())
            let average = String(format: "%.1f", profile.averageNetImpact)
            if profile.isHelpful {
                return PersonalInterventionLearning(
                    id: "helpful-\(signal)",
                    icon: "checkmark.seal.fill",
                    title: label(for: signal),
                    detail: "Costuma ajudar seus sinais após ser concluída.",
                    evidence: "\(rate)% de resposta positiva em \(profile.sampleCount) impactos medidos; efeito médio \(average).",
                    tintName: "green",
                    priority: 95
                )
            }

            if profile.isHarmful {
                return PersonalInterventionLearning(
                    id: "sensitive-\(signal)",
                    icon: "exclamationmark.triangle.fill",
                    title: label(for: signal),
                    detail: "Precisa de dose menor ou alternativa para você.",
                    evidence: "\(profile.sampleCount) impactos medidos; efeito médio \(average).",
                    tintName: "orange",
                    priority: 90
                )
            }

            return PersonalInterventionLearning(
                id: "neutral-\(signal)",
                icon: "target",
                title: label(for: signal),
                detail: "Resposta ainda variável; o app torna a ação mais específica.",
                evidence: "\(profile.sampleCount) impactos medidos; \(rate)% positivos.",
                tintName: "blue",
                priority: 70
            )
        }
        .sorted { $0.priority > $1.priority }
    }

    private static func vulnerabilityScore(
        checkIns: [DailyCheckIn],
        temporalPrediction: TemporalRiskPrediction
    ) -> Int {
        let recent = Array(checkIns.prefix(7))
        let recentPenalty: Int
        if recent.isEmpty {
            recentPenalty = 0
        } else {
            let lowSleep = recent.filter { $0.sleepHours < 6 }.count
            let lowMood = recent.filter { $0.mood <= 2 }.count
            let highAnxiety = recent.filter { $0.anxiety >= 4 }.count
            let missedMedication = recent.filter { !$0.medicationTaken }.count
            recentPenalty = min(24, lowSleep * 4 + lowMood * 4 + highAnxiety * 4 + missedMedication * 3)
        }

        return min(100, max(0, temporalPrediction.primaryScore + recentPenalty))
    }

    private static func riskLevel(for score: Int) -> ClinicalRiskLevel {
        if score >= 66 { return .high }
        if score >= 34 { return .moderate }
        return .low
    }

    private static func learningStage(
        score: Int,
        checkInCount: Int,
        measuredImpactCount: Int,
        patternCount: Int
    ) -> (title: String, detail: String) {
        if score >= 75 {
            return (
                "Conhecimento pessoal forte",
                "Já combino histórico, padrões e resposta a intervenções para personalizar o próximo passo."
            )
        }
        if score >= 45 {
            return (
                "Aprendizado em progresso",
                "Já reconheço alguns padrões seus e começo a ajustar recomendações pelo impacto real."
            )
        }
        if checkInCount >= 3 {
            return (
                "Modelo aquecendo",
                "Tenho \(checkInCount) registros. Mais alguns dias ajudam a separar padrão real de ruído."
            )
        }
        return (
            "Primeira linha de base",
            "Os primeiros registros criam a referência pessoal para o app deixar de ser genérico."
        )
    }

    private static func nextBestAction(
        recommendation: ClinicalDailyRecommendation,
        interventionLearnings: [PersonalInterventionLearning],
        patterns: [PersonalRetentionPattern],
        temporalPrediction: TemporalRiskPrediction,
        vulnerabilityLevel: ClinicalRiskLevel
    ) -> (title: String, reason: String) {
        if let helpful = interventionLearnings.first(where: { $0.id.hasPrefix("helpful-\(recommendation.targetSignal)") }) {
            return (
                recommendation.action,
                "\(helpful.title) já mostrou resposta positiva para você; por isso a recomendação mantém essa linha."
            )
        }

        if let sensitive = interventionLearnings.first(where: { $0.id.hasPrefix("sensitive-\(recommendation.targetSignal)") }) {
            return (
                "Faça uma versão menor: \(recommendation.action)",
                "\(sensitive.title) teve resposta pior em medidas anteriores; a carga foi reduzida."
            )
        }

        if vulnerabilityLevel == .high {
            return (
                recommendation.action,
                "A previsão \(temporalPrediction.primaryWindow) está alta, então a prioridade é reduzir vulnerabilidade hoje."
            )
        }

        if let pattern = patterns.first {
            return (
                recommendation.action,
                "A recomendação conversa com o padrão detectado: \(pattern.title.lowercased())."
            )
        }

        return (
            recommendation.action,
            "Ainda estou montando sua linha de base; concluir a ação ajuda a medir resposta individual."
        )
    }

    private static func coverageText(checkInCount: Int, measuredImpactCount: Int, patternCount: Int) -> String {
        "\(checkInCount) check-ins, \(measuredImpactCount) impactos medidos, \(patternCount) padrões pessoais ativos."
    }

    private static func formattedDelta(_ delta: Double) -> String {
        let absolute = Int(abs(delta).rounded())
        return delta >= 0 ? "+\(absolute)%" : "-\(absolute)%"
    }

    private static func label(for targetSignal: String) -> String {
        switch targetSignal {
        case "light-exercise-anxiety":
            return "Caminhada curta"
        case "light-exercise-mood":
            return "Movimento leve"
        case "sleep-debt-anxiety", "sleep-debt-mood", "high-anxiety-sleep", "short-sleep-energy", ClinicalEpisodeKind.circadianShift.rawValue:
            return "Sono protegido"
        case "missed-medication-mood", "missed-medication-anxiety", "two-day-medication-gap-anxiety", ClinicalEpisodeKind.lowAdherence.rawValue:
            return "Adesão à medicação"
        case ClinicalEpisodeKind.depressiveRelapse.rawValue:
            return "Ativação mínima"
        case ClinicalEpisodeKind.anxietyCrisis.rawValue:
            return "Redução de ativação"
        default:
            return targetSignal
        }
    }
}

enum DailyRetentionNarrativeEngine {
    static func compute(
        checkIns: [DailyCheckIn],
        currentSleepHours: Double,
        currentHRV: Double,
        hrvBaseline: Double,
        ppgStress: Double,
        ppgQuality: Double,
        mood: Double,
        anxiety: Double,
        recommendation: ClinicalDailyRecommendation? = nil,
        responseProfile: RecommendationResponseProfile? = nil,
        now: Date = Date()
    ) -> [DailyRetentionNarrative] {
        let effectiveSleep = currentSleepHours > 0
            ? currentSleepHours
            : checkIns.sorted { $0.date > $1.date }.first?.sleepHours ?? 0
        let hrvDelta = currentHRV > 0 && hrvBaseline > 0 && ppgQuality >= 0.45
            ? ((currentHRV - hrvBaseline) / max(hrvBaseline, 1)) * 100
            : nil
        var narratives: [DailyRetentionNarrative] = []

        if effectiveSleep > 0, effectiveSleep < 6, let hrvDelta, hrvDelta <= -8 {
            narratives.append(.init(
                id: "sleep-hrv-vulnerability",
                icon: "moon.zzz.fill",
                title: "Sistema mais vulnerável",
                body: "Hoje seu sistema está mais vulnerável por sono + HRV. Proteja margem: reduza carga, evite excesso de cafeína e priorize uma noite regular.",
                tintName: "red",
                priority: 100
            ))
        }

        if ppgQuality >= 0.45, ppgStress >= 65 || anxiety >= 4 {
            narratives.append(.init(
                id: "high-stress-decisions",
                icon: "exclamationmark.triangle.fill",
                title: "Decisões de alto estresse",
                body: "Evite decisões de alto estresse hoje. Se for inevitável, coloque uma pausa de 10 minutos antes de responder ou assumir compromissos.",
                tintName: "orange",
                priority: 90
            ))
        }

        let recentAlertPatternCount = recentAlertPatternCount(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: effectiveSleep,
            now: now
        )
        if recentAlertPatternCount >= 2 {
            narratives.append(.init(
                id: "recent-alert-pattern",
                icon: "arrow.triangle.branch",
                title: "Padrão recorrente",
                body: "Seu padrão de alerta apareceu \(recentAlertPatternCount) vezes nos últimos 10 dias. Hoje vale tratar o dia como preventivo, não como cobrança.",
                tintName: "purple",
                priority: 80
            ))
        }

        if let exercise = CausalInsightsEngine.compute(from: checkIns).first(where: { insight in
            insight.signalKey == "light-exercise-anxiety" && insight.direction == .decrease
        }) {
            narratives.append(.init(
                id: "walking-anxiety-response",
                icon: "figure.walk.circle.fill",
                title: "Resposta pessoal",
                body: "A caminhada curta tem melhorado sua ansiedade em 24h nos seus registros (\(Int(abs(exercise.deltaPercent).rounded()))% em média).",
                tintName: "teal",
                priority: 70
            ))
        }

        if let responseProfile, responseProfile.isHelpful {
            let rate = Int((responseProfile.responseRate * 100).rounded())
            let actionLabel = recommendation.map { recommendationActionLabel(for: $0, targetSignal: responseProfile.targetSignal) } ?? targetLabel(for: responseProfile.targetSignal)
            narratives.append(.init(
                id: "recommendation-response-helpful-\(responseProfile.targetSignal)",
                icon: "checkmark.seal.fill",
                title: "Ação que costuma funcionar",
                body: "\(actionLabel) costuma funcionar para você: ajudou em \(rate)% das \(responseProfile.sampleCount) execuções medidas.",
                tintName: "green",
                priority: 75
            ))
        } else if let responseProfile, responseProfile.isHarmful {
            let actionLabel = recommendation.map { recommendationActionLabel(for: $0, targetSignal: responseProfile.targetSignal) } ?? targetLabel(for: responseProfile.targetSignal)
            narratives.append(.init(
                id: "recommendation-response-sensitive-\(responseProfile.targetSignal)",
                icon: "exclamationmark.triangle.fill",
                title: "Ação para reduzir carga",
                body: "\(actionLabel) piorou sinais em média nas últimas \(responseProfile.sampleCount) execuções medidas. Hoje o app sugere uma versão menor.",
                tintName: "orange",
                priority: 75
            ))
        }

        return Array(narratives.sorted { $0.priority > $1.priority }.prefix(4))
    }

    private static func recommendationActionLabel(for recommendation: ClinicalDailyRecommendation, targetSignal: String) -> String {
        let action = recommendation.action.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty {
            return targetLabel(for: targetSignal)
        }

        if action.count <= 46 {
            return action
        }

        return targetLabel(for: targetSignal)
    }

    private static func targetLabel(for targetSignal: String) -> String {
        switch targetSignal {
        case "light-exercise-anxiety":
            return "Caminhada curta"
        case "light-exercise-mood":
            return "Movimento leve"
        case "sleep-debt-anxiety", "sleep-debt-mood", "high-anxiety-sleep", "short-sleep-energy":
            return "Sono protegido"
        case "missed-medication-mood", "missed-medication-anxiety", "two-day-medication-gap-anxiety":
            return "Adesão à medicação"
        default:
            return "Essa ação"
        }
    }

    private static func recentAlertPatternCount(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        now: Date
    ) -> Int {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -10, to: now) ?? .distantPast
        let currentLowSleep = sleepHours > 0 && sleepHours < 6
        return checkIns.filter { checkIn in
            guard checkIn.date >= cutoff else { return false }
            let similarSleep = currentLowSleep && checkIn.sleepHours > 0 && checkIn.sleepHours < 6
            let similarMood = mood <= 2 && checkIn.mood <= 2
            let similarAnxiety = anxiety >= 4 && checkIn.anxiety >= 4
            return checkIn.suicidalIdeation || similarSleep || similarMood || similarAnxiety
        }.count
    }
}

@MainActor
enum DailyCoachEngine {
    static func compute(
        checkIns: [DailyCheckIn],
        currentSleepHours: Double,
        currentHRV: Double,
        hrvBaseline: Double,
        ppgStress: Double,
        ppgQuality: Double,
        mood: Double,
        anxiety: Double,
        energy: Double,
        irritability: Double,
        medicationStatus: MedicationStatus,
        steps: Int,
        healthKitSnapshots: [HealthKitDailySnapshot] = [],
        lastHealthKitSyncAt: Date? = nil,
        now: Date = Date()
    ) -> DailyCoachInsight {
        let baselines = PersonalBaselineEngine.compute(from: checkIns, now: now)
        let sleepBaseline = baselines.baseline(for: .sleepHours)?.center ?? 7.0
        let effectiveSleep = currentSleepHours > 0 ? currentSleepHours : latestSleep(from: checkIns)
        let hrvIsUsable = currentHRV > 0 && hrvBaseline > 0 && ppgQuality >= 0.45
        let hrvDelta = hrvIsUsable ? ((currentHRV - hrvBaseline) / max(hrvBaseline, 1)) * 100 : nil
        let currentPassiveSnapshot = currentSnapshot(from: healthKitSnapshots, now: now)

        var score = 82.0
        var drivers: [DailyCoachInsight.Driver] = []

        if effectiveSleep > 0 {
            let sleepDebt = max(0, sleepBaseline - effectiveSleep)
            if sleepDebt >= 0.75 {
                let impact = min(Int((sleepDebt * 9).rounded()), 26)
                score -= Double(impact)
                drivers.append(.init(
                    icon: "moon.zzz.fill",
                    text: "Sono \(String(format: "%.1f", effectiveSleep))h, \(String(format: "%.1f", sleepDebt))h abaixo do seu normal.",
                    impact: impact
                ))
            } else if effectiveSleep >= sleepBaseline {
                score += 5
                drivers.append(.init(
                    icon: "moon.stars.fill",
                    text: "Sono dentro ou acima do seu baseline.",
                    impact: -5
                ))
            }
        }

        if let hrvDelta {
            if hrvDelta <= -8 {
                let impact = min(Int((abs(hrvDelta) * 0.75).rounded()), 28)
                score -= Double(impact)
                drivers.append(.init(
                    icon: "heart.text.square.fill",
                    text: "HRV \(Int(abs(hrvDelta).rounded()))% abaixo do baseline.",
                    impact: impact
                ))
            } else if hrvDelta >= 8 {
                score += 5
                drivers.append(.init(
                    icon: "heart.text.square.fill",
                    text: "HRV \(Int(hrvDelta.rounded()))% acima do baseline.",
                    impact: -5
                ))
            }
        } else if currentHRV > 0 {
            drivers.append(.init(
                icon: "heart.text.square",
                text: "HRV medida, baseline ainda em calibração.",
                impact: 0
            ))
        }

        if let currentRHR = currentPassiveSnapshot?.restingHeartRate,
           let rhrBaseline = restingHeartRateBaseline(from: healthKitSnapshots, excluding: currentPassiveSnapshot?.dayKey),
           currentRHR > rhrBaseline + 5 {
            let delta = currentRHR - rhrBaseline
            let impact = min(Int((delta * 1.2).rounded()), 16)
            score -= Double(impact)
            drivers.append(.init(
                icon: "heart.circle.fill",
                text: "FC repouso \(Int(delta.rounded())) bpm acima do seu padrão.",
                impact: impact
            ))
        }

        if let regularity = currentPassiveSnapshot?.circadianRegularityScore,
           regularity < 0.55 {
            let impact = min(Int(((0.65 - regularity) * 22).rounded()), 12)
            score -= Double(max(impact, 4))
            drivers.append(.init(
                icon: "clock.arrow.circlepath",
                text: "Ritmo de sono irregular nos últimos dias.",
                impact: max(impact, 4)
            ))
        }

        if ppgQuality >= 0.45, ppgStress >= 65 {
            let impact = min(Int(((ppgStress - 55) * 0.35).rounded()), 18)
            score -= Double(impact)
            drivers.append(.init(
                icon: "waveform.path.ecg",
                text: "Sinal autonômico elevado: stress \(Int(ppgStress.rounded()))/100.",
                impact: impact
            ))
        }

        if anxiety >= 4 {
            score -= 12
            drivers.append(.init(
                icon: "exclamationmark.bubble.fill",
                text: "Ansiedade alta no registro atual.",
                impact: 12
            ))
        }

        if mood <= 2 {
            score -= 10
            drivers.append(.init(
                icon: "cloud.rain.fill",
                text: "Humor baixo no registro atual.",
                impact: 10
            ))
        }

        if energy <= 2 {
            score -= 8
            drivers.append(.init(
                icon: "bolt.slash.fill",
                text: "Energia baixa para a carga do dia.",
                impact: 8
            ))
        } else if energy >= 4, effectiveSleep >= sleepBaseline {
            score += 3
            drivers.append(.init(
                icon: "bolt.fill",
                text: "Energia preservada com sono dentro do baseline.",
                impact: -3
            ))
        }

        if irritability >= 4 {
            score -= 9
            drivers.append(.init(
                icon: "flame.fill",
                text: "Irritabilidade alta no registro atual.",
                impact: 9
            ))
        }

        if medicationStatus != .taken {
            score -= medicationStatus == .pending ? 12 : 7
            drivers.append(.init(
                icon: "pills.circle.fill",
                text: medicationStatus == .pending ? "Medicação ainda pendente hoje." : "Medicação marcada como parcial.",
                impact: medicationStatus == .pending ? 12 : 7
            ))
        }

        let weeklyTrendDelta = scoreTrendDelta(checkIns: checkIns, now: now)
        if weeklyTrendDelta <= -8 {
            let impact = min(abs(weeklyTrendDelta), 16)
            score -= Double(impact)
            drivers.append(.init(
                icon: "chart.line.downtrend.xyaxis",
                text: "Tendência pessoal de 7 dias piorou \(abs(weeklyTrendDelta)) pontos.",
                impact: impact
            ))
        } else if weeklyTrendDelta >= 8 {
            let bonus = min(Double(weeklyTrendDelta) * 0.35, 5)
            score += bonus
            drivers.append(.init(
                icon: "chart.line.uptrend.xyaxis",
                text: "Tendência pessoal de 7 dias melhorou \(weeklyTrendDelta) pontos.",
                impact: -Int(bonus.rounded())
            ))
        }

        let preCrisisCount = recentPreCrisisPatternCount(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: effectiveSleep,
            now: now
        )
        if preCrisisCount >= 2 {
            let impact = min(preCrisisCount * 4, 14)
            score -= Double(impact)
            drivers.append(.init(
                icon: "arrow.triangle.branch",
                text: "Padrão pré-crise semelhante apareceu \(preCrisisCount) vezes nos últimos 10 dias.",
                impact: impact
            ))
        }

        if steps > 0, steps < 1500 {
            score -= 5
            drivers.append(.init(
                icon: "figure.walk",
                text: "Pouco movimento registrado até agora.",
                impact: 5
            ))
        }

        let boundedScore = Int(min(max(score.rounded(), 5), 98))
        let band: DailyCoachInsight.Band
        if boundedScore < 40 {
            band = .lowRecovery
        } else if boundedScore < 65 {
            band = .strained
        } else {
            band = .ready
        }

        let headline = headline(for: band, score: boundedScore, hrvDelta: hrvDelta, sleepHours: effectiveSleep)
        let recommendation = recommendation(
            band: band,
            sleepHours: effectiveSleep,
            hrvDelta: hrvDelta,
            ppgStress: ppgStress,
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            medicationStatus: medicationStatus,
            steps: steps
        )
        let actions = dailyActions(
            band: band,
            sleepHours: effectiveSleep,
            hrvDelta: hrvDelta,
            ppgStress: ppgStress,
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            medicationStatus: medicationStatus,
            steps: steps
        )
        let reliability = scoreReliability(
            checkIns: checkIns,
            healthKitSnapshots: healthKitSnapshots,
            currentHRV: currentHRV,
            hrvBaseline: hrvBaseline,
            ppgQuality: ppgQuality,
            lastHealthKitSyncAt: lastHealthKitSyncAt,
            now: now
        )

        return DailyCoachInsight(
            recoveryScore: boundedScore,
            band: band,
            headline: headline,
            recommendation: recommendation,
            actions: actions,
            drivers: Array(drivers.sorted { $0.impact > $1.impact }.prefix(4)),
            hrvDeltaPercent: hrvDelta.map { Int($0.rounded()) },
            weeklyTrendDelta: weeklyTrendDelta,
            reliability: reliability
        )
    }

    private static func latestSleep(from checkIns: [DailyCheckIn]) -> Double {
        checkIns.sorted { $0.date > $1.date }.first?.sleepHours ?? 0
    }

    private static func currentSnapshot(from snapshots: [HealthKitDailySnapshot], now: Date) -> HealthKitDailySnapshot? {
        let todayKey = DailyCheckIn.dayKey(for: now)
        return snapshots.first { $0.dayKey == todayKey } ?? snapshots.sorted { $0.date > $1.date }.first
    }

    private static func restingHeartRateBaseline(from snapshots: [HealthKitDailySnapshot], excluding dayKey: String?) -> Double? {
        let values = snapshots
            .filter { $0.dayKey != dayKey }
            .sorted { $0.date > $1.date }
            .prefix(7)
            .compactMap(\.restingHeartRate)
            .filter { $0 > 0 }
        guard values.count >= 3 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func scoreTrendDelta(checkIns: [DailyCheckIn], now: Date) -> Int {
        let calendar = Calendar.current
        let recentStart = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let previousStart = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast
        let recent = checkIns.filter { $0.date >= recentStart && $0.date <= now }
        let previous = checkIns.filter { $0.date >= previousStart && $0.date < recentStart }
        guard recent.count >= 2, previous.count >= 2 else { return 0 }

        let recentScore = recent.map(dailyMentalScore).reduce(0, +) / Double(recent.count)
        let previousScore = previous.map(dailyMentalScore).reduce(0, +) / Double(previous.count)
        return Int((recentScore - previousScore).rounded())
    }

    private static func dailyMentalScore(_ checkIn: DailyCheckIn) -> Double {
        var score = 82.0
        if checkIn.sleepHours > 0, checkIn.sleepHours < 6 {
            score -= min((6 - checkIn.sleepHours) * 9, 22)
        }
        score -= max(0, checkIn.anxiety - 2.5) * 7
        score -= max(0, 3 - checkIn.mood) * 7
        score -= max(0, 3 - checkIn.energy) * 5
        score -= max(0, checkIn.irritability - 3) * 5
        if !checkIn.medicationTaken { score -= 10 }
        if checkIn.suicidalIdeation { score -= 28 }
        return min(max(score, 5), 98)
    }

    private static func recentPreCrisisPatternCount(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        now: Date
    ) -> Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? .distantPast
        let currentLowSleep = sleepHours > 0 && sleepHours < 6
        return checkIns.filter { checkIn in
            guard checkIn.date >= cutoff else { return false }
            let similarSleep = currentLowSleep && checkIn.sleepHours > 0 && checkIn.sleepHours < 6
            let similarMood = mood <= 2 && checkIn.mood <= 2
            let similarAnxiety = anxiety >= 4 && checkIn.anxiety >= 4
            return checkIn.suicidalIdeation || similarSleep || similarMood || similarAnxiety
        }.count
    }

    private static func scoreReliability(
        checkIns: [DailyCheckIn],
        healthKitSnapshots: [HealthKitDailySnapshot],
        currentHRV: Double,
        hrvBaseline: Double,
        ppgQuality: Double,
        lastHealthKitSyncAt: Date?,
        now: Date
    ) -> DailyCoachInsight.Reliability {
        let recentStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let recentCheckIns = checkIns.filter { $0.date >= recentStart && $0.date <= now }.count
        let checkInCoverage = min(Int((Double(recentCheckIns) / 7.0 * 100).rounded()), 100)
        let passiveQuality = passiveBiometricQuality(healthKitSnapshots: healthKitSnapshots, currentHRV: currentHRV, hrvBaseline: hrvBaseline, ppgQuality: ppgQuality, now: now)
        let recencyHours = lastHealthKitSyncAt.map { max(0, Int(now.timeIntervalSince($0) / 3_600)) }
        let recencyScore = recencyHours.map { $0 <= 6 ? 100 : ($0 <= 24 ? 75 : 40) } ?? (passiveQuality > 0 ? 60 : 30)
        let score = min(max(Int((Double(passiveQuality) * 0.45 + Double(checkInCoverage) * 0.35 + Double(recencyScore) * 0.20).rounded()), 0), 100)
        let level = score >= 75 ? "Alta" : (score >= 50 ? "Parcial" : "Baixa")
        let syncText = recencyHours.map { "sync há \($0)h" } ?? "sync não confirmado"

        return DailyCoachInsight.Reliability(
            score: score,
            level: level,
            passiveQuality: passiveQuality,
            checkInCoverage: checkInCoverage,
            biometricRecencyHours: recencyHours,
            explanation: "Biometria \(passiveQuality)% · check-ins \(checkInCoverage)% · \(syncText)"
        )
    }

    private static func passiveBiometricQuality(
        healthKitSnapshots: [HealthKitDailySnapshot],
        currentHRV: Double,
        hrvBaseline: Double,
        ppgQuality: Double,
        now: Date
    ) -> Int {
        let todayKey = DailyCheckIn.dayKey(for: now)
        let sorted = healthKitSnapshots.sorted { $0.date > $1.date }
        let todayQuality = sorted.first { $0.dayKey == todayKey }?.qualityScore
        let recentSnapshots = Array(sorted.prefix(7))
        let recent = recentSnapshots.map(\.qualityScore)
        let recentMean = recent.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count)
        let watchCoverage = recentSnapshots.isEmpty
            ? 0
            : Double(recentSnapshots.filter { $0.hasWatchSource == true }.count) / Double(recentSnapshots.count)
        let hrvCoverage = recentSnapshots.isEmpty
            ? 0
            : Double(recentSnapshots.filter { $0.hrv > 0 }.count) / Double(recentSnapshots.count)
        let hrvScore = currentHRV > 0 && hrvBaseline > 0 ? min(max(ppgQuality, 0), 1) : 0
        let passiveContinuity = min(watchCoverage * 0.55 + hrvCoverage * 0.45, 1)
        let blended = max(todayQuality ?? 0, recentMean ?? 0, hrvScore, passiveContinuity)
        return min(max(Int((blended * 100).rounded()), 0), 100)
    }

    private static func headline(for band: DailyCoachInsight.Band, score: Int, hrvDelta: Double?, sleepHours: Double) -> String {
        if let hrvDelta, hrvDelta <= -15, sleepHours > 0, sleepHours <= 6 {
            return "Seu corpo parece menos recuperado hoje."
        }

        switch band {
        case .ready:
            return "Bom dia para manter o plano."
        case .strained:
            return "Dia pede ritmo mais cuidadoso."
        case .lowRecovery:
            return "Recovery baixo: simplifique o dia."
        }
    }

    private static func recommendation(
        band: DailyCoachInsight.Band,
        sleepHours: Double,
        hrvDelta: Double?,
        ppgStress: Double,
        mood: Double,
        anxiety: Double,
        energy: Double,
        irritability: Double,
        medicationStatus: MedicationStatus,
        steps: Int
    ) -> String {
        if medicationStatus != .taken {
            return "Priorize regularizar a medicação conforme prescrito e avise sua equipe se houver efeito colateral."
        }

        if (hrvDelta ?? 0) <= -15 && sleepHours > 0 && sleepHours <= 6 {
            return "Se puder, adie conversa ou reunião difícil e faça 20 min de respiração guiada hoje."
        }

        if irritability >= 4 && ((sleepHours > 0 && sleepHours <= 6.5) || anxiety >= 4) {
            return "Hoje reduza atrito: evite conversa difícil, use pausas curtas e escolha uma prioridade essencial."
        }

        if ppgStress >= 65 || anxiety >= 4 {
            return "Reduza carga social por algumas horas e faça 10 ciclos de respiração lenta antes de decisões difíceis."
        }

        if energy <= 2 || mood <= 2 {
            return "Use meta mínima: medicação, alimentação, luz natural e uma tarefa pequena. Reavalie energia no fim da tarde."
        }

        if sleepHours > 0 && sleepHours <= 6 {
            return "Proteja uma janela de descanso hoje: luz natural cedo, cafeína só pela manhã e rotina de sono simples à noite."
        }

        if steps > 0 && steps < 1500 {
            return "Faça uma caminhada leve de 10 a 15 min para sinalizar segurança ao corpo, sem transformar em cobrança."
        }

        switch band {
        case .ready:
            return "Mantenha o plano do dia e registre qualquer gatilho novo para calibrar o coach."
        case .strained:
            return "Escolha uma tarefa difícil a menos hoje e reserve 20 min para recuperação ativa."
        case .lowRecovery:
            return "Troque metas ambiciosas por manutenção: alimentação, medicação, luz natural e descanso."
        }
    }

    private static func dailyActions(
        band: DailyCoachInsight.Band,
        sleepHours: Double,
        hrvDelta: Double?,
        ppgStress: Double,
        mood: Double,
        anxiety: Double,
        energy: Double,
        irritability: Double,
        medicationStatus: MedicationStatus,
        steps: Int
    ) -> [DailyCoachInsight.Action] {
        var actions: [DailyCoachInsight.Action] = []

        if medicationStatus != .taken {
            actions.append(.init(
                icon: "pills.circle.fill",
                title: "Regularizar medicação",
                detail: "Confira a prescrição e marque como tomada só se realmente tomou. Se houve efeito colateral, anote para o médico.",
                priority: 100
            ))
        }

        if (hrvDelta ?? 0) <= -15 || band == .lowRecovery {
            actions.append(.init(
                icon: "person.2.slash.fill",
                title: "Reduzir carga social",
                detail: "Adie conversa difícil, negociação ou reunião emocionalmente pesada quando isso for possível.",
                priority: 92
            ))
        }

        if sleepHours > 0 && sleepHours <= 6.25 {
            actions.append(.init(
                icon: "moon.zzz.fill",
                title: "Priorizar sono",
                detail: "Cafeína só cedo, luz baixa à noite e uma janela protegida para dormir hoje.",
                priority: 88
            ))
        }

        if ppgStress >= 65 || anxiety >= 4 || (hrvDelta ?? 0) <= -10 {
            actions.append(.init(
                icon: "lungs.fill",
                title: "Respiração guiada",
                detail: "Faça 20 min em ritmo lento. Se estiver sem tempo, faça 10 ciclos antes da próxima decisão importante.",
                priority: 84
            ))
        }

        if anxiety >= 4 || mood <= 2 || band == .lowRecovery {
            actions.append(.init(
                icon: "square.and.pencil",
                title: "Check-in extra",
                detail: "Reavalie humor, ansiedade e segurança no fim da tarde para ver se o plano do dia funcionou.",
                priority: 76
            ))
        }

        if irritability >= 4 {
            actions.append(.init(
                icon: "flame.fill",
                title: "Reduzir atrito",
                detail: "Evite conversas difíceis hoje quando puder e use pausas de 5 min antes de responder mensagens sensíveis.",
                priority: 74
            ))
        }

        if mood <= 2 || anxiety >= 4.5 {
            actions.append(.init(
                icon: "message.badge.fill",
                title: "Avisar terapeuta",
                detail: "Envie uma nota curta com o padrão de hoje se isso estiver combinado no seu plano de cuidado.",
                priority: 72
            ))
        }

        if energy <= 2 {
            actions.append(.init(
                icon: "bolt.slash.fill",
                title: "Meta mínima",
                detail: "Escolha uma tarefa pequena e termine cedo. A meta é preservar adesão sem aumentar a carga.",
                priority: 70
            ))
        }

        if steps > 0 && steps < 1500 && band != .lowRecovery {
            actions.append(.init(
                icon: "figure.walk",
                title: "Exercício leve",
                detail: "Caminhe 10 a 15 min em intensidade confortável. A meta é regular, não performar.",
                priority: 64
            ))
        }

        if band == .ready && actions.isEmpty {
            actions.append(.init(
                icon: "checkmark.seal.fill",
                title: "Manter rotina",
                detail: "Siga o plano normal e registre qualquer gatilho novo para deixar o coach mais preciso.",
                priority: 50
            ))
            actions.append(.init(
                icon: "figure.walk",
                title: "Movimento leve",
                detail: "Inclua uma caminhada curta ou alongamento para preservar o ritmo do dia.",
                priority: 45
            ))
        }

        if !actions.contains(where: { $0.title == "Revisar com médico" }), medicationStatus != .taken || mood <= 2 || anxiety >= 4.5 {
            actions.append(.init(
                icon: "stethoscope",
                title: "Revisar com médico",
                detail: "Não ajuste dose sozinho. Leve este padrão para a próxima consulta ou antecipe contato se estiver piorando.",
                priority: 60
            ))
        }

        return Array(actions.sorted { $0.priority > $1.priority }.prefix(4))
    }
}
