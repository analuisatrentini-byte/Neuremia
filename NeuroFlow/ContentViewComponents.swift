//
//  ContentViewComponents.swift
//  NeuroFlow
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

struct NeuroFlowRiskSignatureCard: View {
    let signature: NeuroFlowRiskSignature

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
    let signature: NeuroFlowRiskSignature
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
    let retrySync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Sprint 22: ícone reflete o estado real. Sincronizado = nuvem
            // com check verde. Pendente = nuvem cortada laranja (cloud.slash)
            // — semânticamente "fora do alcance da nuvem agora".
            Image(systemName: pendingCount == 0 ? "checkmark.icloud.fill" : "icloud.slash.fill")
                .font(.headline)
                .foregroundStyle(pendingCount == 0 ? .green : Color.neuroOrange)
                .frame(width: 36, height: 36)
                .background((pendingCount == 0 ? Color.green : Color.neuroYellow).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(pendingCount == 0 ? "Dados protegidos" : "Aguardando sincronização")
                    .font(.subheadline.weight(.bold))
                Text(lastStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if pendingCount > 0 {
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
                    .foregroundStyle(.black)
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
    let syncHealth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "heart.text.square", title: "Fontes combinadas")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                BodySignalMetricPill(title: "Sono Health", value: sleepHours > 0 ? String(format: "%.1fh", sleepHours) : "-", icon: "moon.zzz.fill", color: .indigo)
                BodySignalMetricPill(title: "Passos", value: steps > 0 ? "\(steps)" : "-", icon: "figure.walk", color: .teal)
                BodySignalMetricPill(title: "FC Health", value: heartRate > 0 ? "\(Int(heartRate)) bpm" : "-", icon: "heart.circle.fill", color: .red)
                BodySignalMetricPill(title: "Energia", value: activeEnergy > 0 ? "\(Int(activeEnergy)) kcal" : "-", icon: "flame.fill", color: .orange)
            }

            Button(action: syncHealth) {
                Label("Sincronizar Apple Health", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
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
    let signature: NeuroFlowRiskSignature
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
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
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    addCustomTrigger()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(customTriggerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.52), color.opacity(0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 1.6)
            }
            .overlay(alignment: .topTrailing) {
                if isOn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                        .padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .scaleEffect(isOn ? 1.02 : 1)
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
    let makeBackup: () -> Void
    let restoreBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "externaldrive.badge.checkmark", title: "Backup dos dados")

            Text("Gere, compartilhe ou restaure um arquivo JSON com registros, escalas, medicações, sintomas personalizados e plano de segurança.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                Label("Gerar backup", systemImage: "arrow.down.doc")
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
                    Label("Compartilhar backup", systemImage: "square.and.arrow.up")
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

struct HealthKitIntegrationCard: View {
    @Binding var isEnabled: Bool
    let status: String
    let sleepHours: Double
    let steps: Int
    let heartRate: Double
    let activeEnergy: Double
    let sync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "heart.text.square.fill", title: "Apple Health")

            Toggle("Usar dados do Apple Health", isOn: $isEnabled)
                .toggleStyle(.switch)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                HealthMetricPill(title: "Sono", value: String(format: "%.1fh", sleepHours), icon: "moon.zzz", color: .indigo)
                HealthMetricPill(title: "Passos", value: "\(steps)", icon: "figure.walk", color: .teal)
                HealthMetricPill(title: "FC média", value: heartRate > 0 ? String(format: "%.0f bpm", heartRate) : "-", icon: "heart.fill", color: .red)
                HealthMetricPill(title: "Energia", value: activeEnergy > 0 ? String(format: "%.0f kcal", activeEnergy) : "-", icon: "flame.fill", color: .orange)
            }

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

            if !token.isEmpty {
                Text("Token recebido: \(String(token.prefix(12)))...")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

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
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Check-up do bem-estar")
                        .font(.headline)
                    // P2-8 (UX): subtitle reforça natureza estimada antes de
                    // o paciente ver as pontuações, prevenindo interpretação
                    // incorreta como resultado clínico válido.
                    Text("Estimativa baseada nos seus sliders — não substitui avaliação formal.")
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
                Label("Salvar check-up automático", systemImage: "checkmark.circle")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(status.emoji)
                    .font(.system(size: 34))
                    .frame(width: 54, height: 54)
                    .background(status.color.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Medicação")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(MedicationStatus.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            status = option
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(status == option ? option.color.opacity(0.20) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SafetyStatusCard: View {
    @Binding var status: SafetyStatus
    @State private var isConfirmingUrgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(status.emoji)
                    .font(.system(size: 34))
                    .frame(width: 54, height: 54)
                    .background(status.color.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Segurança hoje")
                        .font(.headline)

                    Text(status.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
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
                        VStack(spacing: 4) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.rawValue)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(status == option ? option.color.opacity(0.20) : Color(.tertiarySystemGroupedBackground))
                        .foregroundStyle(status == option ? option.color : .secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(status == option ? option.color.opacity(0.75) : Color.clear, lineWidth: 1.5)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.10), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(status.color.opacity(0.20), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var openAlerts: [BackendClinicalAlert] {
        alerts.filter { !$0.acknowledged }
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
    let acknowledge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(alert.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(alert.level == ClinicalRiskLevel.high.rawValue ? .red : .orange)

            Text(alert.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Marcar como revisado", action: acknowledge)
                .buttonStyle(.bordered)
        }
        .panelStyle()
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

struct ClinicianPopulationRiskCard: View {
    let signature: NeuroFlowRiskSignature
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
                StatBadge(title: "Risco NeuroFlow", value: "\(signature.score)/100", icon: "brain.head.profile")
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
    let signature: NeuroFlowRiskSignature

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
                                .foregroundStyle(isSelected ? Color.black : Color.primary)
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
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
// Não cacheia `neuroFlowRiskSignature` porque ela depende de inputs voláteis
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
        .modelContainer(for: [PatientProfile.self, DailyCheckIn.self, ScaleAssessment.self, ClinicalAlert.self, ClinicalReport.self], inMemory: true)
}
