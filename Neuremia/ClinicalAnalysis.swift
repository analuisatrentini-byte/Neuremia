//
//  ClinicalAnalysis.swift
//  Neuremia
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import Foundation

// N-M2: All clinical thresholds in one place with bibliographic references
// so that future regulatory audits can verify the basis for each decision.
enum ClinicalThresholds {
    // Trend thresholds (OLS slope per check-in, 14-day window)
    // Ref: CANMAT 2018 — clinically meaningful mood deterioration ≈ -0.5/week
    //      mapped to per-day slope over 14 records.
    static let moodDeclinePerRecord: Double = -0.35
    static let anxietyIncreasePerRecord: Double = 0.35
    static let sleepDeclinePerRecord: Double = -0.35

    // Absolute metric thresholds
    // Ref: Hirshkowitz et al. 2015 (NSF) — <6h associated with impaired function.
    static let minimumSleepHours: Double = 5.5
    // Ref: CANMAT 2018 — medication adherence <80% correlates with relapse risk.
    static let medicationAdherenceMinimum: Double = 0.8

    // Real-time check-in thresholds (0–5 scale)
    static let moodHighRisk: Double = 1.0      // score ≤ 1 → high
    static let moodModerateRisk: Double = 2.0  // score ≤ 2 → moderate
    static let anxietyHighRisk: Double = 4.5   // score ≥ 4.5 → high
    static let anxietyModerateRisk: Double = 3.5 // score ≥ 3.5 → moderate

    // Scale score thresholds
    // Ref: Kroenke et al. 2001 (PHQ-9) — score ≥20 = severe depression.
    static let phq9High: Int = 20
    static let phq9Moderate: Int = 10
    // Ref: Spitzer et al. 2006 (GAD-7) — score ≥15 = severe anxiety.
    static let gad7High: Int = 15
    static let gad7Moderate: Int = 10
    // Ref: Young et al. 1978 (YMRS) — score ≥22 = moderate-severe mania.
    static let ymrsHigh: Int = 22
    static let ymrsModerate: Int = 13
}

enum ClinicalAnalysis {
    static func score(for scale: ScaleKind, answers: [Int]) -> Int {
        // Clamp every answer to its declared range before summing so that
        // out-of-bounds data never inflates the score.
        // YMRS: items at indices 4,5,7,8 are 0–8; all others 0–4 → max 60.
        // PHQ-9: all items 0–3 → max 27.
        // GAD-7: all items 0–3 → max 21.
        answers.prefix(scale.questions.count).enumerated().reduce(0) { total, pair in
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

    // N-M1: returns true if `term` appears in `text` at a position that is NOT
    // immediately preceded by a negation word. Handles two negation patterns:
    //   1. Verb negators (não, nunca, jamais, impossível) — look back up to 3 tokens
    //      to handle "eu não vou me matar".
    //   2. Absence markers (sem) — "sem esperança" means the positive term "esperança"
    //      is ABSENT, so "sem" must be treated as a negator only when it PRECEDES the
    //      term immediately (within 2 tokens), preventing false alerts on phrases like
    //      "estou sem saída" where "sem saída" is itself a high-risk term.
    private static func termPresent(_ term: String, in text: String) -> Bool {
        guard text.contains(term) else { return false }
        let verbNegators = ["nao", "nunca", "jamais", "impossivel"]
        let absenceMarkers = ["sem"]
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, range: searchRange) {
            let before = String(text[text.startIndex..<range.lowerBound])
            let tokens = before.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let lastThree = tokens.suffix(3)
            let lastTwo = tokens.suffix(2)
            let negated = lastThree.contains(where: { verbNegators.contains($0) })
                || lastTwo.contains(where: { absenceMarkers.contains($0) })
            if !negated {
                return true
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
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
        let detectedHighRiskTerms = highRiskTerms.filter { termPresent($0, in: normalized) }
        let detectedModerateRiskTerms = moderateRiskTerms.filter { termPresent($0, in: normalized) }

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
        let episodeForecasts = detectEpisodeForecasts(
            allCheckIns: checkIns.sorted { $0.date < $1.date },
            recent: chronological,
            assessments: assessments,
            textAssessment: textAssessment,
            moodTrend: moodTrend,
            anxietyTrend: anxietyTrend,
            sleepTrend: sleepTrend,
            adherence: medicationAdherence
        )
        let temporalPrediction = TemporalRiskModel.predict(
            checkIns: checkIns,
            assessments: assessments,
            episodeForecasts: episodeForecasts,
            textAssessment: textAssessment
        )
        let dailyRecommendation = recommendation(from: episodeForecasts)

        var signals: [String] = []

        if moodTrend < ClinicalThresholds.moodDeclinePerRecord {
            signals.append("Humor em queda nos registros recentes")
        }

        if anxietyTrend > ClinicalThresholds.anxietyIncreasePerRecord {
            signals.append("Ansiedade em elevação")
        }

        if averageSleep > 0 && averageSleep < ClinicalThresholds.minimumSleepHours {
            signals.append("Sono médio abaixo de 5h30")
        }

        if sleepTrend < ClinicalThresholds.sleepDeclinePerRecord {
            signals.append("Sono em queda nos registros recentes")
        }

        if medicationAdherence < ClinicalThresholds.medicationAdherenceMinimum && !recent.isEmpty {
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
        signals.append(contentsOf: episodeForecasts.prefix(3).map { "\($0.kind.rawValue): \($0.drivers.prefix(2).joined(separator: ", "))" })

        let metricRisk = riskFromMetrics(recent: recent, moodTrend: moodTrend, anxietyTrend: anxietyTrend, sleepTrend: sleepTrend, averageSleep: averageSleep, adherence: medicationAdherence)
        let episodeRisk = highest(episodeForecasts.map(\.level))
        let riskLevel = highest([metricRisk, textRisk, scaleRisk, episodeRisk])
        let clinicalDigest = dailyDigest(
            recent: recent,
            assessments: assessments,
            riskLevel: riskLevel,
            temporalPrediction: temporalPrediction,
            episodeForecasts: episodeForecasts,
            textAssessment: textAssessment,
            adherence: medicationAdherence
        )

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
            signals: signals,
            episodeForecasts: episodeForecasts,
            temporalPrediction: temporalPrediction,
            clinicalDigest: clinicalDigest,
            dailyRecommendation: dailyRecommendation
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
            "Relatório clínico Neuremia",
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
            "Predição 7 dias: \(summary.temporalPrediction.sevenDayRiskScore)/100 (\(summary.temporalPrediction.sevenDayLevel.rawValue))",
            "Predição 14 dias: \(summary.temporalPrediction.fourteenDayRiskScore)/100 (\(summary.temporalPrediction.fourteenDayLevel.rawValue))",
            "Modelo preditivo: \(summary.temporalPrediction.source.rawValue) \(summary.temporalPrediction.modelVersion), confiança \(String(format: "%.0f", summary.temporalPrediction.confidence * 100))%",
            "Digest clínico: \(summary.clinicalDigest.title) — \(summary.clinicalDigest.recommendedClinicianAction)",
            "Recomendação do dia: \(summary.dailyRecommendation.action)",
            "Episódios monitorados: \(summary.episodeForecasts.isEmpty ? "sem episódio prioritário" : summary.episodeForecasts.map { "\($0.kind.rawValue) \($0.level.rawValue)" }.joined(separator: "; "))",
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

    private static func detectEpisodeForecasts(
        allCheckIns: [DailyCheckIn],
        recent: [DailyCheckIn],
        assessments: [ScaleAssessment],
        textAssessment: TextRiskAssessment,
        moodTrend: Double,
        anxietyTrend: Double,
        sleepTrend: Double,
        adherence: Double
    ) -> [ClinicalEpisodeForecast] {
        guard !recent.isEmpty else { return [] }

        let latest = recent.last
        let latestYMRS = latestScore(.ymrs, in: assessments)
        let latestPHQ9 = latestScore(.phq9, in: assessments)
        let latestGAD7 = latestScore(.gad7, in: assessments)
        let recentAverageSleep = average(recent.suffix(5).map(\.sleepHours))
        let comparison = previousEpisodeComparison(allCheckIns: allCheckIns, recent: recent)
        var forecasts: [ClinicalEpisodeForecast] = []

        if let latest, latest.suicidalIdeation || textAssessment.level == .high || latestPHQ9 >= ClinicalThresholds.phq9High {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .suicideRisk,
                level: .high,
                confidence: textAssessment.level == .high || latest.suicidalIdeation ? 0.92 : 0.78,
                window: "24h",
                drivers: ["triagem/texto de segurança alterado", "PHQ-9 ou humor recente exige revisão"],
                comparison: comparison
            ))
        }

        if let latest {
            let activationPattern = latest.sleepHours <= 5.5 && (latest.energy >= 4 || latest.irritability >= 4)
            let scaleOrTrendPattern = latestYMRS >= ClinicalThresholds.ymrsModerate || (latest.sleepHours <= 5.5 && sleepTrend < -0.25)
            if activationPattern || scaleOrTrendPattern {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .maniaProdrome,
                level: latestYMRS >= ClinicalThresholds.ymrsHigh || latest.sleepHours < 5 ? .high : .moderate,
                confidence: min(0.9, 0.55 + max(0, latest.energy - 3) * 0.08 + max(0, 6 - latest.sleepHours) * 0.07),
                window: "24-72h",
                drivers: ["sono reduzido", "energia/irritabilidade elevadas", "YMRS ou tendência circadiana alterada"],
                comparison: comparison
            ))
            }
        }

        if moodTrend < ClinicalThresholds.moodDeclinePerRecord || latestPHQ9 >= ClinicalThresholds.phq9Moderate {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .depressiveRelapse,
                level: latestPHQ9 >= ClinicalThresholds.phq9High ? .high : .moderate,
                confidence: min(0.88, 0.5 + abs(moodTrend) * 0.45 + Double(max(latestPHQ9 - 9, 0)) / 60),
                window: "3-7 dias",
                drivers: ["humor em queda", "PHQ-9 alterado", "energia/sono podem estar piorando"],
                comparison: comparison
            ))
        }

        if anxietyTrend > ClinicalThresholds.anxietyIncreasePerRecord || latestGAD7 >= ClinicalThresholds.gad7Moderate || latest?.anxiety ?? 0 >= ClinicalThresholds.anxietyModerateRisk {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .anxietyCrisis,
                level: latestGAD7 >= ClinicalThresholds.gad7High || (latest?.anxiety ?? 0) >= ClinicalThresholds.anxietyHighRisk ? .high : .moderate,
                confidence: min(0.9, 0.52 + max(0, anxietyTrend) * 0.35 + Double(max(latestGAD7 - 7, 0)) / 55),
                window: "24-72h",
                drivers: ["ansiedade em elevação", "GAD-7 ou ansiedade diária alterados", "gatilhos recentes devem ser revisados"],
                comparison: comparison
            ))
        }

        if adherence < ClinicalThresholds.medicationAdherenceMinimum, recent.count >= 3 {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .lowAdherence,
                level: adherence < 0.55 ? .high : .moderate,
                confidence: min(0.9, 0.45 + (1 - adherence) * 0.65),
                window: "esta semana",
                drivers: ["adesão abaixo de 80%", "risco de recaída aumenta quando falhas se repetem"],
                comparison: nil
            ))
        }

        if sleepTrend < ClinicalThresholds.sleepDeclinePerRecord || recentAverageSleep < ClinicalThresholds.minimumSleepHours {
            forecasts.append(ClinicalEpisodeForecast(
                kind: .circadianShift,
                level: recentAverageSleep < 5 ? .high : .moderate,
                confidence: min(0.86, 0.5 + abs(sleepTrend) * 0.45 + max(0, 6 - recentAverageSleep) * 0.08),
                window: "2-5 dias",
                drivers: ["sono médio baixo", "queda progressiva do sono"],
                comparison: comparison
            ))
        }

        return forecasts
            .sorted {
                if $0.level.sortOrder == $1.level.sortOrder {
                    return $0.confidence > $1.confidence
                }
                return $0.level.sortOrder > $1.level.sortOrder
            }
    }

    private static func recommendation(from forecasts: [ClinicalEpisodeForecast]) -> ClinicalDailyRecommendation {
        guard let forecast = forecasts.first else {
            return .fallback
        }

        switch forecast.kind {
        case .suicideRisk:
            return ClinicalDailyRecommendation(
                id: "safety-plan",
                title: "Plano de segurança agora",
                action: "Avise uma pessoa de confiança e mantenha meios de risco afastados hoje.",
                rationale: "Há sinal de segurança prioritário; a recomendação precisa reduzir risco imediato antes de qualquer meta de rotina.",
                targetSignal: forecast.kind.rawValue,
                expectedWindow: forecast.window
            )
        case .maniaProdrome, .circadianShift:
            return ClinicalDailyRecommendation(
                id: "protect-sleep-window",
                title: "Proteger sono hoje",
                action: "Reduza estímulos à noite e combine uma janela fixa para dormir.",
                rationale: "Sono reduzido ou irregular é um sinal sensível para virada de humor e alteração circadiana.",
                targetSignal: forecast.kind.rawValue,
                expectedWindow: forecast.window
            )
        case .depressiveRelapse:
            return ClinicalDailyRecommendation(
                id: "minimum-activation",
                title: "Ativação mínima",
                action: "Escolha uma tarefa pequena de 10 minutos e registre como ficou depois.",
                rationale: "Quando humor cai, uma ação pequena e mensurável ajuda o app a acompanhar resposta nos dias seguintes.",
                targetSignal: forecast.kind.rawValue,
                expectedWindow: forecast.window
            )
        case .anxietyCrisis:
            return ClinicalDailyRecommendation(
                id: "grounding-breath",
                title: "Reduzir ativação",
                action: "Faça 3 minutos de respiração lenta ou aterramento antes de dormir.",
                rationale: "Ansiedade em alta responde melhor quando a ação reduz ativação fisiológica e é fácil de repetir.",
                targetSignal: forecast.kind.rawValue,
                expectedWindow: forecast.window
            )
        case .lowAdherence:
            return ClinicalDailyRecommendation(
                id: "medication-check",
                title: "Checar medicação",
                action: "Confirme o horário da medicação e deixe um lembrete visível para hoje.",
                rationale: "A baixa adesão recorrente aumenta risco de recaída; a intervenção precisa reduzir esquecimento e fricção.",
                targetSignal: forecast.kind.rawValue,
                expectedWindow: forecast.window
            )
        }
    }

    private static func dailyDigest(
        recent: [DailyCheckIn],
        assessments: [ScaleAssessment],
        riskLevel: ClinicalRiskLevel,
        temporalPrediction: TemporalRiskPrediction,
        episodeForecasts: [ClinicalEpisodeForecast],
        textAssessment: TextRiskAssessment,
        adherence: Double
    ) -> ClinicalDailyDigest {
        let priorityScore = max(
            temporalPrediction.primaryScore,
            riskLevel.sortOrder == 2 ? 80 : riskLevel.sortOrder == 1 ? 48 : 18
        )
        let latest = recent.first
        let title: String
        let action: String

        if textAssessment.level == .high || latest?.suicidalIdeation == true {
            title = "Revisão de segurança hoje"
            action = "Avaliar risco, plano de segurança e necessidade de contato ativo."
        } else if temporalPrediction.primaryLevel == .high {
            title = "Paciente no topo da fila"
            action = "Revisar sinais 7/14 dias antes da próxima consulta e considerar contato breve."
        } else if adherence < ClinicalThresholds.medicationAdherenceMinimum, !recent.isEmpty {
            title = "Checar adesão"
            action = "Confirmar barreiras de medicação antes que o padrão vire recaída."
        } else if episodeForecasts.contains(where: { $0.kind == .maniaProdrome || $0.kind == .circadianShift }) {
            title = "Monitorar sono e ativação"
            action = "Revisar sono, energia e irritabilidade nas próximas 48-72h."
        } else {
            title = "Acompanhamento de rotina"
            action = "Manter digest diário e revisar apenas se o score subir."
        }

        var auditTrail = [
            "Digest gerado por ClinicalAnalysis.summary.",
            "Predição temporal \(temporalPrediction.modelVersion): 7d \(temporalPrediction.sevenDayRiskScore)/100, 14d \(temporalPrediction.fourteenDayRiskScore)/100.",
            "Dados usados: \(recent.count) check-ins recentes, \(assessments.count) escalas, texto clínico triado localmente."
        ]
        if let topForecast = episodeForecasts.first {
            auditTrail.append("Pipeline priorizou \(topForecast.kind.rawValue) com \(Int((topForecast.confidence * 100).rounded()))% de confiança.")
        }

        let queueReason = temporalPrediction.drivers.first
            ?? episodeForecasts.first?.drivers.first
            ?? "sem driver crítico dominante"

        return ClinicalDailyDigest(
            generatedAt: Date(),
            priorityScore: priorityScore,
            priorityLevel: temporalPrediction.primaryLevel.sortOrder >= riskLevel.sortOrder ? temporalPrediction.primaryLevel : riskLevel,
            title: title,
            summary: "Prioridade \(priorityScore)/100 para \(temporalPrediction.primaryWindow). Motivo principal: \(queueReason).",
            patientQueueReason: queueReason,
            recommendedClinicianAction: action,
            auditTrail: auditTrail,
            consentScope: ["médico vinculado", "digest clínico", "push crítico se autorizado"]
        )
    }

    private static func latestScore(_ scale: ScaleKind, in assessments: [ScaleAssessment]) -> Int {
        assessments
            .filter { $0.scaleName == scale.rawValue }
            .max { $0.date < $1.date }?
            .score ?? 0
    }

    private static func previousEpisodeComparison(allCheckIns: [DailyCheckIn], recent: [DailyCheckIn]) -> String? {
        guard let latest = recent.last, allCheckIns.count >= 8 else { return nil }
        let current = ClinicalPatternVector(checkIn: latest)
        let earlier = allCheckIns.dropLast(recent.count)
        let matches = earlier.filter { $0.mood <= 2 || $0.anxiety >= 4 || $0.suicidalIdeation }
            .map { (checkIn: $0, score: current.similarity(to: ClinicalPatternVector(checkIn: $0))) }
            .filter { $0.score >= 0.72 }

        guard let best = matches.max(by: { $0.score < $1.score }) else {
            return "Sem episódio anterior suficientemente parecido."
        }

        let percent = Int((best.score * 100).rounded())
        return "Padrão \(percent)% parecido com episódio real anterior."
    }

    private static func riskFromMetrics(recent: [DailyCheckIn], moodTrend: Double, anxietyTrend: Double, sleepTrend: Double, averageSleep: Double, adherence: Double) -> ClinicalRiskLevel {
        guard let latest = recent.first else {
            return .low
        }

        if latest.suicidalIdeation
            || latest.mood <= ClinicalThresholds.moodHighRisk
            || latest.anxiety >= ClinicalThresholds.anxietyHighRisk {
            return .high
        }

        if moodTrend < ClinicalThresholds.moodDeclinePerRecord
            || anxietyTrend > ClinicalThresholds.anxietyIncreasePerRecord
            || sleepTrend < ClinicalThresholds.sleepDeclinePerRecord
            || averageSleep < ClinicalThresholds.minimumSleepHours
            || adherence < ClinicalThresholds.medicationAdherenceMinimum
            || latest.mood <= ClinicalThresholds.moodModerateRisk
            || latest.anxiety >= ClinicalThresholds.anxietyModerateRisk {
            return .moderate
        }

        return .low
    }

    private static func riskFromAssessments(_ assessments: [ScaleAssessment]) -> ClinicalRiskLevel {
        let latestByScale = Dictionary(grouping: assessments, by: \.scaleName).compactMap { $0.value.max { $0.date < $1.date } }

        if latestByScale.contains(where: { a in
            (a.scaleName == ScaleKind.phq9.rawValue && a.score >= ClinicalThresholds.phq9High) ||
            (a.scaleName == ScaleKind.gad7.rawValue && a.score >= ClinicalThresholds.gad7High) ||
            (a.scaleName == ScaleKind.ymrs.rawValue && a.score >= ClinicalThresholds.ymrsHigh)
        }) {
            return .high
        }

        if latestByScale.contains(where: { a in
            (a.scaleName == ScaleKind.phq9.rawValue && a.score >= ClinicalThresholds.phq9Moderate) ||
            (a.scaleName == ScaleKind.gad7.rawValue && a.score >= ClinicalThresholds.gad7Moderate) ||
            (a.scaleName == ScaleKind.ymrs.rawValue && a.score >= ClinicalThresholds.ymrsModerate)
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

    // Adherence is computed only over check-ins where the patient explicitly
    // recorded whether they took medication. Missing entries (days without a
    // check-in) are treated as "unknown", not as "medication not taken", to
    // avoid artificially deflating adherence when a patient skips logging.
    private static func adherence(in checkIns: [DailyCheckIn]) -> Double {
        guard !checkIns.isEmpty else { return 1 }
        let taken = checkIns.filter(\.medicationTaken).count
        return Double(taken) / Double(checkIns.count)
    }

    private static func highest(_ levels: [ClinicalRiskLevel]) -> ClinicalRiskLevel {
        levels.max { $0.sortOrder < $1.sortOrder } ?? .low
    }
}

private enum TemporalRiskModel {
    static func predict(
        checkIns: [DailyCheckIn],
        assessments: [ScaleAssessment],
        episodeForecasts: [ClinicalEpisodeForecast],
        textAssessment: TextRiskAssessment,
        now: Date = Date()
    ) -> TemporalRiskPrediction {
        let chronological = checkIns.sorted { $0.date < $1.date }
        let recent90 = Array(chronological.suffix(90))
        let recent14 = Array(chronological.suffix(14))
        let recent7 = Array(chronological.suffix(7))

        var score7 = 12.0
        var score14 = 14.0
        var drivers: [String] = []
        var evidence: [String] = []

        let moodSlope7 = trend(recent7.map(\.mood))
        let anxietySlope7 = trend(recent7.map(\.anxiety))
        let sleepSlope14 = trend(recent14.map(\.sleepHours))
        let energySlope7 = trend(recent7.map(\.energy))
        let irritabilitySlope7 = trend(recent7.map(\.irritability))
        let recentSleep = average(recent7.map(\.sleepHours))
        let adherence7 = adherence(recent7)
        let moodVolatility = volatility(recent14.map(\.mood))
        let anxietyVolatility = volatility(recent14.map(\.anxiety))

        if moodSlope7 <= -0.25 {
            let impact = min(abs(moodSlope7) * 26, 18)
            score7 += impact
            score14 += impact * 0.8
            drivers.append("humor em queda nos últimos 7 registros")
        }

        if anxietySlope7 >= 0.25 {
            let impact = min(anxietySlope7 * 24, 18)
            score7 += impact
            score14 += impact * 0.85
            drivers.append("ansiedade em aceleração recente")
        }

        if sleepSlope14 <= -0.18 || recentSleep < ClinicalThresholds.minimumSleepHours {
            let sleepDebt = max(0, ClinicalThresholds.minimumSleepHours - recentSleep)
            let impact = min(10 + sleepDebt * 5 + abs(sleepSlope14) * 18, 24)
            score7 += impact
            score14 += impact
            drivers.append("sono insuficiente ou circadiano em queda")
        }

        if adherence7 < ClinicalThresholds.medicationAdherenceMinimum, !recent7.isEmpty {
            let impact = min((1 - adherence7) * 30, 24)
            score7 += impact
            score14 += impact * 1.2
            drivers.append("adesão medicamentosa abaixo de 80%")
        }

        if energySlope7 >= 0.25 && irritabilitySlope7 >= 0.20 && recentSleep < 6.25 {
            score7 += 18
            score14 += 12
            drivers.append("ativação com pouco sono sugere pródromo de mania")
        }

        if moodVolatility >= 1.2 || anxietyVolatility >= 1.2 {
            score7 += 8
            score14 += 10
            drivers.append("alta variabilidade emocional no período")
        }

        let latestScores = latestScaleScores(assessments)
        if latestScores.phq9 >= ClinicalThresholds.phq9Moderate {
            let impact = Double(latestScores.phq9 - 8)
            score7 += min(impact, 18)
            score14 += min(impact * 1.1, 22)
            drivers.append("PHQ-9 recente alterado")
        }
        if latestScores.gad7 >= ClinicalThresholds.gad7Moderate {
            let impact = Double(latestScores.gad7 - 8)
            score7 += min(impact, 16)
            score14 += min(impact, 18)
            drivers.append("GAD-7 recente alterado")
        }
        if latestScores.ymrs >= ClinicalThresholds.ymrsModerate {
            let impact = Double(latestScores.ymrs - 10)
            score7 += min(impact * 1.2, 22)
            score14 += min(impact, 18)
            drivers.append("YMRS recente alterado")
        }

        if textAssessment.level == .high || recent7.contains(where: \.suicidalIdeation) {
            score7 = max(score7, 92)
            score14 = max(score14, 86)
            drivers.append("sinal de segurança prioritário")
        } else if textAssessment.level == .moderate {
            score7 += 12
            score14 += 10
            drivers.append("texto sugere sofrimento importante")
        }

        if let similarEpisode = previousEpisodeSimilarity(allCheckIns: recent90, currentWindow: recent14), similarEpisode.similarity >= 0.72 {
            let impact = (similarEpisode.similarity - 0.65) * 55
            score7 += impact
            score14 += impact * 1.15
            drivers.append("janela atual parecida com episódio anterior real")
            evidence.append("Similaridade com episódio anterior: \(Int((similarEpisode.similarity * 100).rounded()))%.")
        }

        let forecastBoost = episodeForecasts.reduce(0.0) { partial, forecast in
            partial + Double(forecast.level.sortOrder + 1) * forecast.confidence * 5
        }
        score7 += min(forecastBoost, 18)
        score14 += min(forecastBoost * 0.9, 16)

        evidence.append("Série longitudinal analisada: \(recent90.count) check-ins, \(assessments.count) escalas.")
        evidence.append("Janelas: 7 dias para risco agudo; 14 dias para recaída e padrão circadiano.")
        evidence.append("Entradas: sono, humor, ansiedade, energia, irritabilidade, medicação, texto, escalas e episódios prévios.")

        let bounded7 = boundedScore(score7)
        let bounded14 = boundedScore(score14)
        let confidence = confidence(sampleCount: recent90.count, assessmentCount: assessments.count, hasEpisodeMemory: evidence.contains { $0.contains("Similaridade") })
        let primaryWindow = bounded7 >= bounded14 ? "próximos 7 dias" : "próximos 14 dias"

        return TemporalRiskPrediction(
            generatedAt: now,
            source: .localFallback,
            modelVersion: "temporal-risk-local-v1",
            sevenDayRiskScore: bounded7,
            fourteenDayRiskScore: bounded14,
            sevenDayLevel: level(for: bounded7),
            fourteenDayLevel: level(for: bounded14),
            primaryWindow: primaryWindow,
            predictedEpisodes: Array(episodeForecasts.prefix(4)),
            drivers: Array(drivers.uniqued().prefix(5)),
            evidence: evidence,
            longitudinalSampleCount: recent90.count,
            confidence: confidence
        )
    }

    private static func latestScaleScores(_ assessments: [ScaleAssessment]) -> (phq9: Int, gad7: Int, ymrs: Int) {
        (
            phq9: latestScore(.phq9, in: assessments),
            gad7: latestScore(.gad7, in: assessments),
            ymrs: latestScore(.ymrs, in: assessments)
        )
    }

    private static func latestScore(_ scale: ScaleKind, in assessments: [ScaleAssessment]) -> Int {
        assessments
            .filter { $0.scaleName == scale.rawValue }
            .max { $0.date < $1.date }?
            .score ?? 0
    }

    private static func previousEpisodeSimilarity(allCheckIns: [DailyCheckIn], currentWindow: [DailyCheckIn]) -> (similarity: Double, date: Date)? {
        guard currentWindow.count >= 5, allCheckIns.count >= currentWindow.count + 5 else { return nil }
        let currentVector = ClinicalWindowVector(checkIns: currentWindow)
        let candidatePool = allCheckIns.dropLast(currentWindow.count)
        let candidates = candidatePool
            .filter { $0.mood <= 2 || $0.anxiety >= 4 || $0.suicidalIdeation }
            .map { checkIn in
                let window = allCheckIns.filter { $0.date <= checkIn.date }.suffix(currentWindow.count)
                return (date: checkIn.date, similarity: currentVector.similarity(to: ClinicalWindowVector(checkIns: Array(window))))
            }

        guard let best = candidates.max(by: { $0.similarity < $1.similarity }) else { return nil }
        return (best.similarity, best.date)
    }

    private static func trend(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard n >= 2 else { return 0 }
        let meanX = (n - 1) / 2
        let meanY = values.reduce(0, +) / n
        let numerator = values.enumerated().reduce(0.0) { partial, pair in
            partial + (Double(pair.offset) - meanX) * (pair.element - meanY)
        }
        let denominator = values.indices.reduce(0.0) { partial, index in
            partial + pow(Double(index) - meanX, 2)
        }
        return denominator == 0 ? 0 : numerator / denominator
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func adherence(_ checkIns: [DailyCheckIn]) -> Double {
        checkIns.isEmpty ? 1 : Double(checkIns.filter(\.medicationTaken).count) / Double(checkIns.count)
    }

    private static func volatility(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let mean = average(values)
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private static func boundedScore(_ score: Double) -> Int {
        Int(min(max(score.rounded(), 0), 100))
    }

    private static func level(for score: Int) -> ClinicalRiskLevel {
        if score >= 66 { return .high }
        if score >= 34 { return .moderate }
        return .low
    }

    private static func confidence(sampleCount: Int, assessmentCount: Int, hasEpisodeMemory: Bool) -> Double {
        let sampleComponent = min(Double(sampleCount) / 45, 1) * 0.45
        let scaleComponent = min(Double(assessmentCount) / 6, 1) * 0.25
        let episodeComponent = hasEpisodeMemory ? 0.2 : 0
        return min(0.95, 0.1 + sampleComponent + scaleComponent + episodeComponent)
    }
}

private struct ClinicalPatternVector {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let energy: Double
    let irritability: Double
    let medicationTaken: Bool

    init(checkIn: DailyCheckIn) {
        mood = checkIn.mood
        anxiety = checkIn.anxiety
        sleepHours = checkIn.sleepHours
        energy = checkIn.energy
        irritability = checkIn.irritability
        medicationTaken = checkIn.medicationTaken
    }

    func similarity(to other: ClinicalPatternVector) -> Double {
        closeness(mood, other.mood, range: 4) * 0.22
            + closeness(anxiety, other.anxiety, range: 4) * 0.22
            + closeness(sleepHours, other.sleepHours, range: 8) * 0.22
            + closeness(energy, other.energy, range: 4) * 0.14
            + closeness(irritability, other.irritability, range: 4) * 0.12
            + (medicationTaken == other.medicationTaken ? 0.08 : 0)
    }

    private func closeness(_ first: Double, _ second: Double, range: Double) -> Double {
        max(0, 1 - abs(first - second) / range)
    }
}

private struct ClinicalWindowVector {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let energy: Double
    let irritability: Double
    let adherence: Double

    init(checkIns: [DailyCheckIn]) {
        mood = Self.average(checkIns.map(\.mood))
        anxiety = Self.average(checkIns.map(\.anxiety))
        sleepHours = Self.average(checkIns.map(\.sleepHours))
        energy = Self.average(checkIns.map(\.energy))
        irritability = Self.average(checkIns.map(\.irritability))
        adherence = checkIns.isEmpty ? 1 : Double(checkIns.filter(\.medicationTaken).count) / Double(checkIns.count)
    }

    func similarity(to other: ClinicalWindowVector) -> Double {
        closeness(mood, other.mood, range: 4) * 0.20
            + closeness(anxiety, other.anxiety, range: 4) * 0.20
            + closeness(sleepHours, other.sleepHours, range: 8) * 0.20
            + closeness(energy, other.energy, range: 4) * 0.14
            + closeness(irritability, other.irritability, range: 4) * 0.14
            + closeness(adherence, other.adherence, range: 1) * 0.12
    }

    private func closeness(_ first: Double, _ second: Double, range: Double) -> Double {
        max(0, 1 - abs(first - second) / range)
    }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
