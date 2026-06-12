//
//  ClinicalAnalysis.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation

enum ClinicalAnalysis {
    static func score(for scale: ScaleKind, answers: [Int]) -> Int {
        // Clamp every answer to its declared range before summing so that
        // out-of-bounds data never inflates the score.
        // YMRS: items at indices 4,5,7,8 are 0–8; all others 0–4 → max 60.
        // PHQ-9: all items 0–3 → max 27.
        // GAD-7: all items 0–3 → max 21.
        answers.enumerated().reduce(0) { total, pair in
            let (index, value) = pair
            let range = scale.answerRange(for: index)
            return total + min(max(value, range.lowerBound), range.upperBound)
        }
    }

    static func interpretation(for scale: ScaleKind, score: Int) -> String {
        switch scale {
        case .phq9:
            switch score {
            case 0...4:
                "Mínimo"
            case 5...9:
                "Leve"
            case 10...14:
                "Moderado"
            case 15...19:
                "Moderadamente grave"
            default:
                "Grave"
            }
        case .gad7:
            switch score {
            case 0...4:
                "Mínimo"
            case 5...9:
                "Leve"
            case 10...14:
                "Moderado"
            default:
                "Grave"
            }
        case .ymrs:
            switch score {
            case 0...12:
                "Mínimo ou ausente"
            case 13...21:
                "Leve a moderado"
            default:
                "Marcado a grave"
            }
        }
    }

    static func textRisk(for text: String) -> ClinicalRiskLevel {
        textAssessment(for: text).level
    }

    static func textAssessment(for text: String) -> TextRiskAssessment {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let highRiskTerms = [
            // Suicidal ideation — direct
            "suicidio", "suicida", "me matar", "quero morrer", "vou me matar",
            "tirar minha vida", "acabar com tudo", "nao quero mais viver",
            "nao vale a pena viver", "melhor estar morto",
            // Self-harm
            "autolesao", "me machucar", "me cortar", "cortar os pulsos",
            "me ferir", "me machuquei",
            // Hopelessness / farewell
            "sem saida", "nao tem saida", "nao ha saida",
            "despedida", "ultima vez", "ninguem vai sentir falta",
            // Death wish (passive)
            "morrer", "desaparecer para sempre", "nao acordar mais"
        ]
        let moderateRiskTerms = [
            // Emotional distress
            "desesperanca", "desesperado", "desesperada", "sem esperanca",
            "nao aguento mais", "nao consigo mais", "estou no limite",
            "esgotado", "esgotada", "exausto", "exausta",
            // Anxiety / crisis
            "panico", "ataque de panico", "crise", "crise de ansiedade",
            "colapso", "entrei em colapso",
            // Sleep / physical
            "insonia", "nao consigo dormir", "noites sem dormir",
            // Impulse / control loss
            "impulsivo", "impulsiva", "sem controle", "perdi o controle",
            "fiz algo que nao devia",
            // Isolation / abandonment
            "me sinto sozinho", "me sinto sozinha", "ninguem me entende",
            "abandonado", "abandonada", "invisivel"
        ]
        let detectedHighRiskTerms = highRiskTerms.filter { normalized.contains($0) }
        let detectedModerateRiskTerms = moderateRiskTerms.filter { normalized.contains($0) }

        if !detectedHighRiskTerms.isEmpty {
            return TextRiskAssessment(
                level: .high,
                detectedTerms: detectedHighRiskTerms,
                explanation: "Termos compatíveis com risco de autolesão, morte ou desesperança extrema foram identificados."
            )
        }

        if !detectedModerateRiskTerms.isEmpty {
            return TextRiskAssessment(
                level: .moderate,
                detectedTerms: detectedModerateRiskTerms,
                explanation: "Termos compatíveis com sofrimento importante, crise, impulsividade ou perda de controle foram identificados."
            )
        }

        return TextRiskAssessment(
            level: .low,
            detectedTerms: [],
            explanation: "Nenhum termo textual de risco moderado ou alto foi identificado pela triagem local."
        )
    }

    static func summary(checkIns: [DailyCheckIn], assessments: [ScaleAssessment]) -> LongitudinalSummary {
        let recent = Array(checkIns.sorted { $0.date > $1.date }.prefix(14))
        let chronological = Array(recent.reversed())
        let moodValues = chronological.map(\.mood)
        let anxietyValues = chronological.map(\.anxiety)
        let sleepValues = chronological.map(\.sleepHours)
        let moodTrend = trend(values: moodValues)
        let anxietyTrend = trend(values: anxietyValues)
        let sleepTrend = trend(values: sleepValues)
        let averageSleep = average(recent.map(\.sleepHours))
        let medicationAdherence = adherence(in: recent)
        let combinedText = recent.map { "\($0.journalEntry) \($0.automaticThoughts)" }.joined(separator: " ")
        let textAssessment = recent.contains(where: \.suicidalIdeation)
            ? TextRiskAssessment(level: .high, detectedTerms: ["triagem positiva"], explanation: "A triagem estruturada marcou ideação suicida em pelo menos um registro recente.")
            : textAssessment(for: combinedText)
        let textRisk = textAssessment.level
        let scaleRisk = riskFromAssessments(assessments)

        var signals: [String] = []

        if moodTrend < -0.35 {
            signals.append("Humor em queda nos registros recentes")
        }

        if anxietyTrend > 0.35 {
            signals.append("Ansiedade em elevação")
        }

        if averageSleep > 0 && averageSleep < 5.5 {
            signals.append("Sono médio abaixo de 5h30")
        }

        if sleepTrend < -0.35 {
            signals.append("Sono em queda nos registros recentes")
        }

        if medicationAdherence < 0.8 && !recent.isEmpty {
            signals.append("Adesão medicamentosa abaixo de 80%")
        }

        if textRisk == .high {
            signals.append("Texto ou triagem indicam risco prioritário")
        } else if textRisk == .moderate {
            signals.append("Texto indica sofrimento importante")
        }

        if signals.isEmpty {
            signals.append("Sem sinais críticos nos dados recentes")
        }

        let metricRisk = riskFromMetrics(recent: recent, moodTrend: moodTrend, anxietyTrend: anxietyTrend, sleepTrend: sleepTrend, averageSleep: averageSleep, adherence: medicationAdherence)
        let riskLevel = highest([metricRisk, textRisk, scaleRisk])

        return LongitudinalSummary(
            riskLevel: riskLevel,
            moodTrend: moodTrend,
            anxietyTrend: anxietyTrend,
            sleepTrend: sleepTrend,
            averageSleep: averageSleep,
            medicationAdherence: medicationAdherence,
            textRisk: textRisk,
            textAssessment: textAssessment,
            analyzedCheckInCount: recent.count,
            firstMood: moodValues.first,
            latestMood: moodValues.last,
            firstAnxiety: anxietyValues.first,
            latestAnxiety: anxietyValues.last,
            firstSleep: sleepValues.first,
            latestSleep: sleepValues.last,
            signals: signals
        )
    }

    static func reportText(checkIns: [DailyCheckIn], assessments: [ScaleAssessment]) -> String {
        let summary = summary(checkIns: checkIns, assessments: assessments)
        let latestCheckIn = checkIns.sorted { $0.date > $1.date }.first
        let latestAssessments = assessments.sorted { $0.date > $1.date }.prefix(3)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        var lines = [
            "Relatório clínico NeuroFlow",
            "Gerado em: \(formatter.string(from: Date()))",
            "Risco atual: \(summary.riskLevel.rawValue)",
            "Registros analisados: \(summary.analyzedCheckInCount)",
            "Tendência de humor: \(String(format: "%.2f", summary.moodTrend)) por registro",
            "Tendência de ansiedade: \(String(format: "%.2f", summary.anxietyTrend)) por registro",
            "Tendência de sono: \(String(format: "%.2f", summary.sleepTrend))h por registro",
            "Sono médio recente: \(String(format: "%.1f", summary.averageSleep))h",
            "Adesão medicamentosa: \(String(format: "%.0f", summary.medicationAdherence * 100))%",
            "Classificação textual: \(summary.textAssessment.level.rawValue)",
            "Termos textuais detectados: \(summary.textAssessment.detectedTerms.isEmpty ? "nenhum" : summary.textAssessment.detectedTerms.joined(separator: ", "))",
            "Recomendação textual: \(summary.textAssessment.recommendation)",
            "Sinais: \(summary.signals.joined(separator: "; "))"
        ]

        if let latestCheckIn {
            lines.append("Último registro: humor \(String(format: "%.1f", latestCheckIn.mood)), ansiedade \(String(format: "%.1f", latestCheckIn.anxiety)), ideação suicida \(latestCheckIn.suicidalIdeation ? "sim" : "não")")
        }

        if !latestAssessments.isEmpty {
            let scaleText = latestAssessments.map { "\($0.scaleName): \($0.score) (\($0.interpretation))" }.joined(separator: "; ")
            lines.append("Escalas recentes: \(scaleText)")
        }

        lines.append("Observação: análise automatizada de apoio, sem substituir julgamento médico.")
        return lines.joined(separator: "\n")
    }

    private static func riskFromMetrics(recent: [DailyCheckIn], moodTrend: Double, anxietyTrend: Double, sleepTrend: Double, averageSleep: Double, adherence: Double) -> ClinicalRiskLevel {
        guard let latest = recent.first else {
            return .low
        }

        if latest.suicidalIdeation || latest.mood <= 1 || latest.anxiety >= 4.5 {
            return .high
        }

        if moodTrend < -0.35 || anxietyTrend > 0.35 || sleepTrend < -0.35 || averageSleep < 5.5 || adherence < 0.8 || latest.mood <= 2 || latest.anxiety >= 3.5 {
            return .moderate
        }

        return .low
    }

    private static func riskFromAssessments(_ assessments: [ScaleAssessment]) -> ClinicalRiskLevel {
        let latestByScale = Dictionary(grouping: assessments, by: \.scaleName).compactMap { $0.value.max { $0.date < $1.date } }

        if latestByScale.contains(where: { assessment in
            (assessment.scaleName == ScaleKind.phq9.rawValue && assessment.score >= 20) ||
            (assessment.scaleName == ScaleKind.gad7.rawValue && assessment.score >= 15) ||
            (assessment.scaleName == ScaleKind.ymrs.rawValue && assessment.score >= 22)
        }) {
            return .high
        }

        if latestByScale.contains(where: { assessment in
            (assessment.scaleName == ScaleKind.phq9.rawValue && assessment.score >= 10) ||
            (assessment.scaleName == ScaleKind.gad7.rawValue && assessment.score >= 10) ||
            (assessment.scaleName == ScaleKind.ymrs.rawValue && assessment.score >= 13)
        }) {
            return .moderate
        }

        return .low
    }

    // Returns the ordinary least-squares slope (change per step) of `values`.
    // More robust than first-to-last delta: a single outlier at either end
    // no longer dominates the trend shown to clinicians.
    private static func trend(values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0 }

        let meanX = (n - 1) / 2          // mean of 0, 1, …, n-1
        let meanY = values.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for (i, y) in values.enumerated() {
            let dx = Double(i) - meanX
            numerator   += dx * (y - meanY)
            denominator += dx * dx
        }

        return denominator == 0 ? 0 : numerator / denominator
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +) / Double(values.count)
    }

    private static func adherence(in checkIns: [DailyCheckIn]) -> Double {
        guard !checkIns.isEmpty else {
            return 1
        }

        let taken = checkIns.filter(\.medicationTaken).count
        return Double(taken) / Double(checkIns.count)
    }

    private static func highest(_ levels: [ClinicalRiskLevel]) -> ClinicalRiskLevel {
        levels.max { $0.sortOrder < $1.sortOrder } ?? .low
    }
}
