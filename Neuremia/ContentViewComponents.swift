//
//  ContentViewComponents.swift
//  Neuremia
//
//  Reusable View structs extracted from ContentView.swift (QC1).
//

import SwiftUI
import SwiftData
import Charts


struct CareFocusRiskWeights {
    let mood: Double
    let anxiety: Double
    let sleep: Double
    let medication: Double
    let triggers: Double
}

struct MoodWheelCard: View {
    @Binding var mood: Double
    @Binding var anxiety: Double
    @Binding var energy: Double

    private let emotions: [MoodWheelEmotion] = [
        MoodWheelEmotion(emoji: "😊", title: "Leve", mood: 5, anxiety: 1, energy: 4, color: .green),
        MoodWheelEmotion(emoji: "🙂", title: "Bem", mood: 4, anxiety: 2, energy: 3, color: .neuroYellow),
        MoodWheelEmotion(emoji: "😐", title: "Neutro", mood: 3, anxiety: 2, energy: 3, color: .gray),
        MoodWheelEmotion(emoji: "😟", title: "Ansioso", mood: 2, anxiety: 4, energy: 3, color: .orange),
        MoodWheelEmotion(emoji: "😔", title: "Triste", mood: 1, anxiety: 3, energy: 1, color: .blue),
        MoodWheelEmotion(emoji: "😠", title: "Irritado", mood: 2, anxiety: 4, energy: 4, color: .red)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Como você está agora?")
                        .font(.headline)
                    Text("Toque em uma emoção ou ajuste os sliders abaixo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // B3 — hide decorative emoji from VoiceOver; the card label below already
                // conveys the current state.
                Text(currentEmoji)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
            }

            CircularMoodWheel(emotions: emotions, mood: $mood, anxiety: $anxiety, energy: $energy)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.neuroYellow.opacity(0.28), Color.neuroGold.opacity(0.12), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.neuroGold.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // B3 — expose the card state as a single VoiceOver element so assistive
        // technology users get a concise summary before navigating into the wheel.
        .accessibilityLabel("Roda de humor. Estado atual: \(currentAccessibilityLabel).")
        .accessibilityHint("Deslize para cima ou para baixo para ajustar o humor. Acione dois vezes para abrir as opções de emoção.")
    }

    private var currentEmoji: String {
        if mood >= 4 && anxiety <= 2 { return "😊" }
        if mood <= 1.5 { return "😔" }
        if anxiety >= 4 { return "😟" }
        return "🙂"
    }

    private var currentAccessibilityLabel: String {
        let moodDesc: String
        switch mood {
        case 4...: moodDesc = "humor elevado"
        case 3..<4: moodDesc = "humor neutro"
        case 2..<3: moodDesc = "humor baixo"
        default:   moodDesc = "humor muito baixo"
        }
        let anxietyDesc = anxiety >= 4 ? ", ansiedade alta" : anxiety >= 3 ? ", ansiedade moderada" : ""
        return moodDesc + anxietyDesc
    }

}

struct MoodWheelEmotion: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let mood: Double
    let anxiety: Double
    let energy: Double
    let color: Color
}

struct CircularMoodWheel: View {
    let emotions: [MoodWheelEmotion]
    @Binding var mood: Double
    @Binding var anxiety: Double
    @Binding var energy: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(.systemBackground), Color.neuroYellow.opacity(0.22)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 132
                    )
                )
                .overlay {
                    Circle()
                        .stroke(
                            AngularGradient(
                                colors: [.neuroYellow, .neuroGold, .neuroOrange, .red, .blue, .green, .neuroYellow],
                                center: .center
                            ),
                            lineWidth: 5
                        )
                }
                .shadow(color: .orange.opacity(0.14), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(selectedEmoji)
                    .font(.system(size: 44))
                Text(selectedTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial)
            .clipShape(Circle())

            ForEach(Array(emotions.enumerated()), id: \.element.id) { index, emotion in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        mood = emotion.mood
                        anxiety = emotion.anxiety
                        energy = emotion.energy
                    }
                } label: {
                    let selected = isSelected(emotion)
                    let bgColor: Color = selected ? emotion.color.opacity(0.24) : Color(UIColor.secondarySystemGroupedBackground)
                    let strokeColor: Color = selected ? emotion.color : Color.clear
                    let shadowColor: Color = selected ? emotion.color.opacity(0.24) : Color.clear
                    VStack(spacing: 2) {
                        // B3 — emoji is decorative; the button label below handles VoiceOver.
                        Text(emotion.emoji)
                            .font(.title)
                            .accessibilityHidden(true)
                        Text(emotion.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 76, height: 62)
                    .background(bgColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(strokeColor, lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .scaleEffect(selected ? 1.08 : 1)
                    .shadow(color: shadowColor, radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .offset(offset(for: index))
                // B3 — clear label + selected state for each emotion button.
                .accessibilityLabel(emotion.title)
                .accessibilityHint("Humor \(Int(emotion.mood)), ansiedade \(Int(emotion.anxiety)), energia \(Int(emotion.energy))")
                .accessibilityAddTraits(isSelected(emotion) ? .isSelected : [])
            }

            // B3 — render the central display as a separate, non-interactive element
            // so VoiceOver announces the current state when focus lands on the wheel.
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Emoção selecionada: \(selectedTitle)")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 270)
        // B3 — announce the wheel as a group with adjustable trait so horizontal
        // swipe gestures work naturally in VoiceOver.
        .accessibilityElement(children: .contain)
    }

    private var selectedEmoji: String {
        emotions.first(where: { isSelected($0) })?.emoji ?? "🙂"
    }

    private var selectedTitle: String {
        emotions.first(where: { isSelected($0) })?.title ?? "Hoje"
    }

    private func isSelected(_ emotion: MoodWheelEmotion) -> Bool {
        abs(mood - emotion.mood) < 0.1 && abs(anxiety - emotion.anxiety) < 0.1
    }

    private func offset(for index: Int) -> CGSize {
        let angle = (Double(index) / Double(max(emotions.count, 1))) * 2 * Double.pi - Double.pi / 2
        let radius = 96.0
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

struct PatientEvolutionCard: View {
    let checkIns: [DailyCheckIn]
    let currentMood: Double
    let currentAnxiety: Double
    let currentIrritability: Double
    let currentSleep: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "chart.line.uptrend.xyaxis", title: "Minha evolução")

            Text("Um resumo simples para perceber mudanças antes que elas acumulem.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                MiniTrendCard(title: "Humor", icon: "face.smiling", values: recentValues(\.mood, fallback: currentMood), color: .neuroYellow, maxValue: 5)
                MiniTrendCard(title: "Ansiedade", icon: "waveform.path.ecg", values: recentValues(\.anxiety, fallback: currentAnxiety), color: .orange, maxValue: 5)
                MiniTrendCard(title: "Irritabilidade", icon: "exclamationmark.bubble", values: recentValues(\.irritability, fallback: currentIrritability), color: .red, maxValue: 5)
                MiniTrendCard(title: "Sono", icon: "moon.zzz", values: recentValues(\.sleepHours, fallback: currentSleep), color: .indigo, maxValue: 10)
            }
        }
        .panelStyle()
    }

    private func recentValues(_ keyPath: KeyPath<DailyCheckIn, Double>, fallback: Double) -> [Double] {
        let values = checkIns.prefix(7).reversed().map { $0[keyPath: keyPath] }
        return values.isEmpty ? [fallback] : values
    }
}

struct NeuremiaRiskSignatureCard: View {
    let signature: NeuremiaRiskSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "brain.head.profile", title: "Como você está em geral")
                    Text("Score próprio experimental, calculado a partir dos registros e sinais do app. As escalas oficiais continuam separadas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(signature.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(signature.level.rawValue)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(levelColor)
            }

            // P2-4 (UX): faixas de interpretação com ticks e labels abaixo
            // da barra — sem eles "34 pontos" não é interpretável para o
            // paciente. Leve 0-33 | Moderado 34-65 | Alto 66-100.
            VStack(spacing: 4) {
                ProgressView(value: Double(signature.score), total: 100)
                    .tint(levelColor)

                HStack(spacing: 0) {
                    Text("Leve")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Moderado")
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Alto")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Text(signature.explanation)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Label(signature.predictedWindow, systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(levelColor)

            Text(signature.baseline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !signature.baselineAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Desvio do seu padrão")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(signature.baselineAlerts.prefix(4), id: \.self) { alert in
                        Label(alert.capitalized, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption)
                            .foregroundStyle(levelColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(levelColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let similarCrisisPattern = signature.similarCrisisPattern {
                Label(similarCrisisPattern, systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(levelColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !signature.explanationDetails.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Por que o score mudou")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(signature.explanationDetails, id: \.self) { detail in
                        Label(detail, systemImage: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !signature.protectiveFactors.isEmpty {
                Text("Proteções: \(signature.protectiveFactors.prefix(3).joined(separator: ", ")).")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private var levelColor: Color {
        switch signature.level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct PatientPatternInsightCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let summary: LongitudinalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "sparkles.rectangle.stack", title: "Padrões precoces")

            Text("O app cruza diário, sono, sintomas, medicação e gatilhos para sugerir hipóteses de acompanhamento. Não é diagnóstico automático.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                InsightTile(icon: "arrow.down.right.circle", title: "O que está mudando", text: worseningInsight, tint: .orange)
                InsightTile(icon: "moon.zzz", title: "Sono x ansiedade", text: sleepBeforeAnxietyInsight, tint: .indigo)
                InsightTile(icon: "exclamationmark.triangle", title: "Antes de dias ruins", text: triggerInsight, tint: .red)
                InsightTile(icon: "arrow.triangle.branch", title: "Padrão parecido", text: similarAntecedentInsight, tint: .purple)
                InsightTile(icon: "pills", title: "Medicação x resposta", text: medicationInsight, tint: .green)
            }
        }
        .panelStyle()
    }

    private var worseningInsight: String {
        var findings: [String] = []
        if summary.moodTrend < -0.25 {
            findings.append("humor em queda")
        }
        if summary.anxietyTrend > 0.25 {
            findings.append("ansiedade em alta")
        }
        if summary.sleepTrend < -0.25 {
            findings.append("sono reduzindo")
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            findings.append("adesão irregular")
        }
        return findings.isEmpty ? "Sem piora consistente nos registros recentes." : findings.joined(separator: ", ").capitalized + "."
    }

    private var sleepBeforeAnxietyInsight: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        let pairs = zip(chronological, chronological.dropFirst())
        let matches = pairs.filter { previous, current in
            previous.sleepHours < 6 && current.anxiety >= 4
        }
        if matches.isEmpty {
            return "Ainda não há padrão claro de pouco sono antes de ansiedade alta."
        }
        return "Pouco sono apareceu antes de ansiedade alta em \(matches.count) registro(s)."
    }

    private var triggerInsight: String {
        let riskyDays = checkIns.filter { $0.mood <= 2 || $0.anxiety >= 4 || $0.suicidalIdeation }
        let triggers = riskyDays.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = mostFrequent(in: triggers) else {
            return "Com mais histórico, o app identifica gatilhos antes de dias ruins."
        }
        return "\(mostCommon) apareceu com mais frequência antes de dias de maior sofrimento."
    }

    private var medicationInsight: String {
        let changes = medicationPlans
            .map(\.changeNote)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !changes.isEmpty {
            return "Há mudança de dose/medicação registrada. Compare os próximos dias com humor, sono e ansiedade."
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            return "Adesão abaixo de 80%; vale observar relação com sintomas e efeitos colaterais."
        }
        return "Sem mudança de dose registrada nos dados locais."
    }

    private var similarAntecedentInsight: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard chronological.count >= 5, let latest = chronological.last else {
            return "Com mais histórico, o app compara o dia atual com padrões antes de crises anteriores."
        }

        let currentVector = CrisisAntecedentVector(
            mood: latest.mood,
            anxiety: latest.anxiety,
            sleepHours: latest.sleepHours,
            medicationTaken: latest.medicationTaken,
            triggers: Set(triggerLabels(from: latest.journalEntry))
        )
        var bestMatch: (daysBefore: Int, score: Double)?

        for index in chronological.indices {
            let crisis = chronological[index]
            guard crisis.mood <= 2 || crisis.anxiety >= 4 || crisis.suicidalIdeation else { continue }

            for offset in 1...7 {
                guard let antecedentIndex = chronological.index(index, offsetBy: -offset, limitedBy: chronological.startIndex) else {
                    continue
                }
                let antecedent = chronological[antecedentIndex]
                guard antecedent.date < latest.date else { continue }
                let antecedentVector = CrisisAntecedentVector(
                    mood: antecedent.mood,
                    anxiety: antecedent.anxiety,
                    sleepHours: antecedent.sleepHours,
                    medicationTaken: antecedent.medicationTaken,
                    triggers: Set(triggerLabels(from: antecedent.journalEntry))
                )
                let score = currentVector.similarity(to: antecedentVector)
                if score >= 0.72, score > (bestMatch?.score ?? 0) {
                    bestMatch = (offset, score)
                }
            }
        }

        guard let bestMatch else {
            return "Ainda não há episódio passado parecido o suficiente para comparação."
        }

        return "Hoje parece \(Int((bestMatch.score * 100).rounded()))% com um padrão que ocorreu \(bestMatch.daysBefore) dia(s) antes de piora anterior."
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }

    private func mostFrequent(in values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 })
            .mapValues(\.count)
            .max { $0.value < $1.value }?
            .key
    }
}

// MARK: - Early episode detection card
// Surfaces per-syndrome prodromal patterns (mania, depression, anxiety,
// suicide, adherence, circadian) with explicit evidence and severity.
// Backed by EpisodeRiskEngine which combines temporal windows with the
// user's personal baseline.
struct EpisodeRiskCard: View {
    let checkIns: [DailyCheckIn]

    private var signals: [EpisodeRiskSignal] {
        EpisodeRiskEngine.compute(from: checkIns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "sensor.tag.radiowaves.forward.fill", title: "Detecção precoce")

            Text("O app rastreia padrões prodrômicos (mania, depressão, ansiedade, adesão, ritmo circadiano) cruzando janela temporal com seu baseline pessoal. Não substitui avaliação médica.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let list = signals
            if list.isEmpty {
                clearState
            } else {
                VStack(spacing: 10) {
                    ForEach(list) { signal in
                        EpisodeRiskRow(signal: signal)
                    }
                }
            }
        }
        .panelStyle()
    }

    private var clearState: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sem padrão prodrômico ativo")
                    .font(.subheadline.weight(.semibold))
                Text("Nenhum sinal precoce de mania, depressão, ansiedade ou instabilidade circadiana nos últimos 14 dias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct EpisodeRiskRow: View {
    let signal: EpisodeRiskSignal

    private var tint: Color {
        switch signal.kind.tintName {
        case "orange": .orange
        case "indigo": .indigo
        case "red": .red
        case "pink": .pink
        case "yellow": .yellow
        case "teal": .teal
        default: .accentColor
        }
    }

    private var severityColor: Color {
        switch signal.severity {
        case .early: .yellow
        case .emerging: .orange
        case .active: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: signal.kind.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(signal.kind.label)
                        .font(.subheadline.weight(.semibold))
                    Text("Janela: últimos \(signal.windowDays) dia(s)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(signal.severity.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(severityColor.opacity(0.20))
                    .foregroundStyle(severityColor)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(signal.evidence, id: \.self) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text(signal.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Predictive episode card
// Turns the local temporal model into patient-facing copy: probability in the
// next 7 days, closest past antecedent window, and the metric forecasts driving it.
struct EpisodePredictionCard: View {
    let checkIns: [DailyCheckIn]

    private var prediction: EpisodePrediction {
        EpisodePredictionEngine.compute(from: checkIns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "crystal.ball.fill", title: "Predição 7 dias")
                    Text("Modelo temporal local sobre sua série longitudinal. Ele estima piora provável, não faz diagnóstico.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                probabilityBadge
            }

            switch prediction.state {
            case .warmingUp(let daysUntilReady):
                warmingUpState(daysUntilReady: daysUntilReady)
            case .noPastEpisodes:
                noPastEpisodesState
                forecastList
            case .ready:
                readyState
                forecastList
            }
        }
        .panelStyle()
    }

    @ViewBuilder
    private var probabilityBadge: some View {
        if let probability = prediction.probabilityWorsening7d, let band = prediction.riskBand {
            VStack(spacing: 2) {
                Text("\(Int((probability * 100).rounded()))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(band.label)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(bandColor)
            .accessibilityLabel("Probabilidade de piora nos próximos 7 dias: \(Int((probability * 100).rounded())) por cento. Risco \(band.label).")
        }
    }

    private var readyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let match = prediction.bestMatch {
                Text("Nos últimos 14 dias você tem um padrão \(match.similarityPercent)% semelhante ao que precedeu seu episódio de \(match.episodeLabel).")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Label("Naquele histórico, esse padrão apareceu \(match.daysBeforeEpisode) dia(s) antes de \(match.kind.label.lowercased()).", systemImage: match.kind.icon)
                    .font(.caption)
                    .foregroundStyle(bandColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Há episódios passados no histórico, mas nenhum antecedente ficou parecido o suficiente com os últimos 14 dias.")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bandColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var noPastEpisodesState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(bandColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sem episódio anterior para comparar")
                    .font(.subheadline.weight(.semibold))
                Text("A probabilidade vem só da projeção dos últimos 14 dias. Quando houver histórico de episódios, o app compara padrões antecedentes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bandColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func warmingUpState(daysUntilReady: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hourglass.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Predição em aquecimento")
                    .font(.subheadline.weight(.semibold))
                Text("Faltam cerca de \(daysUntilReady) dia(s) de histórico para estimar risco prospectivo com janela de 14 dias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var forecastList: some View {
        let meaningfulForecasts = prediction.forecasts
            .filter { $0.direction != .stable || $0.fitQuality >= 0.25 }
            .prefix(4)

        if !meaningfulForecasts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Projeção se a tendência continuar")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(Array(meaningfulForecasts)) { forecast in
                    ForecastRow(forecast: forecast)
                }
            }
        }
    }

    private var bandColor: Color {
        switch prediction.riskBand {
        case .high:
            .red
        case .moderate:
            .orange
        case .low:
            .green
        case .none:
            .secondary
        }
    }
}

private struct ForecastRow: View {
    let forecast: EpisodePrediction.MetricForecast

    private var tint: Color {
        switch forecast.direction {
        case .worsening:
            .orange
        case .improving:
            .green
        case .stable:
            .secondary
        }
    }

    private var directionIcon: String {
        switch forecast.direction {
        case .worsening:
            "arrow.up.forward.circle.fill"
        case .improving:
            "arrow.down.forward.circle.fill"
        case .stable:
            "minus.circle.fill"
        }
    }

    private var directionLabel: String {
        switch forecast.direction {
        case .worsening:
            "piorando"
        case .improving:
            "melhorando"
        case .stable:
            "estável"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: forecast.metric.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(forecast.metric.label)
                    .font(.caption.weight(.semibold))
                Text("\(forecast.metric.format(forecast.currentValue)) → \(forecast.metric.format(forecast.projected7d))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Label(directionLabel, systemImage: directionIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .labelStyle(.iconOnly)
                .accessibilityLabel(directionLabel)
        }
        .padding(10)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Personal baseline card
// Shows this user's *own* normal range for each metric plus how the current
// week compares to it in z-score space — replaces population thresholds with
// individual reference points.
struct PersonalBaselineCard: View {
    let checkIns: [DailyCheckIn]

    private var summary: PersonalBaselineEngine.Summary {
        PersonalBaselineEngine.compute(from: checkIns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "person.crop.circle.badge.checkmark", title: "Seu normal")

            Text("O app aprendeu seus valores típicos ao longo das últimas 8 semanas. Comparamos você com você mesmo — não com uma média populacional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let s = summary
            if s.warmingUp {
                warmingUpState(daysUntilReady: s.daysUntilReady)
            } else if s.baselines.isEmpty {
                notEnoughRecentState
            } else {
                VStack(spacing: 10) {
                    ForEach(s.baselines) { baseline in
                        PersonalBaselineRow(baseline: baseline)
                    }
                }
            }
        }
        .panelStyle()
    }

    private func warmingUpState(daysUntilReady: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hourglass.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Aprendendo seu padrão")
                    .font(.subheadline.weight(.semibold))
                Text(daysUntilReady > 0
                    ? "Faltam \(daysUntilReady) check-in(s) para o app ter uma referência confiável."
                    : "Mais alguns dias e sua linha de base fica pronta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var notEnoughRecentState: some View {
        Text("Faça check-in por 3 dias seguidos para comparar sua semana com seu padrão histórico.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EarlyDetectionBaselineBubble: View {
    let checkIns: [DailyCheckIn]

    private var signals: [EpisodeRiskSignal] {
        EpisodeRiskEngine.compute(from: checkIns)
    }

    private var baselineSummary: PersonalBaselineEngine.Summary {
        PersonalBaselineEngine.compute(from: checkIns)
    }

    private var focusBaselines: [PersonalBaseline] {
        let learned = baselineSummary.baselines
        let attention = learned.filter { $0.status != .normal }
        return attention.isEmpty ? Array(learned.prefix(2)) : Array(attention.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.neuroYellow.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.neuroNavy)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Detecção + seu normal")
                        .font(.headline.weight(.bold))
                    Text("Sinais precoces comparados ao seu padrão.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                signalBadge
            }

            HStack(spacing: 10) {
                statusTile(
                    icon: signals.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    title: "Agora",
                    value: signals.isEmpty ? "Estável" : "\(signals.count) sinal(is)",
                    tint: signals.isEmpty ? .green : .orange
                )

                statusTile(
                    icon: baselineSummary.warmingUp ? "hourglass.circle" : "person.crop.circle.badge.checkmark",
                    title: "Seu normal",
                    value: baselineValue,
                    tint: baselineTint
                )
            }

            compactDetails
        }
        .panelStyle()
        .accessibilityElement(children: .contain)
    }

    private var signalBadge: some View {
        Text(signals.isEmpty ? "OK" : "Atenção")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.neuroYellow)
            .foregroundStyle(Color.neuroNavy)
            .clipShape(Capsule())
    }

    private var baselineValue: String {
        if baselineSummary.warmingUp {
            return baselineSummary.daysUntilReady > 0 ? "Faltam \(baselineSummary.daysUntilReady)" : "Aprendendo"
        }
        if baselineSummary.baselines.isEmpty {
            return "Mais check-ins"
        }
        return focusBaselines.contains { $0.status != .normal } ? "Observar" : "No padrão"
    }

    private var baselineTint: Color {
        if baselineSummary.warmingUp || baselineSummary.baselines.isEmpty {
            return .secondary
        }
        return focusBaselines.contains { $0.status == .alert } ? .red : (focusBaselines.contains { $0.status == .watch } ? .yellow : .green)
    }

    @ViewBuilder
    private var compactDetails: some View {
        if signals.isEmpty && !baselineSummary.warmingUp && focusBaselines.allSatisfy({ $0.status == .normal }) {
            Label("Nenhum sinal precoce ativo. Continue registrando seus check-ins.", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.neuroNavy)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.neuroYellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(signals.prefix(2)) { signal in
                    compactSignalRow(signal)
                }

                if baselineSummary.warmingUp {
                    compactInfoRow(
                        icon: "hourglass.circle",
                        title: "Seu normal ainda está sendo aprendido",
                        detail: baselineSummary.daysUntilReady > 0 ? "Faltam \(baselineSummary.daysUntilReady) check-in(s)." : "Continue registrando por mais alguns dias.",
                        tint: .secondary
                    )
                } else if baselineSummary.baselines.isEmpty {
                    compactInfoRow(
                        icon: "calendar.badge.plus",
                        title: "Baseline sem comparação recente",
                        detail: "Faça check-in por 3 dias seguidos.",
                        tint: .secondary
                    )
                } else {
                    ForEach(focusBaselines) { baseline in
                        compactBaselineRow(baseline)
                    }
                }
            }
        }
    }

    private func statusTile(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.neuroNavy)
                .frame(width: 28, height: 28)
                .background(Color.neuroYellow.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.neuroNavy.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.neuroYellow.opacity(0.26), lineWidth: 1)
        }
    }

    private func compactSignalRow(_ signal: EpisodeRiskSignal) -> some View {
        compactInfoRow(
            icon: signal.kind.icon,
            title: signal.kind.label,
            detail: signal.severity.label,
            tint: severityColor(for: signal)
        )
    }

    private func compactBaselineRow(_ baseline: PersonalBaseline) -> some View {
        compactInfoRow(
            icon: baseline.metric.icon,
            title: baseline.metric.label,
            detail: baseline.status == .normal ? baseline.currentCopy : baseline.status.label,
            tint: statusColor(for: baseline)
        )
    }

    private func compactInfoRow(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.neuroNavy)
                .frame(width: 26, height: 26)
                .background(Color.neuroYellow.opacity(0.20), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func severityColor(for signal: EpisodeRiskSignal) -> Color {
        switch signal.severity {
        case .early:
            .yellow
        case .emerging:
            .orange
        case .active:
            .red
        }
    }

    private func statusColor(for baseline: PersonalBaseline) -> Color {
        switch baseline.status {
        case .normal:
            .green
        case .watch:
            .yellow
        case .alert:
            .red
        }
    }
}

struct RobustBiometricBaselineCard: View {
    let checkIns: [DailyCheckIn]
    let currentHRV: Double
    let globalHRVBaseline: Double
    let hrvContextData: String
    let currentSleepHours: Double
    let medicationTaken: Bool
    let ppgStress: Double
    let activeTriggers: [String]

    private var summary: BiometricBaselineSummary {
        BiometricBaselineEngine.compute(
            checkIns: checkIns,
            currentHRV: currentHRV,
            globalHRVBaseline: globalHRVBaseline,
            hrvStore: HRVContextBaselineStore.decode(from: hrvContextData),
            currentSleepHours: currentSleepHours,
            medicationTaken: medicationTaken,
            ppgStress: ppgStress,
            activeTriggers: activeTriggers
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "waveform.path.ecg.rectangle", title: "Baseline biométrico")

            Text(summary.readinessText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(summary.items) { item in
                    BiometricBaselineRow(item: item)
                }
            }

            if !summary.responsePatterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resposta individual")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(summary.responsePatterns) { insight in
                        Label("\(insight.antecedent), \(insight.consequent) \(Int(abs(insight.deltaPercent).rounded()))% (n=\(insight.sampleSize)).", systemImage: insight.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .panelStyle()
    }
}

private struct BiometricBaselineRow: View {
    let item: BiometricBaselineSummary.Item

    private var color: Color {
        switch item.status {
        case .stable:
            .green
        case .watch:
            .orange
        case .alert:
            .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(item.value)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct PersonalBaselineRow: View {
    let baseline: PersonalBaseline

    private var tint: Color {
        switch baseline.metric.tintName {
        case "indigo": .indigo
        case "purple": .purple
        case "teal": .teal
        case "orange": .orange
        case "red": .red
        default: .accentColor
        }
    }

    private var statusColor: Color {
        switch baseline.status {
        case .normal: .green
        case .watch: .yellow
        case .alert: .red
        }
    }

    private var driftLine: String? {
        // Only surface drift when the baseline itself is trending in the
        // concerning direction fast enough to matter (~0.5 units over 30 days).
        let concerningDrift = baseline.metric.higherIsWorse
            ? baseline.driftPerDay
            : -baseline.driftPerDay
        guard concerningDrift > 0.017 else { return nil }        // ~ +0.5 in 30d
        let perMonth = concerningDrift * 30
        let verb = baseline.metric.higherIsWorse ? "subindo" : "caindo"
        let unit = baseline.metric.unit
        return String(format: "Sua linha de base está %@ ~%.1f%@ por mês.", verb, abs(perMonth), unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: baseline.metric.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(baseline.metric.label)
                        .font(.subheadline.weight(.semibold))
                    Text(baseline.centerCopy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(baseline.status.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.18))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }

            BaselineRangeIndicator(baseline: baseline, tint: tint)

            Text(baseline.currentCopy)
                .font(.caption)
                .foregroundStyle(.primary)

            if let driftLine {
                Label(driftLine, systemImage: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Horizontal bar: shaded band = ±1σ around center, marker = current week.
/// Renders in z-score space clamped to ±3σ so extreme weeks stay visible.
private struct BaselineRangeIndicator: View {
    let baseline: PersonalBaseline
    let tint: Color

    private let range: ClosedRange<Double> = -3...3

    private var markerFraction: CGFloat {
        let clamped = min(max(baseline.zScore, range.lowerBound), range.upperBound)
        let normalized = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(normalized)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 8)

                // ±1σ personal-normal band, centered visually on 0.
                Capsule()
                    .fill(tint.opacity(0.30))
                    .frame(width: width / 3.0, height: 8)   // 2σ span of a 6σ range
                    .offset(x: width / 3.0)                 // starts at -1σ

                // Current-week marker.
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle().stroke(Color.white, lineWidth: 2)
                    }
                    .offset(x: markerFraction * width - 7)
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Causal insights card
// Surfaces quantitative "antecedent → consequent" patterns, e.g.
// "When you sleep <6h for 2 days, anxiety rises 28% next day". Backed by
// CausalInsightsEngine which runs on the in-memory check-in window.
struct CausalInsightsCard: View {
    let checkIns: [DailyCheckIn]

    private var insights: [CausalInsight] {
        CausalInsightsEngine.compute(from: checkIns)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "link.circle.fill", title: "Relações que aparecem nos seus dados")

            Text("O app compara hábitos e sintomas dos últimos 60 dias e destaca só relações estatisticamente relevantes. Não substitui avaliação clínica.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if insights.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(insights.prefix(4)) { insight in
                        CausalInsightRow(insight: insight)
                    }
                }
            }
        }
        .panelStyle()
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.dots.scatter")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Faça check-ins por pelo menos 2 semanas seguidas para o app identificar relações confiáveis entre sono, medicação e sintomas.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CausalInsightRow: View {
    let insight: CausalInsight

    private var tint: Color {
        switch insight.tintName {
        case "indigo": .indigo
        case "purple": .purple
        case "green": .green
        case "mint": .mint
        case "orange": .orange
        case "teal": .teal
        case "red": .red
        default: .accentColor
        }
    }

    private var deltaLabel: String {
        let sign = insight.deltaPercent >= 0 ? "+" : ""
        return "\(sign)\(Int(insight.deltaPercent.rounded()))%"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: insight.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                let styledDelta = Text("\(deltaLabel) no dia seguinte")
                    .foregroundStyle(tint)
                    .fontWeight(.semibold)
                Text("\(insight.antecedent), \(insight.consequent) em média \(styledDelta).")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: insight.direction.arrow)
                        .font(.caption2.weight(.bold))
                    Text(insight.confidence.label)
                    Text("·")
                    Text("\(insight.sampleSize) ocorrência\(insight.sampleSize == 1 ? "" : "s")")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(insight.recommendation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct InsightTile: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AppointmentEventCard: View {
    @Binding var appointmentDate: Date
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.badge.clock", title: "Próxima consulta")

            DatePicker("Data da consulta", selection: $appointmentDate, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)

            TextField("Observação para lembrar na consulta", text: $note)
                .textFieldStyle(.roundedBorder)

            Text("A consulta registrada aparece como evento na linha do tempo clínica.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

struct ClinicalTimelineCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let appointmentDate: Date
    let appointmentNote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "timeline.selection", title: "Linha do tempo clínica")

            if events.isEmpty {
                EmptyState(text: "Com mais registros, eventos importantes aparecem aqui automaticamente.")
            } else {
                ForEach(events.prefix(8)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.icon)
                            .foregroundStyle(event.color)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(event.color.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }

    private var events: [ClinicalTimelineEvent] {
        var items: [ClinicalTimelineEvent] = []

        items.append(
            ClinicalTimelineEvent(
                date: appointmentDate,
                icon: "calendar.badge.clock",
                title: "Consulta agendada",
                detail: appointmentNote.isEmpty ? appointmentDate.formatted(date: .abbreviated, time: .shortened) : appointmentNote,
                color: .blue
            )
        )

        for plan in medicationPlans where !plan.changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(ClinicalTimelineEvent(date: plan.createdAt, icon: "pills", title: "Mudança de medicação", detail: plan.changeNote, color: .green))
        }

        for checkIn in checkIns {
            if checkIn.suicidalIdeation {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "exclamationmark.triangle", title: "Sinal de segurança", detail: "Triagem marcou necessidade de atenção imediata.", color: .red))
            } else if checkIn.mood <= 2 || checkIn.anxiety >= 4 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "waveform.path.ecg", title: "Dia de maior sofrimento", detail: "Humor \(String(format: "%.0f", checkIn.mood))/5, ansiedade \(String(format: "%.0f", checkIn.anxiety))/5.", color: .orange))
            }

            if !checkIn.medicationTaken {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "pills.circle", title: "Medicação pendente/parcial", detail: "Registro de adesão incompleta no dia.", color: .orange))
            }

            if checkIn.sleepHours < 6 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "moon.zzz", title: "Alteração de sono", detail: "Sono registrado abaixo de 6 horas.", color: .indigo))
            }

            if checkIn.mood >= 4 && checkIn.anxiety <= 2 && checkIn.sleepHours >= 7 {
                items.append(ClinicalTimelineEvent(date: checkIn.date, icon: "checkmark.seal", title: "Dia de estabilidade", detail: "Humor preservado, ansiedade baixa e sono adequado.", color: .green))
            }
        }

        return items.sorted { $0.date > $1.date }
    }
}

struct ClinicalTimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let icon: String
    let title: String
    let detail: String
    let color: Color
}

struct DigitalPhenotypeCard: View {
    let checkIns: [DailyCheckIn]
    let medicationPlans: [MedicationPlanEntry]
    let signature: NeuremiaRiskSignature
    let ppgStress: Double
    let ppgQuality: Double
    let voicePauseRatio: Double
    let typingSpeed: Double
    let healthSleepHours: Double
    let healthSteps: Int
    let healthHeartRate: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.text.rectangle", title: "Fenótipo digital")

            Text("Perfil longitudinal individual, ainda experimental, para entender padrões próprios do paciente.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 10)], spacing: 10) {
                InsightTile(icon: "moon.zzz", title: "Sono típico", text: sleepPattern, tint: .indigo)
                InsightTile(icon: "waveform.path.ecg", title: "Ansiedade típica", text: anxietyPattern, tint: .orange)
                InsightTile(icon: "tag", title: "Gatilho recorrente", text: triggerPattern, tint: .red)
                InsightTile(icon: "pills", title: "Resposta à medicação", text: medicationPattern, tint: .green)
                InsightTile(icon: "heart.circle", title: "PPG", text: ppgPattern, tint: .pink)
                InsightTile(icon: "mic.circle", title: "Voz", text: voicePattern, tint: .purple)
                InsightTile(icon: "keyboard", title: "Digitação", text: typingPattern, tint: .teal)
                InsightTile(icon: "figure.walk.circle", title: "Apple Health", text: healthPattern, tint: .blue)
            }

            Text("Assinatura atual: \(signature.level.rawValue.lowercased()) (\(signature.score)/100).")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var sleepPattern: String {
        guard !checkIns.isEmpty else { return "Ainda sem histórico suficiente." }
        let average = checkIns.prefix(14).map(\.sleepHours).reduce(0, +) / Double(min(checkIns.count, 14))
        return "Média recente de \(String(format: "%.1f", average))h."
    }

    private var anxietyPattern: String {
        guard !checkIns.isEmpty else { return "Ainda sem histórico suficiente." }
        let average = checkIns.prefix(14).map(\.anxiety).reduce(0, +) / Double(min(checkIns.count, 14))
        return "Média recente de \(String(format: "%.1f", average))/5."
    }

    private var triggerPattern: String {
        let triggers = checkIns.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = Dictionary(grouping: triggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }) else {
            return "Nenhum gatilho recorrente ainda."
        }
        return "\(mostCommon.key) aparece com mais frequência."
    }

    private var medicationPattern: String {
        if medicationPlans.contains(where: { !$0.changeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Há mudança cadastrada para acompanhar resposta."
        }
        let adherence = checkIns.isEmpty ? 0 : Double(checkIns.filter { $0.medicationTaken }.count) / Double(checkIns.count)
        return checkIns.isEmpty ? "Ainda sem adesão longitudinal." : "\(Int((adherence * 100).rounded()))% de adesão nos registros."
    }

    private var ppgPattern: String {
        guard ppgQuality > 0 else {
            return "Sem leitura PPG suficiente ainda."
        }
        if ppgQuality < 0.45 {
            return "Sinal fraco; repetir com dedo parado e flash coberto."
        }
        return "Ativação estimada \(Int((ppgStress * 100).rounded()))%, com qualidade \(Int((ppgQuality * 100).rounded()))%."
    }

    private var voicePattern: String {
        guard voicePauseRatio > 0 else {
            return "Sem amostra de voz ainda."
        }
        return "Pausas em \(Int((voicePauseRatio * 100).rounded()))% da amostra, sem salvar conteúdo."
    }

    private var typingPattern: String {
        guard typingSpeed > 0 else {
            return "Digite no diário para criar padrão."
        }
        return "\(Int(typingSpeed.rounded())) caracteres/min no app."
    }

    private var healthPattern: String {
        var parts: [String] = []
        if healthSleepHours > 0 {
            parts.append("sono \(String(format: "%.1f", healthSleepHours))h")
        }
        if healthSteps > 0 {
            parts.append("\(healthSteps) passos")
        }
        if healthHeartRate > 0 {
            parts.append("FC \(Int(healthHeartRate.rounded())) bpm")
        }
        return parts.isEmpty ? "Apple Health ainda sem dados sincronizados." : parts.joined(separator: " • ")
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }
}

struct MiniTrendCard: View {
    let title: String
    let icon: String
    let values: [Double]
    let color: Color
    let maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.75))
                        .frame(height: max(10, CGFloat(min(value / maxValue, 1)) * 54))
                }
            }
            .frame(height: 58, alignment: .bottom)

            Text(values.count == 1 ? "Hoje" : "Últimos \(values.count) registros")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct OfflineSyncStatusCard: View {
    let pendingCount: Int
    let lastStatus: String
    let localOnlyMode: Bool
    let retrySync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Sprint 22: ícone reflete o estado real. Sincronizado = nuvem
            // com check verde. Pendente = nuvem cortada laranja (cloud.slash)
            // — semânticamente "fora do alcance da nuvem agora".
            Image(systemName: localOnlyMode ? "lock.iphone" : (pendingCount == 0 ? "checkmark.icloud.fill" : "icloud.slash.fill"))
                .font(.headline)
                .foregroundStyle(localOnlyMode ? Color.neuroNavy : (pendingCount == 0 ? .green : Color.neuroOrange))
                .frame(width: 36, height: 36)
                .background(localOnlyMode ? Color.neuroYellow : (pendingCount == 0 ? Color.green : Color.neuroYellow).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(localOnlyMode ? "Dados apenas no aparelho" : (pendingCount == 0 ? "Dados protegidos" : "Aguardando sincronização"))
                    .font(.subheadline.weight(.bold))
                Text(lastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !localOnlyMode && pendingCount > 0 {
                Button(action: retrySync) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Tentar sincronizar novamente")
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BodySignalsIntroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.title2)
                    .foregroundStyle(Color.neuroNavy)
                    .frame(width: 44, height: 44)
                    .background(Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Check-in fisiológico")
                        .font(.headline)
                    Text("Área experimental para sinais associados ao estado autonômico, como pulso, HRV estimada, respiração indireta e perfusão.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Não mede humor diretamente e não substitui avaliação clínica. Estes dados ficam fora das escalas PHQ-9, GAD-7, YMRS e do cálculo de risco.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

struct BodySignalsReadingCard: View {
    let heartRate: Double
    let hrv: Double
    let respiration: Double
    let perfusion: Double
    let stress: Double
    let quality: Double
    let status: String
    let isMeasuring: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "sensor.tag.radiowaves.forward", title: "PPG pela câmera")

            VStack(alignment: .leading, spacing: 8) {
                Text("Cubra a câmera traseira e o flash com o dedo, mantenha parado por 30 segundos e evite frio, cafeína, exercício recente e pressão excessiva.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(action: start) {
                        Label(isMeasuring ? "Medindo..." : "Medir com câmera e flash", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMeasuring)

                    Button(action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isMeasuring)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Pulso", value: heartRate > 0 ? "\(Int(heartRate)) bpm" : "-", icon: "heart.fill", color: .red)
                BodySignalMetricPill(title: "HRV estimada", value: hrv > 0 ? "\(Int(hrv)) ms" : "-", icon: "point.3.connected.trianglepath.dotted", color: .teal)
                BodySignalMetricPill(title: "Respiração", value: respiration > 0 ? "\(Int(respiration))/min" : "-", icon: "lungs.fill", color: .indigo)
                BodySignalMetricPill(title: "Perfusão", value: perfusion > 0 ? String(format: "%.1f%%", perfusion) : "-", icon: "drop.fill", color: .blue)
                BodySignalMetricPill(title: "Estresse", value: stress > 0 ? "\(Int(stress))/100" : "-", icon: "bolt.heart.fill", color: .orange)
                BodySignalMetricPill(title: "Qualidade", value: quality > 0 ? "\(Int(quality * 100))%" : "-", icon: "checkmark.seal.fill", color: quality >= 0.45 ? .green : .orange)
            }

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

struct BodySignalMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct BodySignalsBehaviorCard: View {
    let typingLatency: Double
    let typingSpeed: Double
    let interactionCount: Int
    let sessionMinutes: Double
    let voiceAverage: Double
    let voicePauseRatio: Double
    let voiceVariability: Double
    let voicePitch: Double
    let voicePitchVariability: Double
    let voiceSyllableEnergy: Double
    let voiceRhythm: Double
    let voiceStatus: String
    let isRecording: Bool
    let startVoice: () -> Void
    let stopVoice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "keyboard", title: "Digitação e voz")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Latência", value: typingLatency > 0 ? "\(Int(typingLatency))s" : "-", icon: "timer", color: .purple)
                BodySignalMetricPill(title: "Velocidade", value: typingSpeed > 0 ? "\(Int(typingSpeed)) c/min" : "-", icon: "keyboard.fill", color: .teal)
                BodySignalMetricPill(title: "Interações", value: "\(interactionCount)", icon: "hand.tap.fill", color: .blue)
                BodySignalMetricPill(title: "Sessão", value: String(format: "%.1f min", sessionMinutes), icon: "iphone", color: .indigo)
                BodySignalMetricPill(title: "Voz", value: voiceAverage > 0 ? "\(Int(voiceAverage * 100))%" : "-", icon: "waveform", color: .orange)
                BodySignalMetricPill(title: "Pausas", value: voicePauseRatio > 0 ? "\(Int(voicePauseRatio * 100))%" : "-", icon: "pause.circle.fill", color: .gray)
                BodySignalMetricPill(title: "Pitch", value: voicePitch > 0 ? "\(Int(voicePitch)) Hz" : "-", icon: "music.quarternote.3", color: .purple)
                BodySignalMetricPill(title: "Variação vocal", value: voicePitchVariability > 0 ? "\(Int(voicePitchVariability)) Hz" : "-", icon: "waveform.path", color: .pink)
                BodySignalMetricPill(title: "Energia fala", value: voiceSyllableEnergy > 0 ? "\(Int(voiceSyllableEnergy * 100))%" : "-", icon: "speaker.wave.2.fill", color: .teal)
                BodySignalMetricPill(title: "Ritmo", value: voiceRhythm > 0 ? "\(Int(voiceRhythm))/min" : "-", icon: "metronome.fill", color: .blue)
            }

            HStack(spacing: 10) {
                Button(action: startVoice) {
                    Label(isRecording ? "Gravando..." : "Medir voz", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecording)

                Button(action: stopVoice) {
                    Image(systemName: "stop.fill")
                        .frame(width: 44)
                }
                .buttonStyle(.bordered)
                .disabled(!isRecording)
            }

            Text("Variação vocal: \(voiceVariability > 0 ? "\(Int(voiceVariability * 100))%" : "-"). \(voiceStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

struct CombinedBodySignalCard: View {
    let ppgStress: Double
    let signalQuality: Double
    let typingSpeed: Double
    let voicePauseRatio: Double
    let voiceVariability: Double
    let sleepHours: Double
    let steps: Int

    private var combinedIndex: Double {
        let sleepLoad = sleepHours > 0 ? max(0, 7 - sleepHours) * 10 : 12
        let inactivityLoad = steps > 0 ? max(0, 5000 - Double(steps)) / 100 : 10
        let typingLoad = typingSpeed > 0 ? min(max(220 - typingSpeed, 0) / 4, 25) : 8
        let voiceLoad = voicePauseRatio * 16 + voiceVariability * 12
        let qualityPenalty = signalQuality > 0 ? (1 - signalQuality) * 18 : 10
        let evidenceWeight = signalQuality >= 0.45 ? 1.0 : 0.55
        return min(max((ppgStress * 0.40 + sleepLoad + inactivityLoad + typingLoad + voiceLoad) * evidenceWeight + qualityPenalty, 0), 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "point.3.connected.trianglepath.dotted", title: "Modelo combinado experimental")

            HStack(spacing: 12) {
                Text("\(Int(combinedIndex))")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                    .frame(width: 82, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.headline)
                    Text("Combina PPG, sono, passos, digitação e voz. Modelo heurístico não validado; não entra no risco clínico nem nas escalas.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .panelStyle()
    }

    private var label: String {
        switch combinedIndex {
        case ..<35:
            "Baixa ativação autonômica"
        case ..<65:
            "Ativação intermediária"
        default:
            "Ativação elevada"
        }
    }

    private var color: Color {
        switch combinedIndex {
        case ..<35:
            .green
        case ..<65:
            .orange
        default:
            .red
        }
    }
}

struct BodySignalsSourcesCard: View {
    let sleepHours: Double
    let steps: Int
    let heartRate: Double
    let activeEnergy: Double
    let hrv: Double
    let restingHeartRate: Double
    let healthKitSnapshots: [HealthKitDailySnapshot]
    let lastSyncAt: Double
    let syncHealth: () -> Void

    private var latestSnapshot: HealthKitDailySnapshot? {
        healthKitSnapshots.sorted { $0.date > $1.date }.first
    }

    private var qualityText: String {
        guard let quality = latestSnapshot?.qualityScore else { return "-" }
        return "\(Int((quality * 100).rounded()))%"
    }

    private var circadianText: String {
        guard let score = latestSnapshot?.circadianRegularityScore else { return "-" }
        return "\(Int((score * 100).rounded()))%"
    }

    private var weeklyTrendText: String {
        let sorted = healthKitSnapshots.sorted { $0.date > $1.date }
        let recent = Array(sorted.prefix(7))
        let previous = Array(sorted.dropFirst(7).prefix(7))
        guard recent.count >= 3, previous.count >= 3 else { return "calibrando" }
        let recentMean = passiveRecoveryMean(recent)
        let previousMean = passiveRecoveryMean(previous)
        let delta = Int((recentMean - previousMean).rounded())
        if delta > 0 { return "+\(delta) pts" }
        if delta < 0 { return "\(delta) pts" }
        return "estável"
    }

    private var sourceText: String {
        latestSnapshot?.hasWatchSource == true ? "Watch ativo" : "iPhone/Health"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "applewatch", title: "Biometria passiva")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Sono Health", value: sleepHours > 0 ? String(format: "%.1fh", sleepHours) : "-", icon: "moon.zzz.fill", color: .indigo)
                BodySignalMetricPill(title: "HRV Watch", value: hrv > 0 ? "\(Int(hrv.rounded())) ms" : "-", icon: "heart.text.square.fill", color: .pink)
                BodySignalMetricPill(title: "FC repouso", value: restingHeartRate > 0 ? "\(Int(restingHeartRate.rounded())) bpm" : "-", icon: "heart.circle.fill", color: .red)
                BodySignalMetricPill(title: "Atividade", value: steps > 0 ? "\(steps) passos" : "-", icon: "figure.walk", color: .teal)
                BodySignalMetricPill(title: "FC Health", value: heartRate > 0 ? "\(Int(heartRate)) bpm" : "-", icon: "heart.circle.fill", color: .red)
                BodySignalMetricPill(title: "Energia", value: activeEnergy > 0 ? "\(Int(activeEnergy)) kcal" : "-", icon: "flame.fill", color: .orange)
                BodySignalMetricPill(title: "Circadiano", value: circadianText, icon: "clock.arrow.circlepath", color: .purple)
                BodySignalMetricPill(title: "Qualidade", value: qualityText, icon: "gauge.with.dots.needle.67percent", color: .green)
                BodySignalMetricPill(title: "Tendência 7d", value: weeklyTrendText, icon: weeklyTrendText.hasPrefix("-") ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis", color: weeklyTrendText.hasPrefix("-") ? .orange : .green)
            }

            HStack(spacing: 8) {
                Label(sourceText, systemImage: latestSnapshot?.hasWatchSource == true ? "applewatch" : "iphone")
                Spacer(minLength: 8)
                Label(lastSyncText, systemImage: "clock.arrow.circlepath")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Button(action: syncHealth) {
                Label("Sincronizar Apple Health", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
    }

    private var lastSyncText: String {
        guard lastSyncAt > 0 else { return "sem sync" }
        return Date(timeIntervalSince1970: lastSyncAt).formatted(.relative(presentation: .named))
    }

    private func passiveRecoveryMean(_ snapshots: [HealthKitDailySnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let values = snapshots.map { snapshot in
            var score = 60.0
            score += min(snapshot.qualityScore * 18, 18)
            if snapshot.sleepHours >= 6.5 { score += 8 }
            if snapshot.hrv > 0 { score += min(snapshot.hrv / 10, 8) }
            if let circadian = snapshot.circadianRegularityScore { score += circadian * 6 }
            if let resting = snapshot.restingHeartRate, resting > 0 { score -= max(0, resting - 70) * 0.35 }
            return min(max(score, 0), 100)
        }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct BodySignalsLimitationsCard: View {
    private let limitations = [
        "PPG por câmera sofre interferência de movimento, temperatura, iluminação e posição do dedo.",
        "Cafeína, exercício, medicamentos e sono alteram pulso/HRV sem significar mudança de humor.",
        "Tristeza, fadiga e ansiedade podem produzir sinais fisiológicos parecidos.",
        "Para uso clínico, esses sinais precisam ser combinados com autorrelato, sono, atividade e escalas validadas."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "exclamationmark.triangle", title: "Limitações")

            ForEach(limitations, id: \.self) { item in
                Label(item, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }
}

struct MonthlyMoodCalendarCard: View {
    let checkIns: [DailyCheckIn]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let weekdays = ["D", "S", "T", "Q", "Q", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(icon: "calendar", title: "Cronograma mensal")
                Spacer()
                Text(monthTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(calendarDays) { day in
                    CalendarDayCell(day: day, checkIn: checkInByDay[day.dateKey])
                }
            }

            HStack(spacing: 8) {
                CalendarLegendDot(color: .red, text: "difícil")
                CalendarLegendDot(color: .orange, text: "oscilou")
                CalendarLegendDot(color: .neuroYellow, text: "neutro")
                CalendarLegendDot(color: .green, text: "bem")
            }
        }
        .panelStyle()
    }

    private var monthTitle: String {
        Date.now.formatted(.dateTime.month(.wide).year())
    }

    private var checkInByDay: [String: DailyCheckIn] {
        Dictionary(grouping: checkIns) { dateKey(for: $0.date) }
            .compactMapValues { entries in
                entries.max { $0.date < $1.date }
            }
    }

    private var calendarDays: [CalendarDay] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: .now),
            let dayRange = calendar.range(of: .day, in: .month, for: .now)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        var days: [CalendarDay] = (1..<firstWeekday).map { _ in CalendarDay(date: nil) }

        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(CalendarDay(date: date))
            }
        }

        return days
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date?

    var dateKey: String {
        guard let date else { return id.uuidString }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct CalendarDayCell: View {
    let day: CalendarDay
    let checkIn: DailyCheckIn?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                }

            if let date = day.date {
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption.weight(.bold))
                    if checkIn != nil {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                    }
                }
                .foregroundStyle(textColor)
            }
        }
        .frame(height: 42)
    }

    private var backgroundColor: Color {
        guard let checkIn else {
            return day.date == nil ? .clear : Color(.secondarySystemGroupedBackground)
        }

        switch checkIn.mood {
        case ...1.5:
            return .red.opacity(0.26)
        case ..<3:
            return .orange.opacity(0.26)
        case ..<4:
            return .neuroYellow.opacity(0.38)
        default:
            return .green.opacity(0.28)
        }
    }

    private var borderColor: Color {
        checkIn == nil ? Color(.separator).opacity(day.date == nil ? 0 : 0.22) : moodColor.opacity(0.65)
    }

    private var moodColor: Color {
        guard let checkIn else { return .secondary }
        switch checkIn.mood {
        case ...1.5:
            return .red
        case ..<3:
            return .orange
        case ..<4:
            return .neuroYellow
        default:
            return .green
        }
    }

    private var textColor: Color {
        checkIn == nil ? .secondary : moodColor
    }
}

struct CalendarLegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct YearMoodOverviewCard: View {
    let checkIns: [DailyCheckIn]

    private let calendar = Calendar.current
    private let months = Calendar.current.shortMonthSymbols
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "calendar.badge.clock", title: "Visão anual")

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(months.enumerated()), id: \.offset) { index, month in
                    let average = averageMood(forMonth: index + 1)
                    VStack(spacing: 6) {
                        Text(month.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color(for: average).opacity(average == nil ? 0.08 : 0.34))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(color(for: average).opacity(average == nil ? 0.12 : 0.55), lineWidth: 1)
                            }
                            .frame(height: 38)
                            .overlay {
                                Text(average.map { String(format: "%.1f", $0) } ?? "-")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(average == nil ? .secondary : color(for: average))
                            }
                    }
                }
            }

            Text("Cada mês mostra a média de humor salva nos registros diários.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func averageMood(forMonth month: Int) -> Double? {
        let year = calendar.component(.year, from: .now)
        let entries = checkIns.filter {
            calendar.component(.year, from: $0.date) == year &&
            calendar.component(.month, from: $0.date) == month
        }
        guard !entries.isEmpty else { return nil }
        return entries.map(\.mood).reduce(0, +) / Double(entries.count)
    }

    private func color(for value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case ...1.5:
            return .red
        case ..<3:
            return .orange
        case ..<4:
            return .neuroGold
        default:
            return .green
        }
    }
}

struct MedicationPlanCard: View {
    @Binding var medicationName: String
    @Binding var medicationDose: String
    @Binding var medicationSchedule: String
    @Binding var medicationPrescription: String
    @Binding var medicationChangeNote: String
    let medicationPlans: [MedicationPlanEntry]
    let addMedication: () -> Void
    let removeMedication: (MedicationPlanEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "pills.fill", title: "Medicamentos")

            VStack(spacing: 10) {
                TextField("Nome do medicamento", text: $medicationName)
                TextField("Dose. Ex.: 50 mg", text: $medicationDose)
                TextField("Horário. Ex.: manhã e noite", text: $medicationSchedule)
                TextField("Prescrição/orientação. Ex.: após jantar", text: $medicationPrescription)
                TextField("Mudança recente de dose ou troca", text: $medicationChangeNote)
            }
            .textFieldStyle(.roundedBorder)

            Button(action: addMedication) {
                Label("Adicionar medicamento", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(medicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if medicationPlans.isEmpty {
                Text("Cadastre medicamentos, doses, horários, prescrição e mudanças para acompanhar resposta e efeitos colaterais ao longo do tempo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(medicationPlans) { medication in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "pills.circle.fill")
                                .foregroundStyle(Color.neuroOrange)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(medication.name)
                                    .font(.subheadline.weight(.bold))
                                Text([medication.dose, medication.schedule].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                if !medication.prescription.isEmpty {
                                    Text(medication.prescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !medication.changeNote.isEmpty {
                                    Label(medication.changeNote, systemImage: "arrow.triangle.2.circlepath")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }

                            Spacer()

                            Button {
                                removeMedication(medication)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.neuroYellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CustomSymptomCard: View {
    @Binding var symptomName: String
    @Binding var symptomValue: Double
    let symptoms: [CustomSymptomEntry]
    let addSymptom: () -> Void
    let removeSymptom: (CustomSymptomEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "slider.horizontal.3", title: "Sintomas personalizados")

            TextField("Ex.: impulsividade, compulsão, dor, choro", text: $symptomName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(symptomName.isEmpty ? "Intensidade" : symptomName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(symptomValue))/5")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.neuroOrange)
                }

                Slider(value: $symptomValue, in: 1...5, step: 1)
                    .tint(.neuroGold)
            }

            Button(action: addSymptom) {
                Label("Adicionar sintoma", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(symptomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !symptoms.isEmpty {
                VStack(spacing: 8) {
                    ForEach(symptoms) { symptom in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(symptom.name)
                                    .font(.subheadline.weight(.bold))
                                ProgressView(value: symptom.value, total: 5)
                                    .tint(.neuroGold)
                            }

                            Text("\(Int(symptom.value))/5")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.neuroOrange)

                            Button {
                                removeSymptom(symptom)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SafetyPlanEditorCard: View {
    @Binding var safetyContact: String
    @Binding var warningSigns: String
    @Binding var strategies: String
    let signature: NeuremiaRiskSignature
    let careFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "lifepreserver", title: "Plano de segurança")

            if signature.level != .low {
                VStack(alignment: .leading, spacing: 8) {
                    Label(signature.level == .high ? "Ação prioritária hoje" : "Atenção nas próximas 24-72h", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(alertColor)

                    ForEach(personalizedActions, id: \.self) { action in
                        Label(action, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(alertColor.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(alertColor.opacity(0.25), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Label(careFocus.safetyGuidance, systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField("Contato de confiança ou emergência", text: $safetyContact)
                .textFieldStyle(.roundedBorder)
            TextField("Meus sinais de alerta", text: $warningSigns)
                .textFieldStyle(.roundedBorder)
            TextField("O que costuma me ajudar", text: $strategies)
                .textFieldStyle(.roundedBorder)

            Text("Em risco imediato, procure emergência local ou contato de crise. Este plano não substitui atendimento profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var alertColor: Color {
        signature.level == .high ? .red : .orange
    }

    private var personalizedActions: [String] {
        var actions: [String] = []
        if !safetyContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append("Avisar ou combinar checagem com: \(safetyContact).")
        } else {
            actions.append("Definir um contato de confiança antes de uma crise.")
        }

        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("sono") }) {
            actions.append("Priorizar rotina de sono e reduzir estímulos hoje.")
        }
        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("medicação") || $0.localizedCaseInsensitiveContains("adesão") }) {
            actions.append("Conferir medicação, efeitos colaterais e combinar conduta com profissional.")
        }
        if signature.factors.contains(where: { $0.localizedCaseInsensitiveContains("gatilho") }) {
            actions.append("Evitar gatilhos identificados e usar estratégia de regulação.")
        }
        if !signature.focusAlerts.isEmpty {
            actions.append(careFocus.safetyGuidance)
        }
        if signature.level == .high {
            actions.append("Se houver risco imediato de se machucar, procurar emergência local agora.")
        }
        return Array(actions.prefix(5))
    }
}

struct PsychoeducationCard: View {
    private let topics = [
        PsychoeducationTopic(
            icon: "moon.zzz.fill",
            title: "Sono e rotina",
            text: "Mudanças no sono podem aparecer antes de oscilações importantes. Observe horário de dormir, despertares e energia no dia seguinte.",
            color: Color.indigo
        ),
        PsychoeducationTopic(
            icon: "pills.fill",
            title: "Medicação",
            text: "Registrar tomada parcial, esquecimentos e efeitos colaterais ajuda a conversar com o profissional sem depender só da memória.",
            color: Color.teal
        ),
        PsychoeducationTopic(
            icon: "bolt.heart.fill",
            title: "Gatilhos",
            text: "Álcool, privação de sono, estresse e conflitos podem afetar sintomas. Com histórico, o app começa a mostrar padrões pessoais.",
            color: Color.orange
        ),
        PsychoeducationTopic(
            icon: "lifepreserver.fill",
            title: "Sinais de alerta",
            text: "Se houver risco de se machucar, procure ajuda imediata. O plano de segurança serve para lembrar contatos e estratégias já combinadas.",
            color: Color.red
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "book.pages", title: "Aprender sobre meu cuidado")

            Text("Informações curtas para entender melhor os registros e preparar conversas com seu profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(topics) { topic in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(topic.color)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(topic.title)
                                .font(.subheadline.weight(.bold))
                            Text(topic.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(topic.color.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }
}

struct PsychoeducationTopic: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let text: String
    let color: Color
}

struct DSM5CriteriaGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

struct DSM5FoundationCard: View {
    let selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "brain.head.profile", title: "Por que pergunto isso?")

            Text("Triagem estruturada baseada em domínios clínicos do DSM-5/DSM-5-TR. O app organiza sinais para acompanhamento e conversa clínica, sem fechar diagnóstico automaticamente.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Label(selectedFocus.rawValue, systemImage: selectedFocus.icon)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(selectedFocus.dsm5MonitoringFrame)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                    ForEach(selectedFocus.dsm5SignalSummary, id: \.self) { signal in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(Color.neuroOrange)
                            Text(signal)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.neuroYellow.opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(selectedFocus.dsm5CriteriaGroups) { group in
                        DSM5CriteriaGroupView(group: group)
                    }
                }

                Label("Para uso clínico: confirmar duração, intensidade, prejuízo funcional, curso longitudinal, risco atual, diagnósticos diferenciais e exclusões médicas/substâncias antes de qualquer conclusão.", systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }
}

struct DSM5CriteriaGroupView: View {
    let group: DSM5CriteriaGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)

            ForEach(group.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "smallcircle.filled.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.neuroGold)
                        .padding(.top, 3)

                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct MedicationTrackerCard: View {
    let medicationStatus: MedicationStatus
    let adherence: Double
    let sideEffects: String
    let checkIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "pills", title: "Medicação")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                MoodSignalPill(
                    title: "Hoje",
                    value: medicationStatus.rawValue,
                    icon: medicationStatus == .taken ? "checkmark.seal" : "bell.badge",
                    color: medicationStatus.color
                )

                MoodSignalPill(
                    title: "Adesão recente",
                    value: "\(String(format: "%.0f", adherence * 100))%",
                    icon: "chart.pie",
                    color: adherence >= 0.8 ? .green : .orange
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                MoodSignalPill(
                    title: "Com medicação",
                    value: display(averageMood(medicationTaken: true)),
                    icon: "face.smiling",
                    color: .green
                )

                MoodSignalPill(
                    title: "Sem medicação",
                    value: display(averageMood(medicationTaken: false)),
                    icon: "chart.line.downtrend.xyaxis",
                    color: .orange
                )
            }

            Text(sideEffects.isEmpty ? "Registre efeitos colaterais para comparar medicação e sintomas ao longo do tempo." : "Efeito anotado hoje: \(sideEffects)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(abandonmentInsight)
                .font(.caption.weight(.semibold))
                .foregroundStyle(adherence < 0.7 ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var abandonmentInsight: String {
        if checkIns.count < 3 {
            return "Com mais registros, o app compara adesão, efeitos colaterais e sintomas percebidos."
        }

        if adherence < 0.7 {
            return "Adesão baixa recentemente. Vale revisar esquecimento, efeitos colaterais ou dificuldade de rotina."
        }

        return "Adesão estável. Continue registrando para observar curva de resposta percebida."
    }

    private func averageMood(medicationTaken: Bool) -> Double? {
        let filtered = checkIns.filter { $0.medicationTaken == medicationTaken }
        guard !filtered.isEmpty else { return nil }
        return filtered.map(\.mood).reduce(0, +) / Double(filtered.count)
    }

    private func display(_ value: Double?) -> String {
        guard let value else { return "-" }
        return "\(String(format: "%.1f", value))/5"
    }
}

struct CircadianStabilityCard: View {
    let sleepHours: Double
    let averageSleep: Double
    let checkInCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "moon.stars", title: "Ritmo de sono")

            HStack(spacing: 10) {
                MoodSignalPill(title: "Hoje", value: "\(String(format: "%.1f", sleepHours))h", icon: "bed.double", color: sleepColor)
                MoodSignalPill(title: "Índice circadiano", value: stabilityLabel, icon: "clock", color: stabilityColor)
            }

            MoodSignalPill(
                title: "Desorganização do sono",
                value: "\(disorganizationScore)/100",
                icon: "waveform.path",
                color: disorganizationScore >= 60 ? .red : disorganizationScore >= 35 ? .orange : .green
            )

            Text("Sono irregular pode preceder piora de humor, ansiedade ou energia. Com mais registros, este índice fica mais útil.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var stabilityLabel: String {
        guard checkInCount > 1 else { return "Inicial" }
        return abs(sleepHours - averageSleep) <= 1.5 ? "Estável" : "Oscilando"
    }

    private var stabilityColor: Color {
        stabilityLabel == "Oscilando" ? .orange : .green
    }

    private var sleepColor: Color {
        sleepHours < 5.5 ? .red : sleepHours < 7 ? .orange : .indigo
    }

    private var disorganizationScore: Int {
        guard checkInCount > 1 else { return 0 }
        let deviation = min(abs(sleepHours - averageSleep), 5)
        return Int((deviation / 5) * 100)
    }
}

struct TriggerMapCard: View {
    @Binding var alcoholTrigger: Bool
    @Binding var poorSleepTrigger: Bool
    @Binding var stressTrigger: Bool
    @Binding var conflictTrigger: Bool
    @Binding var routineChangeTrigger: Bool
    @Binding var menstrualTrigger: Bool
    @Binding var customTriggerText: String
    @Binding var customTriggers: [String]
    let checkIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bolt.badge.clock", title: "Gatilhos do dia")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                TriggerToggle(title: "Álcool", icon: "wineglass", color: .purple, isOn: $alcoholTrigger)
                TriggerToggle(title: "Pouco sono", icon: "moon.zzz", color: .indigo, isOn: $poorSleepTrigger)
                TriggerToggle(title: "Estresse", icon: "flame", color: .red, isOn: $stressTrigger)
                TriggerToggle(title: "Conflito", icon: "person.2.slash", color: .orange, isOn: $conflictTrigger)
                TriggerToggle(title: "Rotina mudou", icon: "arrow.triangle.2.circlepath", color: .teal, isOn: $routineChangeTrigger)
                TriggerToggle(title: "Ciclo menstrual", icon: "calendar.badge.clock", color: .pink, isOn: $menstrualTrigger)
            }

            HStack(spacing: 8) {
                TextField("Adicionar gatilho", text: $customTriggerText)
                    .textInputAutocapitalization(.sentences)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    addCustomTrigger()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.neuroOrange, in: Circle())
                .disabled(customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            }

            if !customTriggers.isEmpty {
                FlowLayout(items: customTriggers)
            }

            Text(triggerInsight)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var triggerInsight: String {
        guard checkIns.count >= 3 else {
            return "Com alguns dias de histórico, o app começa a relacionar gatilhos com sono, ansiedade e humor."
        }

        let lastThree = Array(checkIns.prefix(3))
        let lowSleepCount = lastThree.filter { $0.sleepHours < 6 }.count
        let highAnxietyCount = lastThree.filter { $0.anxiety >= 4 }.count
        let lowMoodCount = lastThree.filter { $0.mood <= 2 }.count

        if lowSleepCount >= 2 && (highAnxietyCount >= 1 || lowMoodCount >= 1) {
            return "Insight: pouco sono apareceu junto de maior ansiedade ou queda de humor nos últimos registros."
        }

        if highAnxietyCount >= 2 {
            return "Insight: ansiedade alta apareceu repetidamente. Marcar gatilhos ajuda a encontrar padrões."
        }

        return "Nenhum padrão forte ainda. Continue marcando gatilhos para personalizar os alertas."
    }

    private func addCustomTrigger() {
        let trimmed = customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customTriggers.contains(trimmed) else {
            return
        }

        customTriggers.append(trimmed)
        customTriggerText = ""
    }
}

struct TriggerToggle: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(isOn ? .white : color)
                        .frame(width: 36, height: 36)
                        .background(isOn ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                    Spacer(minLength: 0)

                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isOn ? color : .secondary.opacity(0.45))
                }

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                LinearGradient(
                    colors: isOn
                        ? [color.opacity(0.22), color.opacity(0.08)]
                        : [Color(.secondarySystemGroupedBackground), Color(.tertiarySystemGroupedBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isOn ? color.opacity(0.85) : Color.clear, lineWidth: 1.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isOn ? color.opacity(0.15) : .clear, radius: 8, y: 4)
            .scaleEffect(isOn ? 1.025 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct EngagementCard: View {
    let checkInCount: Int
    let recentCheckIns: [DailyCheckIn]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "rosette", title: "Constância")

            HStack(spacing: 10) {
                MoodSignalPill(title: "Registros", value: "\(checkInCount)", icon: "calendar", color: .neuroYellow)
                MoodSignalPill(title: "Sequência", value: "\(streak) dias", icon: "flame", color: streak >= 7 ? .green : .orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                BadgePill(title: "Primeiro passo", isUnlocked: checkInCount >= 1)
                BadgePill(title: "7 dias", isUnlocked: streak >= 7)
                BadgePill(title: "14 registros", isUnlocked: checkInCount >= 14)
            }

            Text(streak >= 7 ? "Boa sequência. Acompanhar por vários dias melhora a percepção de padrões." : "Tente registrar um pouco por dia. Mesmo respostas rápidas já ajudam.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: min(Double(streak), 7), total: 7) {
                Text("Meta saudável: 7 dias de check-in")
                    .font(.caption.weight(.semibold))
            }
            .tint(.neuroYellow)
        }
        .panelStyle()
    }

    private var streak: Int {
        let days = Set(recentCheckIns.map { Calendar.current.startOfDay(for: $0.date) })
        var count = 0
        var day = Calendar.current.startOfDay(for: .now)

        while days.contains(day) {
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previous
        }

        return count
    }
}

struct BadgePill: View {
    let title: String
    let isUnlocked: Bool

    var body: some View {
        Label(title, systemImage: isUnlocked ? "star.fill" : "star")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(isUnlocked ? Color.neuroYellow.opacity(0.34) : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isUnlocked ? .orange : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CareFocusCard: View {
    @Binding var selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.crop.circle.badge.checkmark", title: "Foco do acompanhamento")

            Picker("Foco do acompanhamento", selection: $selectedFocus) {
                ForEach(CareFocus.allCases) { focus in
                    Text(focus.rawValue).tag(focus)
                }
            }
            .pickerStyle(.menu)

            Text(selectedFocus.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(selectedFocus.modules, systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

struct ClinicalPersonalizationCard: View {
    let selectedFocus: CareFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "slider.horizontal.below.rectangle", title: "Personalização clínica")

            Text("O acompanhamento muda conforme o foco escolhido nas configurações e na evolução.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                PersonalizationTile(icon: "heart.text.square", title: "Escala principal", text: selectedFocus.preferredScale.rawValue, tint: .orange)
                PersonalizationTile(icon: "waveform.path.ecg", title: "Sinais priorizados", text: biomarkerText, tint: .indigo)
                PersonalizationTile(icon: "bell.badge", title: "Risco observado", text: riskText, tint: .red)
                PersonalizationTile(icon: "calendar.badge.clock", title: "Rotina de revisão", text: cadenceText, tint: .green)
            }
        }
        .panelStyle()
    }

    private var biomarkerText: String {
        switch selectedFocus {
        case .bipolar:
            "sono, energia, irritabilidade, PPG e adesão"
        case .depression:
            "humor, energia, sono, apetite e voz"
        case .anxiety:
            "ansiedade, sono, PPG, respiração e gatilhos"
        case .borderline:
            "intensidade emocional, conflitos e segurança"
        case .burnout:
            "energia, sono, atividade e recuperação"
        case .adhd:
            "rotina, sono, digitação e adesão"
        case .postpartum:
            "sono, humor, ansiedade e rede de apoio"
        }
    }

    private var riskText: String {
        switch selectedFocus {
        case .bipolar:
            "virada de humor, sono reduzido e impulsividade"
        case .depression:
            "queda de humor, desesperança e segurança"
        case .anxiety:
            "ansiedade persistente e hiperativação"
        case .borderline:
            "crise interpessoal e impulsividade"
        case .burnout:
            "exaustão sustentada e perda de rotina"
        case .adhd:
            "desorganização funcional e baixa adesão"
        case .postpartum:
            "privação de sono, humor e sinais de alerta"
        }
    }

    private var cadenceText: String {
        switch selectedFocus {
        case .bipolar, .borderline, .postpartum:
            "revisão mais próxima se sono ou segurança mudarem"
        case .depression, .anxiety:
            "revisão semanal quando sintomas subirem"
        case .burnout, .adhd:
            "revisão por padrão de rotina e funcionamento"
        }
    }
}

struct PersonalizationTile: View {
    let icon: String
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PatientReportExportCard: View {
    let reportPreview: String
    let pdfURL: URL?
    let csvURL: URL?
    let generateReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "square.and.arrow.up", title: "Relatório para consulta")

            Text("Gere um resumo com evolução, check-ups e sinais recentes para compartilhar com seu profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: generateReport) {
                Label("Gerar resumo", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if !reportPreview.isEmpty {
                Text(reportPreview)
                    .font(.caption.monospaced())
                    .lineLimit(6)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Compartilhar PDF", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let csvURL {
                    ShareLink(item: csvURL) {
                        Label("Compartilhar CSV", systemImage: "tablecells")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                ShareLink(item: reportPreview) {
                    Label("Compartilhar texto", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .panelStyle()
    }
}

struct MonthlyReportAutomationCard: View {
    @Binding var isEnabled: Bool
    let reportStatusMessage: String
    let generateReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.badge.plus", title: "Relatório mensal")

            Toggle("Preparar relatório mensal automaticamente", isOn: $isEnabled)
                .toggleStyle(.switch)

            HStack(spacing: 10) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(isEnabled ? .green : .secondary)
                Text(isEnabled ? "O app já deixa o relatório mensal pronto quando houver dados suficientes." : "Ative para transformar o histórico do mês em resumo para consulta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: generateReport) {
                Label("Gerar relatório do mês agora", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // P1-2: reportStatusMessage migrado para toast central.
        }
        .panelStyle()
    }
}

struct BackupExportCard: View {
    let backupURL: URL?
    @Binding var isAutomatic: Bool
    @Binding var intervalDays: Int
    let lastAutomaticBackupAt: Double
    let backupStatus: String
    let backgroundStatus: String
    let localOnlyMode: Bool
    let makeBackup: () -> Void
    let restoreBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "externaldrive.badge.checkmark", title: "Backup dos dados")

            Text("Gere, compartilhe ou restaure um arquivo JSON com registros, escalas, medicações, sintomas personalizados e plano de segurança.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if localOnlyMode {
                Label("Modo local ativo: seus dados ficam neste aparelho. Guarde uma cópia do backup em um lugar seguro. Textos clínicos protegidos só restauram quando a chave deste aparelho continua disponível.", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.neuroNavy)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.neuroYellow.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Backup automático ao salvar diário", isOn: $isAutomatic)
                .toggleStyle(.switch)

            Stepper("Backup recorrente: a cada \(intervalDays) dia(s)", value: $intervalDays, in: 1...30)
                .disabled(!isAutomatic)

            Label(lastBackupText, systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Label(backgroundStatus, systemImage: "iphone.and.arrow.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: makeBackup) {
                Label(localOnlyMode ? "Criar backup seguro" : "Gerar backup", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: restoreBackup) {
                Label("Restaurar backup", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Guardar cópia do backup", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if !backupStatus.isEmpty {
                Text(backupStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var lastBackupText: String {
        guard lastAutomaticBackupAt > 0 else {
            return "Nenhum backup automático gerado ainda."
        }

        let date = Date(timeIntervalSince1970: lastAutomaticBackupAt)
        return "Último backup automático: \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct CareTeamAutoSendCard: View {
    @Binding var isEnabled: Bool
    @Binding var contact: String
    @Binding var caregiverName: String
    @Binding var caregiverRelationship: String
    let canShare: Bool
    let canShareCaregiver: Bool
    let status: String
    let caregivers: [BackendCaregiverContact]
    let saveCaregiver: () -> Void
    let refreshCaregivers: () -> Void
    let sendNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "paperplane.fill", title: "Envio automático")

            Toggle("Enviar relatório ao médico/cuidador", isOn: $isEnabled)
                .toggleStyle(.switch)

            TextField("E-mail ou contato do médico/cuidador", text: $contact)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                TextField("Nome do cuidador", text: $caregiverName)
                    .textFieldStyle(.roundedBorder)

                TextField("Vínculo", text: $caregiverRelationship)
                    .textFieldStyle(.roundedBorder)
            }

            Label(canShare ? "Compartilhamento autorizado" : "Ative consentimento e compartilhamento para enviar", systemImage: canShare ? "checkmark.seal.fill" : "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canShare ? .green : .secondary)

            HStack(spacing: 10) {
                Button(action: saveCaregiver) {
                    Label("Cadastrar cuidador", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canShareCaregiver || contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: refreshCaregivers) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Atualizar cuidadores")
            }

            if !caregivers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(caregivers) { caregiver in
                        HStack(spacing: 10) {
                            Image(systemName: caregiver.shareEnabled ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.xmark")
                                .foregroundStyle(caregiver.shareEnabled ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(caregiver.name)
                                    .font(.subheadline.weight(.semibold))

                                Text(caregiverSubtitle(caregiver))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Button(action: sendNow) {
                Label("Enviar relatório agora", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled || !canShare)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private func caregiverSubtitle(_ caregiver: BackendCaregiverContact) -> String {
        let relationship = caregiver.relationship.isEmpty ? "cuidador" : caregiver.relationship
        let permission = caregiver.shareEnabled ? "autorizado" : "bloqueado"
        return "\(relationship) • \(caregiver.contact) • \(permission)"
    }
}

struct ClinicalGovernanceSettingsCard: View {
    @Binding var moodThreshold: Double
    @Binding var anxietyThreshold: Double
    @Binding var sleepThreshold: Double
    @Binding var caregiverDigestConsent: Bool
    @Binding var caregiverSMSConsent: Bool
    @Binding var criticalPushConsent: Bool
    let shareWithClinician: Bool
    let shareWithCaregiver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "slider.horizontal.3", title: "Produto clínico")

            VStack(alignment: .leading, spacing: 10) {
                Text("Limiares por paciente")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                thresholdSlider(title: "Humor atenção", value: $moodThreshold, range: 1...3.5, format: "%.1f ou menos")
                thresholdSlider(title: "Ansiedade atenção", value: $anxietyThreshold, range: 2.5...5, format: "%.1f ou mais")
                thresholdSlider(title: "Sono mínimo", value: $sleepThreshold, range: 4...8, format: "%.1fh")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Consentimento granular")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Toggle("Enviar digest diário ao clínico", isOn: $caregiverDigestConsent)
                    .disabled(!shareWithClinician)
                Toggle("Permitir SMS/contato crítico para cuidador", isOn: $caregiverSMSConsent)
                    .disabled(!shareWithCaregiver)
                Toggle("Permitir push crítico para risco alto", isOn: $criticalPushConsent)
            }
            .toggleStyle(.switch)

            Label(statusText, systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private func thresholdSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 0.5)
        }
    }

    private var statusText: String {
        let clinician = shareWithClinician ? "clínico autorizado" : "clínico bloqueado"
        let caregiver = shareWithCaregiver ? "cuidador autorizado" : "cuidador bloqueado"
        return "Escopo atual: \(clinician), \(caregiver). Consentimentos críticos ficam separados do compartilhamento comum."
    }
}

struct HealthKitIntegrationCard: View {
    @Binding var isEnabled: Bool
    let status: String
    let sleepHours: Double
    let steps: Int
    let heartRate: Double
    let activeEnergy: Double
    let hrv: Double
    let lastSyncAt: Double
    let snapshots: [HealthKitDailySnapshot]
    let sync: () -> Void

    private var latestSnapshot: HealthKitDailySnapshot? {
        snapshots.sorted { $0.date > $1.date }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "heart.text.square.fill", title: "Apple Health")

            Toggle("Usar dados do Apple Health", isOn: $isEnabled)
                .toggleStyle(.switch)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                HealthMetricPill(title: "Sono", value: String(format: "%.1fh", sleepHours), icon: "moon.zzz", color: .indigo)
                HealthMetricPill(title: "Passos", value: "\(steps)", icon: "figure.walk", color: .teal)
                HealthMetricPill(title: "FC média", value: heartRate > 0 ? String(format: "%.0f bpm", heartRate) : "-", icon: "heart.fill", color: .red)
                HealthMetricPill(title: "FC repouso", value: (latestSnapshot?.restingHeartRate ?? 0) > 0 ? String(format: "%.0f bpm", latestSnapshot?.restingHeartRate ?? 0) : "-", icon: "heart.circle", color: .red)
                HealthMetricPill(title: "HRV", value: hrv > 0 ? String(format: "%.0f ms", hrv) : "-", icon: "heart.text.square", color: .pink)
                HealthMetricPill(title: "Energia", value: activeEnergy > 0 ? String(format: "%.0f kcal", activeEnergy) : "-", icon: "flame.fill", color: .orange)
                HealthMetricPill(title: "Circadiano", value: circadianText, icon: "clock.arrow.circlepath", color: .purple)
                HealthMetricPill(title: "Qualidade", value: qualityText, icon: "gauge.with.dots.needle.67percent", color: .green)
                HealthMetricPill(title: "Fonte", value: latestSnapshot?.hasWatchSource == true ? "Watch" : "Health", icon: latestSnapshot?.hasWatchSource == true ? "applewatch" : "heart.text.square", color: .blue)
            }

            Label(lastSyncText, systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(action: sync) {
                Label("Conectar e sincronizar Health", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var lastSyncText: String {
        guard lastSyncAt > 0 else { return "Sync automático ainda não executado." }
        return "Último sync: \(Date(timeIntervalSince1970: lastSyncAt).formatted(.relative(presentation: .named)))"
    }

    private var qualityText: String {
        guard let quality = latestSnapshot?.qualityScore else { return "-" }
        return "\(Int((quality * 100).rounded()))%"
    }

    private var circadianText: String {
        guard let score = latestSnapshot?.circadianRegularityScore else { return "-" }
        return "\(Int((score * 100).rounded()))%"
    }
}

struct HealthMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RemotePushCard: View {
    @Binding var isEnabled: Bool
    let status: String
    let token: String
    let register: () -> Void
    let uploadToken: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bell.and.waves.left.and.right.fill", title: "Push remoto")

            Toggle("Permitir alertas remotos", isOn: $isEnabled)
                .toggleStyle(.switch)

            Button(action: register) {
                Label("Registrar no APNs", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)

            Button(action: uploadToken) {
                Label("Enviar token ao backend", systemImage: "server.rack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(token.isEmpty)

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

struct ProductionReadinessCard: View {
    private let rows = [
        ("heart.text.square", "Apple Health", "Exige ativar HealthKit no projeto e pedir permissão para sono, passos e frequência cardíaca."),
        ("bell.and.waves.left.and.right", "Push remoto", "Exige APNs/Firebase, backend publicado e vínculo real médico-paciente."),
        ("server.rack", "Deploy e PostgreSQL", "Exige servidor/cloud, domínio, HTTPS, DATABASE_URL, backups e monitoramento."),
        ("checkmark.seal", "Escalas e validação", "Exige licença/tradução oficial quando aplicável e validação clínica formal com profissionais.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "shippingbox.and.arrow.backward", title: "Produção")

            ForEach(rows, id: \.1) { row in
                ComplianceRow(icon: row.0, title: row.1, description: row.2)
            }
        }
        .panelStyle()
    }
}

struct ClinicalValidationRoadmapCard: View {
    private let rows = [
        ("waveform.path.ecg", "Validar PPG", "Comparar câmera/flash com Apple Watch, oxímetro ou cinta cardíaca em amostras reais."),
        ("mic", "Validar voz e digitação", "Medir apenas metadados, sem conteúdo, e comparar com escalas e avaliação clínica."),
        ("exclamationmark.triangle", "Falsos alertas", "Registrar quantos alertas foram úteis, excessivos ou perdidos antes de uso clínico."),
        ("person.2.badge.gearshape", "Revisão profissional", "Psiquiatras/psicólogos precisam revisar regras, linguagem, crise e limites do app."),
        ("checkmark.seal", "Estudo de efetividade", "Provar melhora em monitoramento, adesão ou desfechos antes de chamar de produto clínico validado.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "checklist.checked", title: "Validação para inovação")

            Text("O app já prepara a coleta multimodal e os insights, mas a validação depende de estudo real com pessoas e profissionais.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(rows, id: \.1) { row in
                ComplianceRow(icon: row.0, title: row.1, description: row.2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Métricas do estudo piloto")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], spacing: 8) {
                    ValidationMetricPill(title: "Sensibilidade", detail: "crises detectadas")
                    ValidationMetricPill(title: "Especificidade", detail: "dias estáveis corretos")
                    ValidationMetricPill(title: "Falsos alertas", detail: "alertas sem crise")
                    ValidationMetricPill(title: "Antecedência", detail: "dias antes da piora")
                    ValidationMetricPill(title: "Adesão", detail: "uso diário")
                    ValidationMetricPill(title: "Utilidade clínica", detail: "médico/paciente")
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }
}

struct ValidationMetricPill: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AutomaticWellbeingCheckupCard: View {
    let results: [AutomaticScaleResult]
    let statusMessage: String
    let canSave: Bool
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(Color.neuroNavy)
                    .frame(width: 44, height: 44)
                    .background(Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-up do bem-estar")
                        .font(.headline)
                    // P2-8 (UX): subtitle reforça natureza estimada antes de
                    // o paciente ver as pontuações, prevenindo interpretação
                    // incorreta como resultado clínico válido.
                    Text("Estimativa salva automaticamente junto com o diário — não substitui avaliação formal.")
                        .font(.subheadline)
                        .foregroundStyle(.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.scale.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text("\(result.score)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(color(for: result))

                        Text(result.interpretation)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(color(for: result))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(color(for: result).opacity(0.10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color(for: result).opacity(0.25), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Text("Observação: esta é uma estimativa automática de apoio. Aplicação oficial/validada das escalas exige instrumento autorizado e contexto clínico adequado.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: save) {
                Label("Atualizar check-up automático", systemImage: "arrow.clockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)

            if !statusMessage.isEmpty {
                Label(statusMessage, systemImage: statusMessage.contains("Não") ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusMessage.contains("Não") ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private func color(for result: AutomaticScaleResult) -> Color {
        switch result.scale {
        case .phq9:
            result.score >= 20 ? .red : result.score >= 10 ? .orange : .green
        case .gad7:
            result.score >= 15 ? .red : result.score >= 10 ? .orange : .green
        case .ymrs:
            result.score >= 22 ? .red : result.score >= 13 ? .orange : .green
        }
    }
}

struct TodayMoodOverviewCard: View {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let medicationTaken: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Resumo de hoje", systemImage: "calendar.day.timeline.left")
                        .font(.headline)

                    Text(Date.now, format: .dateTime.day().month(.abbreviated))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: overviewIcon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(overviewColor)
                    .frame(width: 42, height: 42)
                    .background(overviewColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                MoodSignalPill(
                    title: "Humor",
                    value: moodLabel,
                    icon: "face.smiling",
                    color: moodColor
                )

                MoodSignalPill(
                    title: "Ansiedade",
                    value: anxietyLabel,
                    icon: "waveform.path.ecg",
                    color: anxietyColor
                )

                MoodSignalPill(
                    title: "Sono",
                    value: "\(String(format: "%.1f", sleepHours))h",
                    icon: "moon.zzz",
                    color: sleepColor
                )

                MoodSignalPill(
                    title: "Medicação",
                    value: medicationTaken ? "Tomada" : "Pendente",
                    icon: medicationTaken ? "checkmark.seal" : "exclamationmark.triangle",
                    color: medicationTaken ? .green : .orange
                )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), overviewColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(overviewColor.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var moodLabel: String {
        if mood <= 1.5 {
            return "Baixo"
        }

        if mood >= 4 {
            return "Bem"
        }

        return "Ok"
    }

    private var anxietyLabel: String {
        if anxiety <= 1.5 {
            return "Leve"
        }

        if anxiety >= 4 {
            return "Alta"
        }

        return "Média"
    }

    private var overviewIcon: String {
        mood >= 4 && anxiety <= 2 ? "sun.max.fill" : "heart.text.square.fill"
    }

    private var overviewColor: Color {
        if anxiety >= 4 || mood <= 1.5 {
            return .red
        }

        if anxiety >= 3 || sleepHours < 6 {
            return .orange
        }

        return .neuroYellow
    }

    private var moodColor: Color {
        if mood <= 1.5 {
            return .red
        }

        if mood >= 4 {
            return .green
        }

        return .orange
    }

    private var anxietyColor: Color {
        if anxiety <= 1.5 {
            return .green
        }

        if anxiety >= 4 {
            return .red
        }

        return .orange
    }

    private var sleepColor: Color {
        if sleepHours < 5.5 {
            return .red
        }

        if sleepHours < 7 {
            return .orange
        }

        return .indigo
    }
}

struct MoodSignalPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

struct DailySafetyChoices: View {
    @Binding var medicationStatus: MedicationStatus
    @Binding var safetyStatus: SafetyStatus

    var body: some View {
        VStack(spacing: 10) {
            MedicationStatusCard(status: $medicationStatus)
            SafetyStatusCard(status: $safetyStatus)
        }
    }
}

struct MedicationStatusCard: View {
    @Binding var status: MedicationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "pills.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(status.color)
                    .frame(width: 52, height: 52)
                    .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Medicação")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(status.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(MedicationStatus.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            status = option
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: medicationIcon(for: option))
                                .font(.title3.weight(.bold))
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(status == option ? option.color.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.12), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func medicationIcon(for option: MedicationStatus) -> String {
        switch option {
        case .pending:
            "alarm.fill"
        case .partial:
            "moonphase.first.quarter"
        case .taken:
            "checkmark.seal.fill"
        }
    }
}

struct SafetyStatusCard: View {
    @Binding var status: SafetyStatus
    @State private var isConfirmingUrgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: safetyIcon(for: status))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(status.color)
                    .frame(width: 52, height: 52)
                    .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Segurança hoje")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(status.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(SafetyStatus.allCases) { option in
                    Button {
                        if option == .urgent && status != .urgent {
                            isConfirmingUrgent = true
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                status = option
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: safetyIcon(for: option))
                                .font(.title3.weight(.bold))
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(status == option ? option.color.opacity(0.20) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.12), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert("Confirmar sinal de risco?", isPresented: $isConfirmingUrgent) {
            Button("Marcar como urgente", role: .destructive) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    status = .urgent
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ao marcar como urgente, o app registra ideação suicida neste check-in e dispara alerta para a equipe de cuidado autorizada (médico vinculado e/ou cuidadores). Se houver risco imediato, ligue para 188 (CVV) ou 192 (SAMU) agora.")
        }
    }

    private func safetyIcon(for option: SafetyStatus) -> String {
        switch option {
        case .safe:
            "checkmark.shield.fill"
        case .attention:
            "exclamationmark.triangle.fill"
        case .urgent:
            "cross.case.fill"
        }
    }
}

// P2-7 (UX): adicionado parâmetro opcional `skipLabel` + `skipValue`.
// Quando presente, exibe um botão extra "Não se aplica" que seta o valor
// para `skipValue` (default 0). Usado em Libido para evitar que o campo
// obrigatório com valor default 3 produza ruído de dados em pacientes
// que simplesmente ignoram o campo.
struct VisualMetricPicker: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let options: [MetricOption]
    var suffix = ""
    var skipLabel: String? = nil
    var skipValue: Double = 0.0

    var isSkipped: Bool { skipLabel != nil && abs(value - skipValue) < 0.1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(isSkipped ? "—" : displayValue)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 6)], spacing: 6) {
                ForEach(options) { option in
                    Button {
                        value = option.value
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isSelected(option) ? option.color.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(isSelected(option) ? option.color : .secondary)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected(option) ? option.color : Color.clear, lineWidth: 1.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                if let label = skipLabel {
                    Button {
                        value = skipValue
                    } label: {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isSkipped ? Color.secondary.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                            .foregroundStyle(isSkipped ? .primary : .secondary)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSkipped ? Color.secondary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func isSelected(_ option: MetricOption) -> Bool {
        !isSkipped && abs(value - option.value) < 0.1
    }

    private var displayValue: String {
        if suffix == "h" {
            return "\(String(format: "%.1f", value))h"
        }

        return "\(Int(value))/5"
    }
}

struct LabeledTextEditor: View {
    let title: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            TextEditor(text: $text)
                .frame(minHeight: 88)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct PatientFeedbackCard: View {
    let summary: LongitudinalSummary
    let canSave: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(color)

            Text(canSave ? patientText : "Ative o consentimento nas configurações para salvar seus registros com segurança.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [color.opacity(0.14), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch summary.riskLevel {
        case .low:
            "Seu dia parece estável"
        case .moderate:
            "Vale acompanhar de perto"
        case .high:
            "Você merece apoio agora"
        }
    }

    private var color: Color {
        switch summary.riskLevel {
        case .low:
            .neuroYellow
        case .moderate:
            .orange
        case .high:
            .red
        }
    }

    private var patientText: String {
        switch summary.riskLevel {
        case .low:
            "Continue registrando aos poucos. Pequenos registros ajudam a enxergar padrões sem precisar lembrar tudo depois."
        case .moderate:
            "Sono, ansiedade ou humor podem estar oscilando. Se isso continuar, compartilhe com seu profissional de confiança."
        case .high:
            "Se estiver em risco ou sem segurança, procure ajuda imediatamente. O app apoia o cuidado, mas não substitui atendimento."
        }
    }
}

struct DailyRecommendationCard: View {
    let recommendation: ClinicalDailyRecommendation
    let log: DailyRecommendationLog?
    let responseProfile: RecommendationResponseProfile?
    let canSave: Bool
    let markCompleted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isCompleted ? "checkmark.seal.fill" : "target")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isCompleted ? .green : .neuroYellow)
                    .frame(width: 34, height: 34)
                    .background((isCompleted ? Color.green : Color.neuroYellow).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text(recommendation.action)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Text(recommendation.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let responseProfile {
                RecommendationResponseProfileRow(profile: responseProfile)
            }

            if let impact = log?.impactSummary {
                Label(impact, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Label("Impacto esperado em \(recommendation.expectedWindow)", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(action: markCompleted) {
                Label(isCompleted ? "Feita hoje" : "Marcar como feita", systemImage: isCompleted ? "checkmark.circle.fill" : "circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCompleted ? .green : .neuroYellow)
            .disabled(!canSave || isCompleted)
            .accessibilityHint("Registra que você executou a recomendação para medir o impacto nos próximos dias.")
        }
        .panelStyle()
    }

    private var isCompleted: Bool {
        log?.completed == true
    }
}

private struct RecommendationResponseProfileRow: View {
    let profile: RecommendationResponseProfile

    private var icon: String {
        if profile.isHelpful {
            return "checkmark.seal.fill"
        }

        if profile.isHarmful {
            return "exclamationmark.triangle.fill"
        }

        return "scope"
    }

    private var tint: Color {
        if !profile.hasEnoughData {
            return .secondary
        }

        if profile.isHelpful {
            return .green
        }

        if profile.isHarmful {
            return .red
        }

        return .orange
    }

    private var targetLabel: String {
        switch profile.targetSignal {
        case "sleep-debt-anxiety", "high-anxiety-sleep":
            return "sono e ansiedade"
        case "sleep-debt-mood", "short-sleep-energy":
            return "sono e energia"
        case "light-exercise-anxiety":
            return "caminhada curta e ansiedade"
        case "light-exercise-mood":
            return "caminhada curta e humor"
        case "missed-medication-mood", "missed-medication-anxiety", "two-day-medication-gap-anxiety":
            return "adesão à medicação"
        default:
            return profile.targetSignal
        }
    }

    private var message: String {
        let rate = Int((profile.responseRate * 100).rounded())
        let average = String(format: "%.1f", profile.averageNetImpact)

        if !profile.hasEnoughData {
            return "Ainda calibrando: \(profile.sampleCount) execução medida para \(targetLabel). Marque quando fizer para comparar os próximos registros."
        }

        if profile.isHelpful {
            return "Resposta pessoal positiva: \(targetLabel) ajudou em \(rate)% das \(profile.sampleCount) execuções medidas."
        }

        if profile.isHarmful {
            return "Resposta pessoal sensível: impacto médio \(average). O app reduz carga e segue medindo."
        }

        return "Resposta ainda pequena: \(profile.sampleCount) execuções medidas, impacto médio \(average)."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ScaleAccessCard: View {
    @Binding var isShowingScales: Bool
    let cadence: String
    let recentAssessmentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [.neuroYellow, .neuroGold, .neuroOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-up do bem-estar")
                        .font(.headline)

                    Text("Algumas perguntas rápidas ajudam a acompanhar padrões ao longo do tempo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Label("\(recentAssessmentCount) check-ups", systemImage: "chart.bar.doc.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation {
                        isShowingScales.toggle()
                    }
                } label: {
                    Label(isShowingScales ? "Ocultar" : "Abrir", systemImage: isShowingScales ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .panelStyle()
    }
}

// MARK: - B5: Locale-aware crisis numbers

/// Maps a device-locale region code to the primary crisis hotline and
/// emergency medical number for that country. Falls back to the Brazilian
/// defaults (CVV 188 / SAMU 192) when the region is unknown.
struct CrisisNumbers {
    let crisisNumber: String   // mental-health / suicide prevention
    let crisisName: String
    let crisisSubtitle: String
    let emergencyNumber: String
    let emergencyName: String
    let emergencySubtitle: String

    static var forCurrentLocale: CrisisNumbers {
        let region = Locale.current.region?.identifier ?? "BR"
        return lookup(region: region)
    }

    static func lookup(region: String) -> CrisisNumbers {
        switch region {
        case "BR":
            return CrisisNumbers(
                crisisNumber: "188", crisisName: "CVV (188)",
                crisisSubtitle: "Centro de Valorização da Vida — 24h, gratuito.",
                emergencyNumber: "192", emergencyName: "SAMU (192)",
                emergencySubtitle: "Emergência médica — risco imediato à vida."
            )
        case "US":
            return CrisisNumbers(
                crisisNumber: "988", crisisName: "988 Suicide & Crisis Lifeline",
                crisisSubtitle: "Free, confidential — 24/7.",
                emergencyNumber: "911", emergencyName: "Emergency (911)",
                emergencySubtitle: "Medical emergency — immediate risk to life."
            )
        case "GB":
            return CrisisNumbers(
                crisisNumber: "116123", crisisName: "Samaritans (116 123)",
                crisisSubtitle: "Free, confidential — 24/7.",
                emergencyNumber: "999", emergencyName: "Emergency (999)",
                emergencySubtitle: "Medical emergency — immediate risk to life."
            )
        case "PT":
            return CrisisNumbers(
                crisisNumber: "213544545", crisisName: "SOS Voz Amiga (213 544 545)",
                crisisSubtitle: "Apoio emocional — 15h30–00h.",
                emergencyNumber: "112", emergencyName: "Emergência (112)",
                emergencySubtitle: "Emergência médica — risco imediato à vida."
            )
        case "AR":
            return CrisisNumbers(
                crisisNumber: "135", crisisName: "Centro de Asistencia al Suicida (135)",
                crisisSubtitle: "Gratuito, confidencial — 24h.",
                emergencyNumber: "107", emergencyName: "SAME (107)",
                emergencySubtitle: "Emergencia médica — riesgo inmediato de vida."
            )
        case "MX":
            return CrisisNumbers(
                crisisNumber: "800290000", crisisName: "SAPTEL (800 290 0024)",
                crisisSubtitle: "Gratuito, confidencial — 24h.",
                emergencyNumber: "911", emergencyName: "Emergencia (911)",
                emergencySubtitle: "Emergencia médica — riesgo inmediato de vida."
            )
        case "DE":
            return CrisisNumbers(
                crisisNumber: "0800111 0111", crisisName: "Telefonseelsorge (0800 111 0 111)",
                crisisSubtitle: "Kostenlos, vertraulich — 24/7.",
                emergencyNumber: "112", emergencyName: "Notruf (112)",
                emergencySubtitle: "Medizinischer Notfall — unmittelbare Lebensgefahr."
            )
        case "FR":
            return CrisisNumbers(
                crisisNumber: "3114", crisisName: "Numéro National Prévention Suicide (3114)",
                crisisSubtitle: "Gratuit, confidentiel — 24h/24.",
                emergencyNumber: "15", emergencyName: "SAMU (15)",
                emergencySubtitle: "Urgence médicale — risque vital immédiat."
            )
        case "ES":
            return CrisisNumbers(
                crisisNumber: "024", crisisName: "Línea de Atención a la Conducta Suicida (024)",
                crisisSubtitle: "Gratuito, confidencial — 24h.",
                emergencyNumber: "112", emergencyName: "Emergencia (112)",
                emergencySubtitle: "Emergencia médica — riesgo inmediato de vida."
            )
        case "AU":
            return CrisisNumbers(
                crisisNumber: "131114", crisisName: "Lifeline (13 11 14)",
                crisisSubtitle: "Free, confidential — 24/7.",
                emergencyNumber: "000", emergencyName: "Emergency (000)",
                emergencySubtitle: "Medical emergency — immediate risk to life."
            )
        default:
            // International fallback: IASP member network info page
            return CrisisNumbers(
                crisisNumber: "188", crisisName: "Linha de Crise (188)",
                crisisSubtitle: "Ligue para o serviço de crise local.",
                emergencyNumber: "192", emergencyName: "Emergência (192)",
                emergencySubtitle: "Emergência médica — risco imediato à vida."
            )
        }
    }
}

struct CrisisSupportCard: View {
    let safetyContact: String
    let warningSigns: String
    let strategies: String
    var protocolSummary: ClinicalAlertProtocol?

    private var trustedNumberDigits: String {
        safetyContact.filter { $0.isNumber }
    }

    private var trustedTelURL: URL? {
        let digits = trustedNumberDigits
        guard digits.count >= 8 else { return nil }
        return URL(string: "tel://\(digits)")
    }

    // B5 — resolve numbers at view creation time so the card always reflects
    // the current device locale without hardcoding BR numbers.
    private let numbers = CrisisNumbers.forCurrentLocale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Plano de segurança", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text("Você marcou um sinal de risco. Este app não substitui atendimento de emergência. Procure uma pessoa de confiança, seu médico assistente ou um serviço de urgência agora se houver risco imediato.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let protocolSummary {
                CrisisProtocolCard(protocolSummary: protocolSummary)
            }

            VStack(spacing: 8) {
                if let url = URL(string: "tel://\(numbers.crisisNumber.filter(\.isNumber))") {
                    crisisCallButton(
                        url: url,
                        title: "Ligar para \(numbers.crisisName)",
                        subtitle: numbers.crisisSubtitle,
                        tint: .red
                    )
                }

                if let url = URL(string: "tel://\(numbers.emergencyNumber.filter(\.isNumber))") {
                    crisisCallButton(
                        url: url,
                        title: numbers.emergencyName,
                        subtitle: numbers.emergencySubtitle,
                        tint: .red
                    )
                }

                if let url = trustedTelURL {
                    crisisCallButton(
                        url: url,
                        title: "Ligar para meu contato de segurança",
                        subtitle: safetyContact,
                        tint: .orange
                    )
                }
            }

            if !warningSigns.isEmpty {
                planSection(title: "Meus sinais de alerta", body: warningSigns)
            }

            if !strategies.isEmpty {
                planSection(title: "Minhas estratégias", body: strategies)
            }

            VStack(alignment: .leading, spacing: 8) {
                ClinicalSignal(icon: "person.2.fill", title: "Rede de apoio", description: "Avise alguém de confiança e evite ficar sozinho durante a crise.")
                ClinicalSignal(icon: "pills.fill", title: "Meios de risco", description: "Afaste medicamentos, objetos cortantes ou outros meios de autolesão.")
            }

            Text("Para produção, este fluxo deve ser revisado por equipe clínica e adaptado ao país/região de uso.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func crisisCallButton(url: URL, title: String, subtitle: String, tint: Color) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityHint("Abre o discador com este número")
    }

    private func planSection(title: String, body content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScaleQuestionRow: View {
    let number: Int
    let question: String
    let range: ClosedRange<Int>
    @Binding var answer: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(question)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Picker("Resposta", selection: $answer) {
                ForEach(Array(range), id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }
}

struct ScaleResultCard: View {
    let scale: ScaleKind
    let score: Int
    let interpretation: String
    let hasCriticalPHQ9Answer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Resultado de agora", systemImage: "sparkline")
                    .font(.headline)

                Spacer()

                Text("\(score) pontos")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.orange)
            }

            Text(interpretation)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(resultColor)

            Text(scoreRangeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if hasCriticalPHQ9Answer {
                Label("Item 9 positivo: requer revisão clínica prioritária.", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var resultColor: Color {
        switch scale {
        case .phq9:
            score >= 20 ? .red : score >= 10 ? .orange : .green
        case .gad7:
            score >= 15 ? .red : score >= 10 ? .orange : .green
        case .ymrs:
            score >= 22 ? .red : score >= 13 ? .orange : .green
        }
    }

    private var scoreRangeDescription: String {
        switch scale {
        case .phq9:
            "PHQ-9: 0-4 mínimo, 5-9 leve, 10-14 moderado, 15-19 moderadamente grave, 20-27 grave."
        case .gad7:
            "GAD-7: 0-4 mínimo, 5-9 leve, 10-14 moderado, 15-21 grave."
        case .ymrs:
            "YMRS: 11 itens, total 0-60. Faixas operacionais no app: 0-12 mínimo/ausente, 13-21 leve a moderado, 22+ marcado a grave."
        }
    }
}

struct RiskSummaryCard: View {
    let summary: LongitudinalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Classificação longitudinal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(summary.riskLevel.rawValue)
                        .font(.title.weight(.bold))
                }

                Spacer()

                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(color)
            }

            HStack(spacing: 10) {
                StatBadge(title: "Sono médio", value: "\(String(format: "%.1f", summary.averageSleep))h", icon: "moon.zzz")
                StatBadge(title: "Adesão", value: "\(String(format: "%.0f", summary.medicationAdherence * 100))%", icon: "pills")
            }

            Text("IA e regras clínicas são usadas exclusivamente como apoio à decisão. Diagnóstico e conduta permanecem responsabilidade do profissional de saúde.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var color: Color {
        switch summary.riskLevel {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct EpisodePipelineCard: View {
    let forecasts: [ClinicalEpisodeForecast]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Pipeline de episódio", systemImage: "waveform.path.ecg")
                .font(.headline)

            if forecasts.isEmpty {
                ClinicalSignal(
                    icon: "checkmark.shield",
                    title: "Sem episódio prioritário",
                    description: "O backend local não encontrou combinação temporal forte para mania, depressão, ansiedade, suicídio, adesão ou ritmo circadiano."
                )
            } else {
                ForEach(forecasts) { forecast in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(forecast.kind.rawValue)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(forecast.level.rawValue) • \(Int((forecast.confidence * 100).rounded()))%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(color(for: forecast.level))
                        }

                        Text("\(forecast.window): \(forecast.drivers.joined(separator: " • "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let comparison = forecast.comparison {
                            Label(comparison, systemImage: "clock.arrow.circlepath")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }

    private func color(for level: ClinicalRiskLevel) -> Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct TemporalRiskPredictionCard: View {
    let prediction: TemporalRiskPrediction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Modelo preditivo temporal", systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    Text("\(prediction.source.rawValue) • \(prediction.modelVersion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(prediction.primaryScore)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(prediction.primaryLevel.rawValue)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(color(for: prediction.primaryLevel))
                .accessibilityLabel("Risco predito \(prediction.primaryScore) de 100 para \(prediction.primaryWindow).")
            }

            HStack(spacing: 10) {
                TemporalRiskWindowPill(
                    title: "7 dias",
                    score: prediction.sevenDayRiskScore,
                    level: prediction.sevenDayLevel
                )
                TemporalRiskWindowPill(
                    title: "14 dias",
                    score: prediction.fourteenDayRiskScore,
                    level: prediction.fourteenDayLevel
                )
            }

            if !prediction.drivers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Drivers do modelo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(prediction.drivers, id: \.self) { driver in
                        Label(driver, systemImage: "arrow.up.forward.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !prediction.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Evidência longitudinal")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(prediction.evidence.prefix(3), id: \.self) { item in
                        Text(item)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                Label("\(prediction.longitudinalSampleCount) registros", systemImage: "calendar")
                Label("Conf. \(Int((prediction.confidence * 100).rounded()))%", systemImage: "gauge.with.dots.needle.67percent")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func color(for level: ClinicalRiskLevel) -> Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct BackendModelValidationCard: View {
    let report: BackendModelValidationReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "checkmark.seal", title: "Validação preditiva")

            if let report {
                Text("\(report.modelVersion) • treinado em \(report.trainedAt.prefix(10))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    StatBadge(title: "Sens. 7 dias", value: percent(report.sensitivitySevenDay), icon: "7.circle")
                    StatBadge(title: "Sens. 14 dias", value: percent(report.sensitivityFourteenDay), icon: "14.circle")
                    StatBadge(title: "Falso positivo", value: percent(report.falsePositiveRate), icon: "exclamationmark.triangle")
                    StatBadge(title: "Lead time", value: String(format: "%.1fd", report.medianLeadTimeDays), icon: "clock.arrow.circlepath")
                    StatBadge(title: "Pacientes", value: "\(report.patientCount)", icon: "person.3")
                    StatBadge(title: "Episódios", value: "\(report.episodeCount)", icon: "waveform.path.ecg.rectangle")
                }

                Text(report.calibrationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Aguardando backend treinado com série longitudinal real. O app mantém fallback local, mas a validação de sensibilidade, falso positivo e lead time precisa vir do servidor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

struct ClinicalDailyDigestCard: View {
    let digest: ClinicalDailyDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "doc.text.magnifyingglass", title: "Digest clínico diário")
                    Text(digest.title)
                        .font(.subheadline.weight(.semibold))
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(digest.priorityScore)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(digest.priorityLevel.rawValue)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(color(for: digest.priorityLevel))
            }

            Text(digest.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ClinicalSignal(
                icon: "phone.badge.waveform",
                title: "Ação sugerida",
                description: digest.recommendedClinicianAction
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Trilha de auditoria")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(digest.auditTrail, id: \.self) { item in
                    Label(item, systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Escopo: \(digest.consentScope.joined(separator: " • "))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func color(for level: ClinicalRiskLevel) -> Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

private struct TemporalRiskWindowPill: View {
    let title: String
    let score: Int
    let level: ClinicalRiskLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("\(score)/100")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(level.rawValue)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var color: Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct TextRiskCard: View {
    let title: String
    let assessment: TextRiskAssessment
    var patientStyle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: patientStyle ? "text.bubble" : "text.magnifyingglass")
                    .font(.headline)

                Spacer()

                Text(patientStyle ? friendlyLevel : assessment.level.rawValue)
                    .font(.headline)
                    .foregroundStyle(color)
            }

            Text(assessment.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !assessment.detectedTerms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(patientStyle ? "Pontos de atenção" : "Termos detectados")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(items: assessment.detectedTerms)
                }
            }

            Text(assessment.recommendation)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)

            Text(patientStyle ? "Esse retorno é só um apoio. Em situação urgente, procure ajuda imediatamente." : "Classificação automatizada de apoio; não substitui avaliação clínica.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var friendlyLevel: String {
        switch assessment.level {
        case .low:
            "Tranquilo"
        case .moderate:
            "Atenção"
        case .high:
            "Prioritário"
        }
    }

    private var color: Color {
        switch assessment.level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

struct AccessGateCard: View {
    let activeRole: AccessRole
    let hasSharingConsent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Acesso médico bloqueado", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Sprint A: a "aba Segurança" não existe — desde Sprint 19 as tabs
            // raiz são Hoje / Corpo / Evolução / Ferramentas, e o perfil de
            // acesso vive em Configurações.
            Text("Acesse Configurações → Perfil de acesso para alternar para o perfil médico e habilitar compartilhamento autorizado.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private var message: String {
        if activeRole != .clinician {
            return "O perfil atual é \(activeRole.rawValue). Dados clínicos consolidados exigem perfil médico."
        }

        if !hasSharingConsent {
            return "O paciente ainda não autorizou o compartilhamento de relatórios com o médico assistente."
        }

        return "Acesso indisponível."
    }
}

struct PrivacyStatusGrid: View {
    let consentAccepted: Bool
    let shareWithClinician: Bool
    let shareWithCaregiver: Bool
    let activeRole: AccessRole

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
            PrivacyStatusCard(title: "Registro local", isActive: consentAccepted, icon: "tray.and.arrow.down")
            PrivacyStatusCard(title: "Médico", isActive: shareWithClinician, icon: "stethoscope")
            PrivacyStatusCard(title: "Cuidador", isActive: shareWithCaregiver, icon: "person.crop.circle.badge.heart")
            PrivacyStatusCard(title: "Perfil", value: activeRole.rawValue, icon: activeRole.icon)
            PrivacyStatusCard(title: "Dashboard médico", isActive: activeRole == .clinician && shareWithClinician, icon: "stethoscope")
        }
    }
}

struct PrivacyStatusCard: View {
    let title: String
    var isActive: Bool?
    var value: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(displayValue)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var displayValue: String {
        if let value {
            return value
        }

        return isActive == true ? "Ativo" : "Bloqueado"
    }

    private var color: Color {
        if value != nil {
            return .neuroYellow
        }

        return isActive == true ? .green : .orange
    }
}

struct RemotePatientSnapshotCard: View {
    let patient: BackendUser
    let checkIns: [BackendDailyCheckIn]
    let assessments: [BackendScaleAssessment]
    let alerts: [BackendClinicalAlert]
    let reports: [BackendClinicalReport]
    let tasks: [BackendClinicalTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visão remota")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(patient.fullName)
                        .font(.headline)
                }

                Spacer()

                Image(systemName: "externaldrive.connected.to.line.below")
                    .foregroundStyle(.orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                StatBadge(title: "Registros", value: "\(checkIns.count)", icon: "calendar")
                StatBadge(title: "Escalas", value: "\(assessments.count)", icon: "checklist.checked")
                StatBadge(title: "Alertas", value: "\(openAlerts.count)", icon: "bell.badge")
                StatBadge(title: "Relatórios", value: "\(reports.count)", icon: "doc.text")
                StatBadge(title: "Tarefas", value: "\(openTasks.count)", icon: "checklist")
            }

            if let latestCheckIn = checkIns.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Último registro")
                        .font(.subheadline.weight(.semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                        Label("Humor \(String(format: "%.1f", latestCheckIn.mood))", systemImage: "face.smiling")
                        Label("Ansiedade \(String(format: "%.1f", latestCheckIn.anxiety))", systemImage: "waveform.path.ecg")
                        Label("Sono \(String(format: "%.1f", latestCheckIn.sleepHours))h", systemImage: "moon.zzz")
                        Label(latestCheckIn.medicationTaken ? "Medicação sim" : "Medicação não", systemImage: "pills")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !assessments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scores recentes")
                        .font(.subheadline.weight(.semibold))

                    ForEach(assessments.prefix(3)) { assessment in
                        HStack {
                            Text(assessment.scaleName)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(assessment.score) · \(assessment.interpretation)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !openAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alertas abertos")
                        .font(.subheadline.weight(.semibold))

                    ForEach(openAlerts.prefix(3)) { alert in
                        Label(alert.title, systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(alert.level == "high" ? .red : .orange)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !openTasks.isEmpty {
                RemoteClinicalTasksCard(tasks: openTasks)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var openAlerts: [BackendClinicalAlert] {
        alerts.filter { !$0.acknowledged }
    }

    private var openTasks: [BackendClinicalTask] {
        tasks.filter { $0.resolvedAt == nil && $0.status.lowercased() != "resolved" }
    }
}

struct RemoteClinicalTasksCard: View {
    let tasks: [BackendClinicalTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tarefas clínicas abertas")
                .font(.subheadline.weight(.semibold))

            ForEach(tasks.prefix(4)) { task in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: task.priority))
                        .foregroundStyle(color(for: task.priority))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.caption.weight(.semibold))
                        Text(taskSubtitle(task))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func taskSubtitle(_ task: BackendClinicalTask) -> String {
        [
            "Status: \(task.status)",
            task.contactStatus.map { "Contato: \($0)" },
            task.assignedClinicianName.map { "Atribuído: \($0)" },
            task.snoozedUntil.map { "Snooze até \($0.prefix(10))" }
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func icon(for priority: String) -> String {
        priority.lowercased() == "high" ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark"
    }

    private func color(for priority: String) -> Color {
        priority.lowercased() == "high" ? .red : .orange
    }
}

struct FlowLayout: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct TrendMetricCard: View {
    let title: String
    let icon: String
    let firstValue: Double?
    let latestValue: Double?
    let trend: Double
    let unit: String
    let higherIsBetter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(display(latestValue))
                    .font(.title3.weight(.bold).monospacedDigit())

                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(changeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(changeColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("Inicial: \(display(firstValue))\(unit)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var changeText: String {
        if firstValue == nil || latestValue == nil {
            return "Sem dados suficientes"
        }

        if abs(trend) < 0.05 {
            return "Tendência estável"
        }

        let direction = trend > 0 ? "subindo" : "caindo"
        return "\(direction.capitalized) \(String(format: "%.2f", abs(trend))) por registro"
    }

    private var changeColor: Color {
        if firstValue == nil || latestValue == nil || abs(trend) < 0.05 {
            return .secondary
        }

        let improved = higherIsBetter ? trend > 0 : trend < 0
        return improved ? .green : .orange
    }

    private func display(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        return String(format: "%.1f", value)
    }
}

struct ClinicalSignal: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct DailyCoachCard: View {
    let checkIns: [DailyCheckIn]
    let sleepHours: Double
    let currentHRV: Double
    let hrvBaseline: Double
    let ppgStress: Double
    let ppgQuality: Double
    let mood: Double
    let anxiety: Double
    let energy: Double
    let irritability: Double
    let medicationStatus: MedicationStatus
    let steps: Int
    let healthKitSnapshots: [HealthKitDailySnapshot]
    let lastHealthKitSyncAt: Date?
    let recommendation: ClinicalDailyRecommendation
    let recommendationLog: DailyRecommendationLog?
    let responseProfile: RecommendationResponseProfile?
    let retentionProfile: PersonalRetentionProfile
    let markRecommendationCompleted: () -> Void

    private var insight: DailyCoachInsight {
        DailyCoachEngine.compute(
            checkIns: checkIns,
            currentSleepHours: sleepHours,
            currentHRV: currentHRV,
            hrvBaseline: hrvBaseline,
            ppgStress: ppgStress,
            ppgQuality: ppgQuality,
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            medicationStatus: medicationStatus,
            steps: steps,
            healthKitSnapshots: healthKitSnapshots,
            lastHealthKitSyncAt: lastHealthKitSyncAt
        )
    }

    private var narratives: [DailyRetentionNarrative] {
        DailyRetentionNarrativeEngine.compute(
            checkIns: checkIns,
            currentSleepHours: sleepHours,
            currentHRV: currentHRV,
            hrvBaseline: hrvBaseline,
            ppgStress: ppgStress,
            ppgQuality: ppgQuality,
            mood: mood,
            anxiety: anxiety,
            recommendation: recommendation,
            responseProfile: responseProfile
        )
    }

    private var tint: Color {
        switch insight.band {
        case .ready:
            .green
        case .strained:
            .orange
        case .lowRecovery:
            .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "waveform.path.ecg.rectangle", title: "Neuremia Score")
                    Text(insight.headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.neuroTextOnNavy.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(insight.neuremiaScore)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(insight.band.label)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color.neuroScoreHighlight)
                .accessibilityLabel("Neuremia Score \(insight.neuremiaScore) de 100. \(insight.band.label).")
            }

            if let topDriver = insight.drivers.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: topDriver.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(topDriver.impact > 0 ? Color.neuroScoreHighlight : .green)
                        .frame(width: 18)
                    Text(topDriver.text)
                        .font(.caption)
                        .foregroundStyle(Color.neuroTextOnNavy.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(Color.neuroCardOnDark.opacity(0.96), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.neuroScoreHighlight.opacity(0.42), lineWidth: 1)
        }
        .foregroundStyle(Color.neuroTextOnNavy)
    }

    private func color(for level: ClinicalRiskLevel) -> Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .neuroYellow
        case .high:
            .red
        }
    }
}

struct PersonalRetentionModelCard: View {
    let profile: PersonalRetentionProfile

    private var tint: Color {
        color(for: profile.vulnerabilityLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(icon: "person.crop.circle.badge.checkmark", title: "O que aprendi sobre você")
                    Text(profile.stageTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(profile.stageDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(profile.learningScore)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("aprendizado")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.blue)
                .accessibilityLabel("Score de aprendizado pessoal \(profile.learningScore) de 100.")
            }

            HStack(spacing: 10) {
                RetentionMetricPill(
                    title: "Vulnerabilidade",
                    value: "\(profile.vulnerabilityScore)/100",
                    subtitle: profile.vulnerabilityLevel.rawValue,
                    icon: "shield.lefthalf.filled",
                    tint: tint
                )
                RetentionMetricPill(
                    title: "Janela",
                    value: profile.predictionWindow,
                    subtitle: "previsão",
                    icon: "calendar.badge.clock",
                    tint: .purple
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Próximo passo mais específico")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(profile.nextBestAction)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.nextBestActionReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if profile.patterns.isEmpty {
                RetentionEmptyLearningRow(
                    icon: "chart.xyaxis.line",
                    title: "Padrões ainda em formação",
                    detail: "Com mais check-ins, o app compara sono, humor, ansiedade, medicação e texto para descobrir relações pessoais."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Padrões pessoais")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(profile.patterns) { pattern in
                        PersonalRetentionPatternRow(pattern: pattern)
                    }
                }
            }

            if profile.interventionLearnings.isEmpty {
                RetentionEmptyLearningRow(
                    icon: "target",
                    title: "Resposta a intervenções em medição",
                    detail: "Quando você marca uma recomendação como feita, os próximos registros mostram se ela ajudou, foi neutra ou pesou demais."
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resposta a intervenções")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    ForEach(profile.interventionLearnings.prefix(3)) { learning in
                        PersonalInterventionLearningRow(learning: learning)
                    }
                }
            }

            Label(profile.dataCoverageText, systemImage: "lock.doc")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    private func color(for level: ClinicalRiskLevel) -> Color {
        switch level {
        case .low:
            .green
        case .moderate:
            .orange
        case .high:
            .red
        }
    }
}

private struct RetentionMetricPill: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalRetentionPatternRow: View {
    let pattern: PersonalRetentionPattern

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: pattern.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(pattern.title)
                    .font(.caption.weight(.bold))
                Text(pattern.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pattern.evidence)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch pattern.tintName {
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "indigo": .indigo
        case "blue": .blue
        default: .accentColor
        }
    }
}

private struct PersonalInterventionLearningRow: View {
    let learning: PersonalInterventionLearning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: learning.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(learning.title)
                    .font(.caption.weight(.bold))
                Text(learning.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(learning.evidence)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch learning.tintName {
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        case "indigo": .indigo
        case "blue": .blue
        default: .accentColor
        }
    }
}

private struct RetentionEmptyLearningRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CheckInRow: View {
    let checkIn: DailyCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(checkIn.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                Label("Humor \(String(format: "%.1f", checkIn.mood))", systemImage: "face.smiling")
                Label("Ansiedade \(String(format: "%.1f", checkIn.anxiety))", systemImage: "waveform.path.ecg")
                Label("Sono \(String(format: "%.1f", checkIn.sleepHours))h", systemImage: "moon.zzz")
                Label(checkIn.medicationTaken ? "Medicação sim" : "Medicação não", systemImage: "pills")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if checkIn.suicidalIdeation {
                Label("Triagem positiva para ideação suicida", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if !checkIn.sideEffects.isEmpty {
                HistoryNote(title: "Efeitos colaterais", text: checkIn.sideEffects)
            }

            if !checkIn.automaticThoughts.isEmpty {
                HistoryNote(title: "Pensamentos", text: checkIn.automaticThoughts)
            }

            if !checkIn.journalEntry.isEmpty {
                HistoryNote(title: "Diário", text: checkIn.journalEntry)
            }
        }
        .panelStyle()
    }
}

struct HistoryNote: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.footnote)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AssessmentRow: View {
    let assessment: ScaleAssessment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.scaleName)
                    .font(.headline)

                Text("\(assessment.score) pontos · \(assessment.interpretation)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(assessment.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

struct AlertRow: View {
    let alert: ClinicalAlert
    let markContacted: () -> Void
    let markFalsePositive: () -> Void
    let escalate: () -> Void

    private var protocolSummary: ClinicalAlertProtocol {
        ClinicalAlertProtocol.from(alert: alert)
    }

    private var workflowStatus: ClinicalAlertWorkflowStatus {
        ClinicalAlertWorkflowStatus(rawValue: alert.workflowStatus) ?? (alert.acknowledged ? .resolved : .open)
    }

    private var contactStatus: ClinicalAlertContactStatus {
        ClinicalAlertContactStatus(rawValue: alert.contactStatus) ?? .notStarted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(alert.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(alert.level == ClinicalRiskLevel.high.rawValue ? .red : .orange)

            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ProtocolLine(icon: "checklist", text: "Status: \(workflowStatus.label)")
                ProtocolLine(icon: "phone.connection", text: contactStatus.label)
                if let acknowledgedAt = alert.acknowledgedAt {
                    ProtocolLine(icon: "checkmark.seal", text: "Confirmação: \(acknowledgedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if let escalatedAt = alert.escalatedAt {
                    ProtocolLine(icon: "arrow.up.right.circle", text: "Escalado: \(escalatedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if let resolvedAt = alert.resolvedAt {
                    ProtocolLine(icon: "checkmark.circle", text: "Fechado: \(resolvedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                if !alert.workflowNote.isEmpty {
                    ProtocolLine(icon: "note.text", text: alert.workflowNote)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                ProtocolLine(icon: "person.2.fill", text: protocolSummary.recipients)
                ProtocolLine(icon: "clock.badge.exclamationmark", text: protocolSummary.responseWindow)
                ProtocolLine(icon: "checkmark.seal", text: protocolSummary.acknowledgement)
                ProtocolLine(icon: "arrow.up.right.circle", text: protocolSummary.escalation)
                ProtocolLine(icon: "exclamationmark.triangle", text: protocolSummary.falsePositiveHandling)
                ProtocolLine(icon: "doc.text.magnifyingglass", text: protocolSummary.legalLimit)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("Contato feito", action: markContacted)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                Button("Falso positivo", action: markFalsePositive)
                    .buttonStyle(.bordered)

                Button("Escalar", action: escalate)
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .controlSize(.small)
        }
        .panelStyle()
    }
}

private struct CrisisProtocolCard: View {
    let protocolSummary: ClinicalAlertProtocol

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Protocolo deste alerta", systemImage: "checklist.checked")
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
            ProtocolLine(icon: "person.2.fill", text: protocolSummary.recipients)
            ProtocolLine(icon: "clock.badge.exclamationmark", text: protocolSummary.responseWindow)
            ProtocolLine(icon: "arrow.up.right.circle", text: protocolSummary.escalation)
            ProtocolLine(icon: "doc.text.magnifyingglass", text: protocolSummary.legalLimit)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProtocolLine: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ComplianceRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ClinicalSignal(icon: icon, title: title, description: description)
    }
}

struct ClinicalOperationsQueueCard: View {
    let tasks: [BackendClinicalTask]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "tray.full", title: "Fila operacional")

            if openTasks.isEmpty {
                Text("Sem tarefas abertas no backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openTasks.prefix(5)) { task in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: task.priority.lowercased() == "high" ? "exclamationmark.octagon.fill" : "clock.badge.exclamationmark")
                            .foregroundStyle(task.priority.lowercased() == "high" ? .red : .orange)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(task.patientName)
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Text(task.status.capitalized)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(task.title)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(taskMeta(task))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .panelStyle()
    }

    private var openTasks: [BackendClinicalTask] {
        tasks
            .filter { $0.resolvedAt == nil && $0.status.lowercased() != "resolved" }
            .sorted { priorityRank($0.priority) > priorityRank($1.priority) }
    }

    private func taskMeta(_ task: BackendClinicalTask) -> String {
        [
            task.contactStatus.map { "Contato: \($0)" },
            task.assignedClinicianName.map { "Responsável: \($0)" },
            task.dueAt.map { "Prazo: \($0.prefix(10))" },
            task.snoozedUntil.map { "Snooze: \($0.prefix(10))" }
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority.lowercased() {
        case "critical", "high":
            3
        case "moderate", "medium":
            2
        default:
            1
        }
    }
}

struct ClinicianPopulationRiskCard: View {
    let signature: NeuremiaRiskSignature
    let alerts: [ClinicalAlert]
    let checkIns: [DailyCheckIn]
    let remotePatients: [BackendUser]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.3.sequence", title: "Painel populacional")

            Text("No backend real, esta visão ordena pacientes por risco. Localmente ela mostra a lógica aplicada ao paciente atual.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                StatBadge(title: "Risco Neuremia", value: "\(signature.score)/100", icon: "brain.head.profile")
                StatBadge(title: "Alertas abertos", value: "\(alerts.count)", icon: "bell.badge")
                StatBadge(title: "Piorou semana", value: worsenedThisWeek ? "Sim" : "Não", icon: "chart.line.downtrend.xyaxis")
                StatBadge(title: "Contato antes consulta", value: shouldContact ? "Priorizar" : "Rotina", icon: "phone.badge.waveform")
                StatBadge(title: "Pacientes remotos", value: "\(remotePatients.count)", icon: "person.2")
                StatBadge(title: "Com risco remoto", value: "\(remotePatients.filter { $0.riskScore != nil }.count)", icon: "list.number")
            }

            if remotePatients.contains(where: { $0.riskScore != nil }) {
                Text("Quando o backend envia `risk_score`, a lista de pacientes é ordenada automaticamente por prioridade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panelStyle()
    }

    private var worsenedThisWeek: Bool {
        let recent = Array(checkIns.prefix(7))
        guard recent.count >= 3 else { return false }
        return recent.contains { $0.mood <= 2 || $0.anxiety >= 4 || $0.sleepHours < 5 || $0.suicidalIdeation }
    }

    private var shouldContact: Bool {
        signature.level == .high || alerts.contains { $0.level == ClinicalRiskLevel.high.rawValue }
    }
}

struct ClinicianPreConsultInsightCard: View {
    let summary: LongitudinalSummary
    let checkIns: [DailyCheckIn]
    let assessments: [ScaleAssessment]
    let medicationPlans: [MedicationPlanEntry]
    let signature: NeuremiaRiskSignature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "doc.text.magnifyingglass", title: "Resumo pré-consulta")

            Text("Síntese automática para orientar a conversa clínica. Deve ser revisada pelo profissional.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ClinicalSignal(icon: "gauge.with.dots.needle.67percent", title: "Risco atual: \(summary.riskLevel.rawValue)", description: summary.textAssessment.recommendation)
                ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: "Mudança longitudinal", description: longitudinalText)
                ClinicalSignal(icon: "pills", title: "Medicação", description: medicationText)
                ClinicalSignal(icon: "tag", title: "Gatilhos recorrentes", description: triggerText)
                ClinicalSignal(icon: "bandage", title: "Efeitos colaterais recentes", description: sideEffectsText)
                ClinicalSignal(icon: "heart.text.square", title: "Escalas recentes", description: recentScalesText)
                ClinicalSignal(icon: "percent", title: "Sintomas que mais pioraram", description: symptomWorseningText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Perguntas sugeridas")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                ForEach(suggestedQuestions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .panelStyle()
    }

    private var longitudinalText: String {
        var parts: [String] = []
        if summary.moodTrend < -0.25 {
            parts.append("humor em queda")
        }
        if summary.anxietyTrend > 0.25 {
            parts.append("ansiedade em alta")
        }
        if summary.sleepTrend < -0.25 {
            parts.append("sono reduzindo")
        }
        return parts.isEmpty ? "Sem tendência crítica clara nos registros analisados." : parts.joined(separator: ", ").capitalized + "."
    }

    private var medicationText: String {
        let changes = medicationPlans
            .map(\.changeNote)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !changes.isEmpty {
            return "Há alteração de medicação/dose registrada; revisar temporalidade com sintomas."
        }
        if summary.medicationAdherence < 0.8, summary.analyzedCheckInCount >= 3 {
            return "Adesão inferior a 80% nos registros analisados."
        }
        return medicationPlans.isEmpty ? "Nenhuma medicação cadastrada no app." : "Medicações cadastradas sem mudança recente registrada."
    }

    private var triggerText: String {
        let triggers = checkIns.flatMap { triggerLabels(from: $0.journalEntry) }
        guard let mostCommon = Dictionary(grouping: triggers, by: { $0 }).mapValues(\.count).max(by: { $0.value < $1.value }) else {
            return "Ainda não há gatilho recorrente suficiente."
        }
        return "\(mostCommon.key) foi o gatilho mais frequente nos registros com contexto."
    }

    private var sideEffectsText: String {
        let recent = checkIns
            .prefix(7)
            .map(\.sideEffects)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !recent.isEmpty else {
            return "Nenhum efeito colateral recente registrado."
        }
        return Array(Set(recent)).prefix(3).joined(separator: " • ")
    }

    private var recentScalesText: String {
        let recent = assessments.prefix(3)
        guard !recent.isEmpty else {
            return "Nenhuma escala recente salva."
        }
        return recent
            .map { "\($0.scaleName): \($0.score) (\($0.interpretation))" }
            .joined(separator: " • ")
    }

    private var symptomWorseningText: String {
        let chronological = checkIns.sorted { $0.date < $1.date }
        guard let first = chronological.first, let latest = chronological.last, chronological.count >= 2 else {
            return "Sem dados suficientes para calcular porcentagem de piora."
        }

        let changes = [
            worseningPercent(title: "ansiedade", first: first.anxiety, latest: latest.anxiety, higherIsWorse: true),
            worseningPercent(title: "irritabilidade", first: first.irritability, latest: latest.irritability, higherIsWorse: true),
            worseningPercent(title: "humor", first: first.mood, latest: latest.mood, higherIsWorse: false),
            worseningPercent(title: "sono", first: first.sleepHours, latest: latest.sleepHours, higherIsWorse: false),
            worseningPercent(title: "energia", first: first.energy, latest: latest.energy, higherIsWorse: false)
        ]
        .compactMap { $0 }
        .sorted { $0.percent > $1.percent }

        guard !changes.isEmpty else {
            return "Sem piora percentual relevante desde o primeiro registro."
        }
        return changes.prefix(3)
            .map { "\($0.title) +\(Int($0.percent.rounded()))%" }
            .joined(separator: " • ")
    }

    private var suggestedQuestions: [String] {
        var questions: [String] = []
        if signature.factors.contains(where: { $0.contains("sono") }) {
            questions.append("O que mudou na rotina de sono nos últimos dias?")
        }
        if signature.factors.contains(where: { $0.contains("medicação") || $0.contains("adesão") }) {
            questions.append("Houve esquecimento, efeito colateral ou dificuldade com a medicação?")
        }
        if signature.factors.contains(where: { $0.contains("gatilhos") }) {
            questions.append("Quais gatilhos apareceram antes dos dias de piora?")
        }
        if sideEffectsText != "Nenhum efeito colateral recente registrado." {
            questions.append("Os efeitos colaterais recentes coincidem com mudança de dose ou adesão?")
        }
        if recentScalesText != "Nenhuma escala recente salva." {
            questions.append("O resultado das escalas confirma o padrão observado no diário?")
        }
        if signature.level == .high {
            questions.append("O plano de segurança está atualizado e acessível?")
        }
        if questions.isEmpty {
            questions.append("O paciente percebe algum padrão que o app ainda não captou?")
        }
        return questions
    }

    private func worseningPercent(title: String, first: Double, latest: Double, higherIsWorse: Bool) -> (title: String, percent: Double)? {
        let delta = higherIsWorse ? latest - first : first - latest
        guard delta > 0 else { return nil }
        let denominator = max(abs(first), 0.5)
        let percent = min((delta / denominator) * 100, 999)
        guard percent >= 10 else { return nil }
        return (title, percent)
    }

    private func triggerLabels(from journal: String) -> [String] {
        journal
            .components(separatedBy: "\n")
            .first { $0.localizedCaseInsensitiveContains("Gatilhos do dia:") }?
            .replacingOccurrences(of: "Gatilhos do dia:", with: "")
            .replacingOccurrences(of: ".", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty } ?? []
    }
}

// P2-3 (UX): adicionado parâmetro opcional `actionLabel`/`action` para
// eliminar dead-ends onde o usuário sabe o que fazer mas não tem caminho
// direto. Usos existentes sem action continuam funcionando.
struct EmptyState: View {
    let text: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let label = actionLabel, let action {
                Button(action: action) {
                    Label(label, systemImage: "arrow.right.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .panelStyle()
    }
}

// Sprint 25: barra unificada de busca + filtro por tipo de evento usada na
// Tab Evolução. O TextField roda offline (filtragem em memória) e os chips
// alternam entre check-ins, escalas, alertas ou tudo.
struct EvolutionSearchFilterCard: View {
    @Binding var query: String
    @Binding var filter: EvolutionFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar no diário, escalas ou alertas", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.search)
                    .accessibilityLabel("Campo de busca da evolução")
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Limpar busca")
                }
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EvolutionFilter.allCases) { option in
                        let isSelected = option == filter
                        Button {
                            filter = option
                        } label: {
                            Label(option.rawValue, systemImage: option.icon)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isSelected ? Color.neuroYellow : Color(.secondarySystemGroupedBackground))
                                .foregroundStyle(isSelected ? Color.neuroNavy : Color.primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Filtro \(option.rawValue)")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
        }
        .panelStyle()
    }
}

extension View {
    func panelStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.neuroInteractiveHighlight.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: Color.neuroNavy.opacity(0.22), radius: 14, y: 6)
    }
}

// MARK: - PatientStore (Sprint E #4)
//
// Cache central para sortedCheckIns / sortedAssessments / summary. Antes do
// refactor essas computeds rodavam ~30 vezes por body (visto em hotspots
// patientEvolutionPage, doctorDashboard, patientToolsPage). Cada chamada
// fazia O(n log n) por causa do .sorted, mais o passo do ClinicalAnalysis.
//
// Estratégia minimalista: `isReady` começa false, fica true após o primeiro
// recompute disparado pelo .task(id: storeFingerprint) no body raiz. Os 3
// callsites originais (sortedCheckIns/sortedAssessments/summary computeds)
// fazem cache-first com fallback ao recompute — não foi preciso mexer nos
// ~30 callsites que consomem essas properties.
//
// Não cacheia `neuremiaRiskSignature` porque ela depende de inputs voláteis
// (mood/anxiety/ppgStress/voicePauseRatio mudam em tempo real). Mas ela
// automaticamente se beneficia ao consumir o `sortedCheckIns` já cacheado.
@Observable
final class PatientStore {
    private(set) var sortedCheckIns: [DailyCheckIn] = []
    private(set) var sortedAssessments: [ScaleAssessment] = []
    private(set) var activeAlerts: [ClinicalAlert] = []
    private(set) var latestReports: [ClinicalReport] = []
    private(set) var summary: LongitudinalSummary?
    var isReady: Bool { summary != nil }

    func recompute(
        checkIns: [DailyCheckIn],
        assessments: [ScaleAssessment],
        alerts: [ClinicalAlert],
        reports: [ClinicalReport]
    ) {
        let sortedC = checkIns.sorted { $0.date > $1.date }
        let sortedA = assessments.sorted { $0.date > $1.date }
        sortedCheckIns = sortedC
        sortedAssessments = sortedA
        activeAlerts = alerts.filter { !$0.acknowledged }.sorted { $0.date > $1.date }
        latestReports = reports.sorted { $0.date > $1.date }
        summary = ClinicalAnalysis.summary(checkIns: sortedC, assessments: sortedA)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PatientProfile.self, DailyCheckIn.self, ScaleAssessment.self, ClinicalAlert.self, ClinicalReport.self, DailyRecommendationLog.self], inMemory: true)
}
