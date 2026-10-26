//
//  ContentViewTypes.swift
//  Neuremia
//
//  Enums and non-View supporting types extracted from ContentView.swift (QC1).
//

import SwiftUI
import SwiftData

enum AppSupportContact {
    static let email = "suporte@neuremia.app"

    static func reportURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

// MARK: - Risk Scoring Constants
// Sprint C: magic numbers extraídos para constantes nomeadas com documentação
enum RiskScoringConstants {
    /// Peso para cada alerta de focus ativo (cap em 15 = 3 alertas)
    static let focusAlertWeight: Double = 5
    static let focusAlertMaxPoints: Double = 15

    /// Peso para tendência de queda de humor
    static let moodTrendWeight: Double = 10
    /// Limiar de tendência de humor (slope < -0.35 indica queda)
    static let moodTrendThreshold: Double = -0.35

    /// Peso para tendência de aumento de ansiedade
    static let anxietyTrendWeight: Double = 10
    /// Limiar de tendência de ansiedade (slope > 0.35 indica aumento)
    static let anxietyTrendThreshold: Double = 0.35

    /// Peso para tendência de redução do sono
    static let sleepTrendWeight: Double = 8
    /// Limiar de tendência de sono (slope < -0.35 indica redução)
    static let sleepTrendThreshold: Double = -0.35

    /// Peso para adesão irregular de medicação
    static let medicationAdherenceWeight: Double = 8
    /// Limiar mínimo de adesão à medicação (80%)
    static let medicationAdherenceThreshold: Double = 0.8
    /// Mínimo de check-ins para avaliar adesão longitudinalmente
    static let minCheckInsForAdherence: Int = 3

    /// Peso máximo para carga de escalas clínicas
    static let scaleLoadMaxPoints: Double = 18
    /// Multiplicador para carga de escalas
    static let scaleLoadMultiplier: Double = 14
    /// Limiar de carga alta para escala (85%)
    static let scaleLoadHighThreshold: Double = 0.85

    /// Peso para sinal de segurança alto no texto
    static let textHighRiskWeight: Double = 24
    /// Peso para sinal moderado no texto
    static let textModerateRiskWeight: Double = 10

    /// Peso para PPG indicando ativação autonômica
    static let ppgStressWeight: Double = 8
    /// Limiar mínimo de qualidade do sinal PPG
    static let ppgQualityThreshold: Double = 0.45
    /// Limiar de stress no PPG
    static let ppgStressThreshold: Double = 0.65

    /// Peso para pausas de voz elevadas
    static let voicePauseWeight: Double = 5
    /// Limiar de ratio de pausas de voz
    static let voicePauseRatioThreshold: Double = 0.55

    /// Peso para digitação lenta
    static let typingSlowWeight: Double = 4
    /// Limiar de velocidade mínima de digitação (caracteres/min)
    static let typingSpeedMinThreshold: Double = 25

    /// Peso para alertas de baseline por ocorrência
    static let baselineAlertWeight: Double = 6
    /// Peso máximo para alertas de baseline (3 alertas)
    static let baselineAlertMaxPoints: Double = 18

    /// Peso para padrão semelhante a crise anterior
    static let similarPatternWeight: Double = 12

    /// Limiar de score para risco alto (>= 66)
    static let highRiskThreshold: Int = 66
    /// Limiar de score para risco moderado (>= 34)
    static let moderateRiskThreshold: Int = 34
}

struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.title2.weight(.bold))
            .foregroundStyle(Color.neuroYellow)
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.neuroYellow)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(Color.neuroTextOnNavy)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color.neuroTextOnNavy.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.neuroCardOnDark.opacity(0.90))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.neuroYellow.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct MetricOption: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

struct AutomaticScaleResult: Identifiable {
    let id = UUID()
    let scale: ScaleKind
    let answers: [Int]
    let score: Int
    let interpretation: String
}

struct NeuremiaRiskSignature {
    let score: Int
    let level: ClinicalRiskLevel
    let explanation: String
    let baseline: String
    let baselineAlerts: [String]
    let similarCrisisPattern: String?
    let factors: [String]
    let focusAlerts: [String]
    let explanationDetails: [String]
    let protectiveFactors: [String]
    let predictedWindow: String

    static func calculate(
        summary: LongitudinalSummary,
        checkIns: [DailyCheckIn],
        scaleResults: [AutomaticScaleResult],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String],
        textAssessment: TextRiskAssessment,
        ppgStress: Double,
        ppgQuality: Double,
        voicePauseRatio: Double,
        typingSpeed: Double,
        careFocus: CareFocus,
        moodModerateThreshold: Double = 2.0,
        anxietyModerateThreshold: Double = 4.0,
        minimumSleepThreshold: Double = 6.0
    ) -> NeuremiaRiskSignature {
        var points = 0.0
        var factors: [String] = []
        var protective: [String] = []
        let weights = careFocus.riskWeights
        var focusAlerts: [String] = []
        let baselineAlerts = baselineDeviationReasons(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours
        )
        let similarPattern = similarCrisisPattern(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )

        if mood <= moodModerateThreshold {
            points += 16 * weights.mood
            factors.append("humor abaixo do limiar pessoal")
        } else if mood >= 4 {
            protective.append("humor preservado")
        }

        if anxiety >= anxietyModerateThreshold {
            points += 14 * weights.anxiety
            factors.append("ansiedade acima do limiar pessoal")
        }

        if sleepHours < minimumSleepThreshold {
            points += 12 * weights.sleep
            factors.append("sono abaixo do mínimo pessoal")
        } else if sleepHours >= 7 {
            protective.append("sono adequado")
        }

        switch medicationStatus {
        case .pending:
            points += 14 * weights.medication
            factors.append("medicação pendente")
        case .partial:
            points += 8 * weights.medication
            factors.append("medicação parcial")
        case .taken:
            protective.append("medicação tomada")
        }

        if !activeTriggers.isEmpty {
            points += min(Double(activeTriggers.count) * 4 * weights.triggers, 14)
            factors.append("gatilhos ativos: \(activeTriggers.prefix(2).joined(separator: ", "))")
        }

        focusAlerts = careFocus.alerts(
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )
        if !focusAlerts.isEmpty {
            points += min(Double(focusAlerts.count) * RiskScoringConstants.focusAlertWeight, RiskScoringConstants.focusAlertMaxPoints)
            factors.append(contentsOf: focusAlerts)
        }

        if summary.moodTrend < RiskScoringConstants.moodTrendThreshold {
            points += RiskScoringConstants.moodTrendWeight
            factors.append("tendência de queda do humor")
        }
        if summary.anxietyTrend > RiskScoringConstants.anxietyTrendThreshold {
            points += RiskScoringConstants.anxietyTrendWeight
            factors.append("tendência de aumento da ansiedade")
        }
        if summary.sleepTrend < RiskScoringConstants.sleepTrendThreshold {
            points += RiskScoringConstants.sleepTrendWeight
            factors.append("tendência de redução do sono")
        }
        if summary.medicationAdherence < RiskScoringConstants.medicationAdherenceThreshold, summary.analyzedCheckInCount >= RiskScoringConstants.minCheckInsForAdherence {
            points += RiskScoringConstants.medicationAdherenceWeight
            factors.append("adesão longitudinal irregular")
        }

        let scaleLoad = scaleResults.reduce(0.0) { partial, result in
            partial + normalizedScaleRisk(result)
        }
        points += min(scaleLoad * RiskScoringConstants.scaleLoadMultiplier, RiskScoringConstants.scaleLoadMaxPoints)
        if scaleLoad > RiskScoringConstants.scaleLoadHighThreshold {
            factors.append("check-up automático alterado")
        }

        switch textAssessment.level {
        case .high:
            points += RiskScoringConstants.textHighRiskWeight
            factors.append("sinal de segurança alto")
        case .moderate:
            points += RiskScoringConstants.textModerateRiskWeight
            factors.append("texto com sinal moderado")
        case .low:
            break
        }

        if ppgQuality > RiskScoringConstants.ppgQualityThreshold, ppgStress > RiskScoringConstants.ppgStressThreshold {
            points += RiskScoringConstants.ppgStressWeight
            factors.append("PPG sugere ativação autonômica")
        }
        if voicePauseRatio > RiskScoringConstants.voicePauseRatioThreshold {
            points += RiskScoringConstants.voicePauseWeight
            factors.append("pausas de voz elevadas")
        }
        if typingSpeed > 0, typingSpeed < RiskScoringConstants.typingSpeedMinThreshold {
            points += RiskScoringConstants.typingSlowWeight
            factors.append("digitação mais lenta no app")
        }
        if !baselineAlerts.isEmpty {
            points += min(Double(baselineAlerts.count) * RiskScoringConstants.baselineAlertWeight, RiskScoringConstants.baselineAlertMaxPoints)
            factors.append(contentsOf: baselineAlerts)
        }
        if similarPattern != nil {
            points += RiskScoringConstants.similarPatternWeight
            factors.append("padrão semelhante antes de crise")
        }

        let score = Int(min(max(points, 0), 100).rounded())
        let level: ClinicalRiskLevel
        if score >= RiskScoringConstants.highRiskThreshold || textAssessment.level == .high {
            level = .high
        } else if score >= RiskScoringConstants.moderateRiskThreshold {
            level = .moderate
        } else {
            level = .low
        }

        let baseline = baselineText(checkIns: checkIns)
        let explanationDetails = detailedExplanations(
            checkIns: checkIns,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggers
        )
        let explanation = factors.isEmpty
            ? "Sem desvio relevante do padrão recente."
            : factors.prefix(4).joined(separator: " • ")
        let predictedWindow = level == .high
            ? "Atenção nas próximas 24-72h"
            : level == .moderate ? "Observar próximos 2-7 dias" : "Manter rotina e acompanhar"

        return NeuremiaRiskSignature(
            score: score,
            level: level,
            explanation: explanation,
            baseline: baseline,
            baselineAlerts: baselineAlerts,
            similarCrisisPattern: similarPattern,
            factors: factors,
            focusAlerts: focusAlerts,
            explanationDetails: explanationDetails,
            protectiveFactors: protective,
            predictedWindow: predictedWindow
        )
    }

    private static func normalizedScaleRisk(_ result: AutomaticScaleResult) -> Double {
        switch result.scale {
        case .phq9:
            return Double(result.score) / 27
        case .gad7:
            return Double(result.score) / 21
        case .ymrs:
            return Double(result.score) / 60
        }
    }

    private static func baselineText(checkIns: [DailyCheckIn]) -> String {
        let recent = Array(checkIns.prefix(30))
        guard !recent.isEmpty else {
            return "Basal ainda em formação; registre alguns dias para personalizar."
        }

        let moodStats = stats(recent.map(\.mood))
        let anxietyStats = stats(recent.map(\.anxiety))
        let sleepStats = stats(recent.map(\.sleepHours))
        return "Basal 30 dias: humor \(format(mean: moodStats.mean, deviation: moodStats.deviation)), ansiedade \(format(mean: anxietyStats.mean, deviation: anxietyStats.deviation)), sono \(format(mean: sleepStats.mean, deviation: sleepStats.deviation))h."
    }

    private static func baselineDeviationReasons(checkIns: [DailyCheckIn], mood: Double, anxiety: Double, sleepHours: Double) -> [String] {
        let baseline = Array(checkIns.prefix(30))
        guard baseline.count >= 5 else {
            return []
        }

        var reasons: [String] = []
        let moodStats = stats(baseline.map(\.mood))
        let anxietyStats = stats(baseline.map(\.anxiety))
        let sleepStats = stats(baseline.map(\.sleepHours))

        if isMeaningfulDeviation(current: mood, mean: moodStats.mean, deviation: moodStats.deviation, direction: .lower) {
            reasons.append("humor abaixo do basal individual")
        }
        if isMeaningfulDeviation(current: anxiety, mean: anxietyStats.mean, deviation: anxietyStats.deviation, direction: .higher) {
            reasons.append("ansiedade acima do basal individual")
        }
        if isMeaningfulDeviation(current: sleepHours, mean: sleepStats.mean, deviation: sleepStats.deviation, direction: .lower) {
            reasons.append("sono abaixo do basal individual")
        }

        if progressiveDrop(values: baseline.prefix(7).map(\.sleepHours)) {
            reasons.append("sono em queda progressiva")
        }
        if progressiveRise(values: baseline.prefix(7).map(\.anxiety)) {
            reasons.append("ansiedade em alta progressiva")
        }
        if progressiveDrop(values: baseline.prefix(7).map(\.mood)) {
            reasons.append("humor em queda progressiva")
        }

        return reasons
    }

    private static func detailedExplanations(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String]
    ) -> [String] {
        var details: [String] = []
        let recent = Array(checkIns.prefix(7))
        let chronological = recent.sorted { $0.date < $1.date }

        if consecutiveSleepDropDays(in: chronological) >= 3 {
            details.append("Sono caiu por \(consecutiveSleepDropDays(in: chronological)) noites seguidas.")
        }

        if let first = chronological.first, first.anxiety > 0.1 {
            let anxietyIncrease = ((anxiety - first.anxiety) / max(first.anxiety, 0.5)) * 100
            if anxietyIncrease >= 20 {
                details.append("Ansiedade subiu \(Int(anxietyIncrease.rounded()))% em relação ao início da semana.")
            }
        }

        let incompleteMedicationDays = recent.filter { !$0.medicationTaken }.count
        if medicationStatus != .taken || incompleteMedicationDays >= 2 {
            let total = incompleteMedicationDays + (medicationStatus == .taken ? 0 : 1)
            details.append("Medicação ficou parcial/pendente em \(max(total, 1)) registro(s) recentes.")
        }

        let recentTriggers = recent.flatMap { triggerLabels(from: $0.journalEntry) } + activeTriggers.map { $0.lowercased() }
        if let commonTrigger = Dictionary(grouping: recentTriggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }), commonTrigger.value >= 2 {
            details.append("Gatilho \(commonTrigger.key) apareceu antes ou durante piora recente.")
        }

        if let first = chronological.first, first.mood > 0.1 {
            let moodDrop = ((first.mood - mood) / max(first.mood, 0.5)) * 100
            if moodDrop >= 20 {
                details.append("Humor caiu \(Int(moodDrop.rounded()))% em relação ao início da semana.")
            }
        }

        if sleepHours < 6 {
            details.append("Sono atual abaixo de 6h, sinal sensível para vários focos clínicos.")
        }

        return Array(details.prefix(5))
    }

    private static func consecutiveSleepDropDays(in checkIns: [DailyCheckIn]) -> Int {
        guard checkIns.count >= 3 else { return 0 }
        var streak = 1
        var best = 1
        for index in 1..<checkIns.count {
            if checkIns[index].sleepHours < checkIns[index - 1].sleepHours {
                streak += 1
                best = max(best, streak)
            } else {
                streak = 1
            }
        }
        return best >= 3 ? best : 0
    }

    private static func similarCrisisPattern(
        checkIns: [DailyCheckIn],
        mood: Double,
        anxiety: Double,
        sleepHours: Double,
        medicationStatus: MedicationStatus,
        activeTriggers: [String]
    ) -> String? {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard chronological.count >= 5 else {
            return nil
        }

        let currentVector = CrisisAntecedentVector(
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationTaken: medicationStatus == .taken,
            triggers: Set(activeTriggers.map { $0.lowercased() })
        )

        var matches: [(daysBefore: Int, score: Double, crisis: DailyCheckIn)] = []
        for index in chronological.indices {
            let crisis = chronological[index]
            guard crisis.mood <= 2 || crisis.anxiety >= 4 || crisis.suicidalIdeation else { continue }

            for offset in 1...7 {
                let antecedentIndex = chronological.index(index, offsetBy: -offset, limitedBy: chronological.startIndex)
                guard let antecedentIndex else { continue }

                let antecedent = chronological[antecedentIndex]
                let vector = CrisisAntecedentVector(
                    mood: antecedent.mood,
                    anxiety: antecedent.anxiety,
                    sleepHours: antecedent.sleepHours,
                    medicationTaken: antecedent.medicationTaken,
                    triggers: Set(triggerLabels(from: antecedent.journalEntry))
                )
                let score = currentVector.similarity(to: vector)
                if score >= 0.72 {
                    matches.append((offset, score, crisis))
                }
            }
        }

        guard let best = matches.max(by: { $0.score < $1.score }) else {
            return nil
        }

        let percent = Int((best.score * 100).rounded())
        return "Padrão \(percent)% parecido apareceu \(best.daysBefore) dia(s) antes de um dia ruim anterior."
    }

    private static func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }

    private enum DeviationDirection {
        case higher
        case lower
    }

    private static func isMeaningfulDeviation(current: Double, mean: Double, deviation: Double, direction: DeviationDirection) -> Bool {
        let safeDeviation = max(deviation, 0.35)
        switch direction {
        case .higher:
            return current >= mean + safeDeviation
        case .lower:
            return current <= mean - safeDeviation
        }
    }

    private static func stats(_ values: [Double]) -> (mean: Double, deviation: Double) {
        guard !values.isEmpty else { return (0, 0) }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return (mean, sqrt(variance))
    }

    private static func format(mean: Double, deviation: Double) -> String {
        "\(String(format: "%.1f", mean))±\(String(format: "%.1f", deviation))"
    }

    private static func progressiveDrop(values: [Double]) -> Bool {
        let ordered = Array(values.reversed())
        guard ordered.count >= 5 else { return false }
        return (ordered.last ?? 0) <= (ordered.first ?? 0) - 0.8
    }

    private static func progressiveRise(values: [Double]) -> Bool {
        let ordered = Array(values.reversed())
        guard ordered.count >= 5 else { return false }
        return (ordered.last ?? 0) >= (ordered.first ?? 0) + 0.8
    }
}

struct CrisisAntecedentVector {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let medicationTaken: Bool
    let triggers: Set<String>

    func similarity(to other: CrisisAntecedentVector) -> Double {
        let moodScore = closeness(mood, other.mood, range: 4)
        let anxietyScore = closeness(anxiety, other.anxiety, range: 4)
        let sleepScore = closeness(sleepHours, other.sleepHours, range: 8)
        let medicationScore = medicationTaken == other.medicationTaken ? 1.0 : 0.0
        let triggerScore = triggerSimilarity(to: other)
        return moodScore * 0.24
            + anxietyScore * 0.24
            + sleepScore * 0.22
            + medicationScore * 0.14
            + triggerScore * 0.16
    }

    private func closeness(_ first: Double, _ second: Double, range: Double) -> Double {
        max(0, 1 - abs(first - second) / range)
    }

    private func triggerSimilarity(to other: CrisisAntecedentVector) -> Double {
        if triggers.isEmpty && other.triggers.isEmpty {
            return 1
        }
        let intersection = triggers.intersection(other.triggers).count
        let union = triggers.union(other.triggers).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

enum PatientPage: String, CaseIterable, Identifiable {
    case diary = "Hoje"
    // Aba de gamificação inspirada em gamificação — antes "Evoluir", renomeada
    // para "Progresso" (Sprint 26) para deixar mais claro o que a aba entrega.
    case evolve = "Progresso"
    // Charts/Histórico - renomeado para Explorar
    case explore = "Explorar"
    // Ferramentas movidas para Settings sheet via toolbar

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .diary:
            "house.fill"
        case .evolve:
            "chart.line.uptrend.xyaxis.circle.fill"
        case .explore:
            "sparkles"
        }
    }
}

// `PatientPageSelector` foi removido na Sprint 20 — a TabView raiz (Sprint 19)
// substituiu o segmented picker. O enum PatientPage continua sendo a fonte
// canônica para `selectedPatientPage` (controla qual aba está ativa).

// Sprint 25: filtro de tipo de evento para a Tab Evolução.
enum EvolutionFilter: String, CaseIterable, Identifiable {
    case all = "Tudo"
    case checkIns = "Check-ins"
    case scales = "Escalas"
    case alerts = "Alertas"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .checkIns: "calendar"
        case .scales: "list.clipboard"
        case .alerts: "bell.badge"
        }
    }
}

enum ExploreMode: String, CaseIterable, Identifiable {
    case now = "Agora"
    case trends = "Tendências"
    case history = "Histórico"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .now: "bolt.heart.fill"
        case .trends: "chart.line.uptrend.xyaxis"
        case .history: "clock.arrow.circlepath"
        }
    }
}

// MARK: - Tipos do dashboard médico (Sprint 24)

enum ClinicianPatientFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case highRisk = "Alto risco"
    case alphabetical = "Por nome"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: "list.bullet"
        case .highRisk: "exclamationmark.triangle.fill"
        case .alphabetical: "textformat"
        }
    }
}

enum SentInviteStatusFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case pending = "Pendentes"
    case accepted = "Aceitos"
    case revoked = "Recusados"
    var id: String { rawValue }
    var apiStatus: String? {
        switch self {
        case .all: return nil
        case .pending: return "pending"
        case .accepted: return "accepted"
        case .revoked: return "revoked"
        }
    }
}

// P1-2 (UX): níveis de toast centralizados. .error não auto-dismiss.
enum ToastLevel {
    case success, warning, error
    var color: Color {
        switch self { case .success: .green; case .warning: .orange; case .error: .red }
    }
    var icon: String {
        switch self { case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .error: "xmark.octagon.fill" }
    }
    /// nil = não faz auto-dismiss
    var autoDismissSeconds: Double? {
        switch self { case .success: 2; case .warning: 4; case .error: nil }
    }
}

// M5 (UX-P0): abas do dashboard do clínico — substitui o scroll único.
enum ClinicianTab: String, CaseIterable, Identifiable {
    case patients = "Pacientes"
    case analysis = "Análise"
    case reports  = "Relatórios"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .patients: "person.2"
        case .analysis: "chart.xyaxis.line"
        case .reports:  "doc.text.magnifyingglass"
        }
    }
}

enum RemotePatientSubTab: String, CaseIterable, Identifiable {
    case overview = "Visão geral"
    case checkIns = "Diário"
    case assessments = "Escalas"
    case alerts = "Alertas"
    case reports = "Relatórios"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "person.text.rectangle"
        case .checkIns: "list.bullet.rectangle"
        case .assessments: "list.clipboard"
        case .alerts: "bell.badge"
        case .reports: "doc.text"
        }
    }
}

enum MedicationStatus: String, CaseIterable, Identifiable {
    case pending = "Pendente"
    case partial = "Parcial"
    case taken = "Tomada"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .pending:
            "⏰"
        case .partial:
            "🌓"
        case .taken:
            "✅"
        }
    }

    var subtitle: String {
        switch self {
        case .pending:
            "Ainda não tomei"
        case .partial:
            "Tomei parte da medicação"
        case .taken:
            "Tomada hoje"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            .orange
        case .partial:
            .neuroYellow
        case .taken:
            .green
        }
    }
}

enum SafetyStatus: String, CaseIterable, Identifiable {
    case safe = "Seguro"
    case attention = "Atenção"
    case urgent = "Apoio"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .safe:
            "🛟"
        case .attention:
            "🟡"
        case .urgent:
            "🆘"
        }
    }

    var subtitle: String {
        switch self {
        case .safe:
            "Sem pensamentos de me machucar"
        case .attention:
            "Pensamentos difíceis, mas sem risco imediato"
        case .urgent:
            "Preciso de apoio agora"
        }
    }

    var color: Color {
        switch self {
        case .safe:
            .green
        case .attention:
            .orange
        case .urgent:
            .red
        }
    }
}

enum CareFocus: String, CaseIterable, Identifiable {
    case bipolar = "Bipolaridade"
    case depression = "Depressão"
    case anxiety = "Ansiedade"
    case borderline = "Borderline"
    case burnout = "Burnout"
    case adhd = "TDAH"
    case postpartum = "Pós-parto"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bipolar:
            "arrow.triangle.2.circlepath"
        case .depression:
            "cloud.rain.fill"
        case .anxiety:
            "waveform.path.ecg"
        case .borderline:
            "person.2.wave.2.fill"
        case .burnout:
            "flame.fill"
        case .adhd:
            "target"
        case .postpartum:
            "heart.text.square.fill"
        }
    }

    var description: String {
        switch self {
        case .bipolar:
            "Prioriza sono, energia, irritabilidade, medicação e sinais de virada de humor."
        case .depression:
            "Prioriza humor, energia, sono, apetite, adesão e sinais de desesperança."
        case .anxiety:
            "Prioriza ansiedade, sono, gatilhos, pensamentos repetitivos e tensão diária."
        case .borderline:
            "Prioriza intensidade emocional, gatilhos interpessoais e segurança."
        case .burnout:
            "Prioriza energia, sono, estresse, rotina e recuperação."
        case .adhd:
            "Prioriza energia, rotina, sono, adesão e impacto funcional."
        case .postpartum:
            "Prioriza sono, humor, ansiedade, apoio e sinais de alerta no pós-parto."
        }
    }

    var modules: String {
        switch self {
        case .bipolar:
            "Sono, energia, irritabilidade, YMRS, adesão e gatilhos de virada."
        case .depression:
            "PHQ-9, humor, energia, sono, apetite e segurança."
        case .anxiety:
            "GAD-7, ansiedade, sono, gatilhos e pensamentos repetitivos."
        case .borderline:
            "Intensidade emocional, conflitos, impulsividade e plano de segurança."
        case .burnout:
            "Energia, estresse, sono, recuperação e rotina."
        case .adhd:
            "Rotina, sono, energia, adesão e impacto funcional."
        case .postpartum:
            "Humor, ansiedade, sono, rede de apoio e sinais de alerta."
        }
    }

    var dsm5MonitoringFrame: String {
        switch self {
        case .bipolar:
            "No DSM-5/DSM-5-TR, transtornos bipolares envolvem episódios de elevação/expansividade ou irritabilidade do humor, alterações de energia/atividade e impacto funcional. Por isso o app acompanha sono, energia, irritabilidade, humor, impulsividade indireta, adesão e sinais de virada."
        case .depression:
            "O enquadramento DSM-5/DSM-5-TR para quadros depressivos valoriza duração, sofrimento/impacto funcional e um conjunto de sintomas afetivos, cognitivos, vegetativos e de segurança. Por isso o app observa humor, energia, sono, apetite, pensamentos negativos e risco de autoagressão."
        case .anxiety:
            "No DSM-5/DSM-5-TR, transtornos de ansiedade envolvem medo/ansiedade persistentes, preocupação, sintomas físicos e prejuízo funcional. Por isso o app monitora ansiedade diária, sono, gatilhos, pensamentos repetitivos, ativação corporal e evitação indireta."
        case .borderline:
            "O DSM-5/DSM-5-TR descreve transtornos de personalidade a partir de padrões persistentes de funcionamento, relações, impulsividade e regulação emocional. Por isso o app observa intensidade emocional, conflitos, segurança, gatilhos interpessoais e padrões repetidos ao longo do tempo."
        case .burnout:
            "Burnout não é uma categoria diagnóstica principal do DSM-5/DSM-5-TR; é acompanhado aqui como estado relacionado a estresse, exaustão, sono e funcionamento. O app usa esse módulo para monitoramento funcional, não para diagnóstico."
        case .adhd:
            "O DSM-5/DSM-5-TR entende TDAH como padrão persistente de desatenção e/ou hiperatividade-impulsividade com impacto em múltiplos contextos. Por isso o app acompanha rotina, sono, adesão, energia, funcionamento e consistência diária."
        case .postpartum:
            "O DSM-5/DSM-5-TR permite especificadores periparto para alguns quadros de humor. O app trata pós-parto como contexto clínico de maior vulnerabilidade, priorizando sono, humor, ansiedade, rede de apoio e sinais de segurança."
        }
    }

    var dsm5SignalSummary: [String] {
        switch self {
        case .bipolar:
            ["sono reduzido", "energia elevada ou queda brusca", "irritabilidade", "adesão medicamentosa", "YMRS como escala auxiliar"]
        case .depression:
            ["humor deprimido", "perda de energia", "sono/apetite alterados", "pensamentos negativos", "PHQ-9 como escala auxiliar"]
        case .anxiety:
            ["ansiedade persistente", "preocupação", "sono ruim", "gatilhos", "GAD-7 como escala auxiliar"]
        case .borderline:
            ["intensidade emocional", "conflitos", "impulsividade indireta", "segurança", "padrões repetidos"]
        case .burnout:
            ["exaustão", "recuperação ruim", "estresse", "sono", "impacto funcional"]
        case .adhd:
            ["rotina", "atenção indireta", "adesão", "sono", "funcionamento diário"]
        case .postpartum:
            ["sono fragmentado", "humor", "ansiedade", "apoio", "segurança"]
        }
    }

    var dsm5CriteriaGroups: [DSM5CriteriaGroup] {
        switch self {
        case .bipolar:
            [
                DSM5CriteriaGroup(
                    title: "Episódio de elevação ou irritabilidade",
                    items: ["humor anormalmente elevado, expansivo ou irritável", "aumento de energia ou atividade", "mudança clara em relação ao funcionamento habitual"]
                ),
                DSM5CriteriaGroup(
                    title: "Sinais associados",
                    items: ["menor necessidade de sono", "fala ou pensamentos acelerados", "impulsividade, agitação ou aumento de metas", "autoestima inflada ou distraibilidade"]
                ),
                DSM5CriteriaGroup(
                    title: "Impacto e exclusões",
                    items: ["prejuízo funcional, internação, psicose ou risco relevante", "avaliar substâncias, medicações, sono e condições clínicas", "diferenciar mania, hipomania, depressão e estados mistos"]
                )
            ]
        case .depression:
            [
                DSM5CriteriaGroup(
                    title: "Humor e interesse",
                    items: ["humor deprimido persistente", "perda de interesse ou prazer", "sofrimento clinicamente significativo"]
                ),
                DSM5CriteriaGroup(
                    title: "Sintomas cognitivos e vegetativos",
                    items: ["alterações de sono, apetite ou peso", "fadiga ou lentificação/agitação", "culpa, desesperança ou baixa autoestima", "concentração reduzida ou pensamentos de morte"]
                ),
                DSM5CriteriaGroup(
                    title: "Duração e contexto",
                    items: ["verificar persistência temporal", "avaliar prejuízo social, ocupacional ou familiar", "excluir luto, substâncias, bipolaridade e causas médicas"]
                )
            ]
        case .anxiety:
            [
                DSM5CriteriaGroup(
                    title: "Medo, ansiedade ou preocupação",
                    items: ["ansiedade persistente ou difícil de controlar", "preocupação excessiva", "hipervigilância ou sensação de ameaça"]
                ),
                DSM5CriteriaGroup(
                    title: "Ativação e evitação",
                    items: ["tensão, inquietação ou sintomas físicos", "sono prejudicado", "evitação de situações ou gatilhos", "dificuldade de concentração"]
                ),
                DSM5CriteriaGroup(
                    title: "Impacto e diferenciais",
                    items: ["confirmar prejuízo funcional", "avaliar pânico, fobias, trauma e obsessões", "considerar substâncias, cafeína, tireoide e outras causas clínicas"]
                )
            ]
        case .borderline:
            [
                DSM5CriteriaGroup(
                    title: "Padrão interpessoal e emocional",
                    items: ["instabilidade de relacionamentos", "medo intenso de abandono", "oscilações afetivas rápidas"]
                ),
                DSM5CriteriaGroup(
                    title: "Impulsividade e segurança",
                    items: ["impulsividade com potencial dano", "raiva intensa ou dificuldade de controle", "autoagressão, ameaças ou ideação suicida", "sensação de vazio ou identidade instável"]
                ),
                DSM5CriteriaGroup(
                    title: "Persistência e contexto",
                    items: ["padrão duradouro em múltiplos contextos", "diferenciar de episódios de humor, trauma e uso de substâncias", "avaliar risco atual antes de qualquer conclusão diagnóstica"]
                )
            ]
        case .burnout:
            [
                DSM5CriteriaGroup(
                    title: "Não é diagnóstico DSM-5 principal",
                    items: ["monitorar como contexto de estresse ocupacional", "avaliar exaustão, cinismo e queda de eficácia", "investigar impacto no sono, humor e funcionamento"]
                ),
                DSM5CriteriaGroup(
                    title: "Triagem relacionada",
                    items: ["diferenciar de depressão, ansiedade e transtornos do sono", "identificar sobrecarga, falta de recuperação e gatilhos de trabalho", "observar risco de autonegligência ou ideação suicida"]
                )
            ]
        case .adhd:
            [
                DSM5CriteriaGroup(
                    title: "Desatenção e/ou hiperatividade-impulsividade",
                    items: ["dificuldade persistente de atenção ou organização", "inquietação, impulsividade ou dificuldade de esperar", "inconsistência em tarefas e rotina"]
                ),
                DSM5CriteriaGroup(
                    title: "Curso e contextos",
                    items: ["sinais desde o desenvolvimento", "presença em mais de um ambiente", "prejuízo acadêmico, profissional, social ou doméstico"]
                ),
                DSM5CriteriaGroup(
                    title: "Diferenciais",
                    items: ["avaliar sono, ansiedade, depressão e uso de substâncias", "considerar efeitos de medicação e condições clínicas", "integrar relato do paciente e informantes quando possível"]
                )
            ]
        case .postpartum:
            [
                DSM5CriteriaGroup(
                    title: "Contexto periparto",
                    items: ["relacionar início dos sintomas ao ciclo gestacional/pós-parto", "monitorar humor, ansiedade, sono e apoio", "verificar sofrimento e prejuízo funcional"]
                ),
                DSM5CriteriaGroup(
                    title: "Segurança materna e do bebê",
                    items: ["avaliar pensamentos de autoagressão", "avaliar pensamentos de dano ao bebê sem julgamento", "identificar psicose, confusão, agitação grave ou risco imediato"]
                ),
                DSM5CriteriaGroup(
                    title: "Diferenciais",
                    items: ["distinguir tristeza pós-parto transitória de quadro persistente", "considerar bipolaridade, depressão, ansiedade e trauma", "acionar rede de apoio e avaliação urgente quando houver risco"]
                )
            ]
        }
    }

    var preferredScale: ScaleKind {
        switch self {
        case .bipolar:
            .ymrs
        case .depression, .borderline, .burnout, .postpartum:
            .phq9
        case .anxiety, .adhd:
            .gad7
        }
    }

    var riskWeights: CareFocusRiskWeights {
        switch self {
        case .bipolar:
            CareFocusRiskWeights(mood: 1.05, anxiety: 0.95, sleep: 1.45, medication: 1.25, triggers: 1.10)
        case .depression:
            CareFocusRiskWeights(mood: 1.35, anxiety: 0.95, sleep: 1.10, medication: 1.05, triggers: 1.00)
        case .anxiety:
            CareFocusRiskWeights(mood: 0.95, anxiety: 1.40, sleep: 1.15, medication: 1.00, triggers: 1.20)
        case .borderline:
            CareFocusRiskWeights(mood: 1.15, anxiety: 1.15, sleep: 1.00, medication: 1.00, triggers: 1.45)
        case .burnout:
            CareFocusRiskWeights(mood: 1.00, anxiety: 1.05, sleep: 1.25, medication: 0.90, triggers: 1.20)
        case .adhd:
            CareFocusRiskWeights(mood: 0.90, anxiety: 1.00, sleep: 1.20, medication: 1.35, triggers: 1.00)
        case .postpartum:
            CareFocusRiskWeights(mood: 1.25, anxiety: 1.25, sleep: 1.35, medication: 1.00, triggers: 1.10)
        }
    }

    func alerts(mood: Double, anxiety: Double, sleepHours: Double, medicationStatus: MedicationStatus, activeTriggers: [String]) -> [String] {
        var alerts: [String] = []
        switch self {
        case .bipolar:
            if sleepHours < 5 { alerts.append("bipolaridade: sono muito reduzido") }
            if mood >= 4 && sleepHours < 6 { alerts.append("bipolaridade: energia/humor alto com pouco sono") }
        case .depression:
            if mood <= 2 { alerts.append("depressão: queda de humor relevante") }
            if sleepHours > 9 || sleepHours < 5 { alerts.append("depressão: sono muito alterado") }
        case .anxiety:
            if anxiety >= 4 { alerts.append("ansiedade: ativação intensa") }
            if !activeTriggers.isEmpty { alerts.append("ansiedade: gatilhos ativos") }
        case .borderline:
            if activeTriggers.contains(where: { $0.localizedCaseInsensitiveContains("conflito") }) { alerts.append("borderline: gatilho interpessoal") }
            if anxiety >= 4 || mood <= 2 { alerts.append("borderline: intensidade emocional alta") }
        case .burnout:
            if mood <= 2 || sleepHours < 6 { alerts.append("burnout: exaustão/recuperação ruim") }
        case .adhd:
            if medicationStatus != .taken { alerts.append("TDAH: adesão medicamentosa incompleta") }
            if sleepHours < 6 { alerts.append("TDAH: sono reduzido pode piorar funcionamento") }
        case .postpartum:
            if sleepHours < 5 { alerts.append("pós-parto: privação de sono relevante") }
            if mood <= 2 || anxiety >= 4 { alerts.append("pós-parto: humor/ansiedade exige atenção") }
        }
        return alerts
    }

    var safetyGuidance: String {
        switch self {
        case .bipolar:
            "Se o sono cair ou houver aceleração, reduzir estímulos e avisar o profissional."
        case .depression:
            "Se houver desesperança ou risco de se machucar, acionar apoio imediatamente."
        case .anxiety:
            "Usar estratégias de aterramento, respiração e reduzir exposição ao gatilho."
        case .borderline:
            "Priorizar contato de apoio, adiar decisões impulsivas e usar estratégia combinada."
        case .burnout:
            "Reduzir demanda, proteger sono e planejar recuperação nas próximas 24h."
        case .adhd:
            "Checar medicação, rotina do dia e reduzir fricção para tarefas essenciais."
        case .postpartum:
            "Acionar rede de apoio, proteger sono e procurar ajuda se sintomas intensificarem."
        }
    }
}
