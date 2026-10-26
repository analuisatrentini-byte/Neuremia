//
//  PatientEnhancementComponents.swift
//  Neuremia
//

import SwiftUI
import Charts

struct LocalOnlyBackupReminderCard: View {
    let lastBackupAt: Double
    let intervalDays: Int
    let backupURL: URL?
    let makeBackup: () -> Void
    let restoreBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.neuroNavy)
                    .frame(width: 38, height: 38)
                    .background(Color.neuroYellow, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Proteja seus dados locais")
                        .font(.headline.weight(.bold))
                    Text(reminderText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(action: makeBackup) {
                    Label("Criar backup", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.neuroYellow)
                .foregroundStyle(Color.neuroNavy)

                Button(action: restoreBackup) {
                    Image(systemName: "arrow.up.doc")
                        .frame(width: 42, height: 36)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Restaurar backup")
            }

            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Guardar cópia fora deste aparelho", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color.neuroYellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.neuroYellow.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var reminderText: String {
        guard lastBackupAt > 0 else {
            return "Você está no modo dados apenas no aparelho. Crie um backup e guarde uma cópia segura para troca ou perda do celular."
        }
        let date = Date(timeIntervalSince1970: lastBackupAt)
        return "Último backup: \(date.formatted(date: .abbreviated, time: .shortened)). Janela configurada: \(max(1, intervalDays)) dia(s)."
    }
}

struct GuidedInterventionsLibraryCard: View {
    let careFocus: CareFocus
    let riskLevel: ClinicalRiskLevel
    @State private var selectedGuideID: String?

    private var guides: [GuidedIntervention] {
        GuidedIntervention.library(for: careFocus, riskLevel: riskLevel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "figure.mind.and.body", title: "Intervenções guiadas")

            Text("Escolha uma prática curta para o estado de agora. As sugestões ficam no aparelho e não substituem cuidado profissional.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(guides) { guide in
                GuidedInterventionRow(
                    guide: guide,
                    isExpanded: selectedGuideID == guide.id,
                    toggle: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            selectedGuideID = selectedGuideID == guide.id ? nil : guide.id
                        }
                    }
                )
            }
        }
        .panelStyle()
    }
}

private struct GuidedInterventionRow: View {
    let guide: GuidedIntervention
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: guide.icon)
                        .font(.headline)
                        .foregroundStyle(Color.neuroNavy)
                        .frame(width: 36, height: 36)
                        .background(Color.neuroYellow, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(guide.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("\(guide.duration) min · \(guide.category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abrir intervenção \(guide.title)")

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(guide.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.neuroNavy)
                                .frame(width: 20, height: 20)
                                .background(Color.neuroYellow, in: Circle())
                            Text(step)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 48)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct GuidedIntervention: Identifiable {
    let id: String
    let icon: String
    let title: String
    let category: String
    let duration: Int
    let why: String
    let steps: [String]

    static func library(for focus: CareFocus, riskLevel: ClinicalRiskLevel) -> [GuidedIntervention] {
        var base = [breathing, grounding, thoughtRecord, mindfulness, crisisPlan]
        switch focus {
        case .anxiety:
            base.insert(bodyScan, at: 1)
        case .depression, .burnout:
            base.insert(behavioralActivation, at: 2)
        case .bipolar, .adhd, .postpartum:
            base.insert(routineAnchor, at: 2)
        case .borderline:
            base.insert(distressTolerance, at: 1)
        }
        if riskLevel == .high {
            base.insert(crisisPlan, at: 0)
        }
        return Array(Dictionary(grouping: base, by: \.id).compactMap { $0.value.first }.prefix(6))
    }

    private static let breathing = GuidedIntervention(
        id: "breathing",
        icon: "lungs.fill",
        title: "Respiração 4-6",
        category: "regulação",
        duration: 3,
        why: "Útil quando há ansiedade, agitação ou sensação de aceleração corporal.",
        steps: ["Inspire pelo nariz contando até 4.", "Expire lentamente contando até 6.", "Repita por 10 ciclos, relaxando os ombros a cada expiração."]
    )

    private static let grounding = GuidedIntervention(
        id: "grounding",
        icon: "hand.raised.fill",
        title: "Grounding 5-4-3-2-1",
        category: "presença",
        duration: 4,
        why: "Ajuda quando a mente está acelerada, dissociada ou presa em ruminação.",
        steps: ["Nomeie 5 coisas que você vê.", "Toque 4 superfícies diferentes.", "Perceba 3 sons, 2 cheiros e 1 gosto ou sensação interna."]
    )

    private static let thoughtRecord = GuidedIntervention(
        id: "thought-record",
        icon: "bubble.left.and.text.bubble.right.fill",
        title: "Registro TCC rápido",
        category: "pensamento",
        duration: 5,
        why: "Transforma pensamento automático em hipótese, reduzindo certeza emocional.",
        steps: ["Escreva o pensamento principal em uma frase.", "Liste uma evidência a favor e uma contra.", "Reescreva uma versão mais equilibrada e prática."]
    )

    private static let mindfulness = GuidedIntervention(
        id: "mindfulness",
        icon: "leaf.fill",
        title: "Atenção plena curta",
        category: "mindfulness",
        duration: 3,
        why: "Serve para voltar ao corpo sem precisar resolver tudo agora.",
        steps: ["Apoie os pés no chão.", "Observe a respiração sem mudar nada por 60 segundos.", "Quando distrair, nomeie 'pensamento' e volte para o ar entrando e saindo."]
    )

    private static let crisisPlan = GuidedIntervention(
        id: "crisis-plan",
        icon: "cross.case.fill",
        title: "Plano pronto para crise",
        category: "segurança",
        duration: 2,
        why: "Quando houver risco ou perda de controle, o foco é reduzir dano e acionar suporte real.",
        steps: ["Afaste meios de risco imediato, se possível.", "Abra o plano de segurança e contate sua pessoa de confiança.", "Se houver risco de vida, ligue 188, 192 ou procure emergência."]
    )

    private static let bodyScan = GuidedIntervention(
        id: "body-scan",
        icon: "waveform.path.ecg",
        title: "Escaneamento corporal",
        category: "ansiedade",
        duration: 4,
        why: "Ajuda a diferenciar ameaça real de ativação fisiológica.",
        steps: ["Percorra testa, mandíbula, peito, abdome e mãos.", "Solte uma área tensa por vez.", "Dê uma nota de 0 a 5 para a ativação antes e depois."]
    )

    private static let behavioralActivation = GuidedIntervention(
        id: "activation",
        icon: "figure.walk",
        title: "Ativação de 10 minutos",
        category: "ação pequena",
        duration: 10,
        why: "Quando energia e humor caem, uma ação mínima pode quebrar inércia sem exigir motivação alta.",
        steps: ["Escolha uma ação física simples: banho, caminhada curta ou arrumar uma superfície.", "Use um timer de 10 minutos.", "Pare quando tocar, mesmo que não tenha terminado."]
    )

    private static let routineAnchor = GuidedIntervention(
        id: "routine-anchor",
        icon: "clock.badge.checkmark.fill",
        title: "Âncora de rotina",
        category: "estabilidade",
        duration: 5,
        why: "Sono, medicação e horários são sinais importantes para estabilidade clínica.",
        steps: ["Escolha o próximo horário fixo do dia: refeição, medicação ou sono.", "Defina uma ação concreta para proteger esse horário.", "Registre no diário se algo saiu do previsto."]
    )

    private static let distressTolerance = GuidedIntervention(
        id: "distress-tolerance",
        icon: "snowflake",
        title: "Tolerância ao pico emocional",
        category: "intensidade",
        duration: 5,
        why: "Útil para atravessar o pico sem agir por impulso.",
        steps: ["Mude a temperatura do rosto com água fria por alguns segundos.", "Faça 20 a 30 segundos de movimento intenso seguro.", "Volte para respiração lenta e adie decisões por 20 minutos."]
    )
}

struct PersonalizationHubCard: View {
    @Binding var medicationName: String
    @Binding var medicationDose: String
    @Binding var medicationSchedule: String
    @Binding var medicationPrescription: String
    @Binding var medicationChangeNote: String
    let medicationPlans: [MedicationPlanEntry]
    let addMedication: () -> Void
    let removeMedication: (MedicationPlanEntry) -> Void
    @Binding var symptomName: String
    @Binding var symptomValue: Double
    let symptoms: [CustomSymptomEntry]
    let addSymptom: () -> Void
    let removeSymptom: (CustomSymptomEntry) -> Void
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
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "slider.horizontal.3", title: "Personalizar acompanhamento")
            Text("Configure sintomas, hábitos, gatilhos e medicações para que o diário e o score reflitam melhor sua realidade.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CustomSymptomCard(
                symptomName: $symptomName,
                symptomValue: $symptomValue,
                symptoms: symptoms,
                addSymptom: addSymptom,
                removeSymptom: removeSymptom
            )

            TriggerMapCard(
                alcoholTrigger: $alcoholTrigger,
                poorSleepTrigger: $poorSleepTrigger,
                stressTrigger: $stressTrigger,
                conflictTrigger: $conflictTrigger,
                routineChangeTrigger: $routineChangeTrigger,
                menstrualTrigger: $menstrualTrigger,
                customTriggerText: $customTriggerText,
                customTriggers: $customTriggers,
                checkIns: checkIns
            )

            MedicationPlanCard(
                medicationName: $medicationName,
                medicationDose: $medicationDose,
                medicationSchedule: $medicationSchedule,
                medicationPrescription: $medicationPrescription,
                medicationChangeNote: $medicationChangeNote,
                medicationPlans: medicationPlans,
                addMedication: addMedication,
                removeMedication: removeMedication
            )
        }
        .panelStyle()
    }
}

struct SimplePatternDashboardCard: View {
    let checkIns: [DailyCheckIn]
    let currentSteps: Double

    private var recent: [DailyCheckIn] {
        Array(checkIns.sorted { $0.date < $1.date }.suffix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "chart.bar.xaxis", title: "Padrões simples")

            if recent.count < 2 {
                EmptyState(text: "Com dois ou mais registros, o app mostra relações simples entre sono, atividade, humor e ansiedade.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                    PatternStatTile(title: "Sono ↔ humor", value: sleepMoodSummary, icon: "moon.zzz.fill")
                    PatternStatTile(title: "Ansiedade", value: anxietySummary, icon: "waveform.path.ecg")
                    PatternStatTile(title: "Atividade", value: stepsSummary, icon: "figure.walk")
                    PatternStatTile(title: "Regularidade", value: regularitySummary, icon: "calendar")
                }

                Chart(recent) { item in
                    LineMark(
                        x: .value("Data", item.date),
                        y: .value("Humor", item.mood)
                    )
                    .foregroundStyle(Color.neuroYellow)
                    LineMark(
                        x: .value("Data", item.date),
                        y: .value("Ansiedade", item.anxiety)
                    )
                    .foregroundStyle(Color.red.opacity(0.75))
                }
                .frame(height: 160)
                .chartYScale(domain: 0...5)
                .accessibilityLabel("Gráfico de humor e ansiedade dos últimos registros")
            }
        }
        .panelStyle()
    }

    private var sleepMoodSummary: String {
        let goodSleep = recent.filter { $0.sleepHours >= 7 }
        let poorSleep = recent.filter { $0.sleepHours < 6 }
        guard !goodSleep.isEmpty, !poorSleep.isEmpty else { return "aguardando" }
        let goodAverage = average(goodSleep.map(\.mood))
        let poorAverage = average(poorSleep.map(\.mood))
        return goodAverage >= poorAverage ? "+\(format(goodAverage - poorAverage))" : "\(format(goodAverage - poorAverage))"
    }

    private var anxietySummary: String {
        let averageAnxiety = average(recent.map(\.anxiety))
        return "média \(format(averageAnxiety))/5"
    }

    private var stepsSummary: String {
        guard currentSteps > 0 else { return "Health off" }
        return currentSteps >= 6000 ? "ativo hoje" : "baixo hoje"
    }

    private var regularitySummary: String {
        let lastSeven = recent.filter { $0.date >= Date().addingTimeInterval(-7 * 24 * 3600) }
        return "\(lastSeven.count)/7 dias"
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct PatternStatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Color.neuroYellow)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

struct WeeklyMoodCalendarCard: View {
    let checkIns: [DailyCheckIn]

    private var days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -6 + offset, to: today)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.badge.clock", title: "Semana em cores")
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let item = checkIn(for: day)
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(color(for: item?.mood))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if item == nil {
                                    Circle().stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3]))
                                }
                            }
                        Text(item.map { String(Int($0.mood)) } ?? "-")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityLabel(for: day, checkIn: item))
                }
            }
        }
        .panelStyle()
    }

    private func checkIn(for day: Date) -> DailyCheckIn? {
        checkIns.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private func color(for mood: Double?) -> Color {
        guard let mood else { return Color(.secondarySystemGroupedBackground) }
        if mood >= 4 { return .green }
        if mood >= 3 { return .neuroYellow }
        if mood >= 2 { return .orange }
        return .red
    }

    private func accessibilityLabel(for day: Date, checkIn: DailyCheckIn?) -> String {
        if let checkIn {
            return "\(day.formatted(date: .abbreviated, time: .omitted)): humor \(Int(checkIn.mood)), ansiedade \(Int(checkIn.anxiety))"
        }
        return "\(day.formatted(date: .abbreviated, time: .omitted)): sem registro"
    }
}

struct WeekdayPatternCard: View {
    let checkIns: [DailyCheckIn]

    private var weekdayAverages: [(weekday: Int, mood: Double, anxiety: Double, count: Int)] {
        let grouped = Dictionary(grouping: checkIns) { Calendar.current.component(.weekday, from: $0.date) }
        return (1...7).compactMap { weekday in
            guard let items = grouped[weekday], !items.isEmpty else { return nil }
            return (
                weekday,
                items.reduce(0) { $0 + $1.mood } / Double(items.count),
                items.reduce(0) { $0 + $1.anxiety } / Double(items.count),
                items.count
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "calendar.day.timeline.left", title: "Padrões da semana")
            if weekdayAverages.count < 2 {
                EmptyState(text: "Depois de alguns registros, o app mostra quais dias costumam pesar mais ou funcionar melhor.")
            } else {
                Chart(weekdayAverages, id: \.weekday) { item in
                    BarMark(
                        x: .value("Dia", weekdayName(item.weekday)),
                        y: .value("Humor médio", item.mood)
                    )
                    .foregroundStyle(Color.neuroYellow)
                    PointMark(
                        x: .value("Dia", weekdayName(item.weekday)),
                        y: .value("Ansiedade média", item.anxiety)
                    )
                    .foregroundStyle(Color.red)
                }
                .frame(height: 150)
                .chartYScale(domain: 0...5)
                .accessibilityLabel("Gráfico de padrões por dia da semana")

                if let hardest = weekdayAverages.max(by: { $0.anxiety < $1.anxiety }) {
                    Label("Dia com mais ansiedade nos seus registros: \(weekdayName(hardest.weekday)).", systemImage: "lightbulb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .panelStyle()
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[max(0, min(weekday - 1, symbols.count - 1))]
    }
}

struct EducationPathwaysCard: View {
    let selectedFocus: CareFocus

    private var modules: [EducationModule] {
        EducationModule.modules(for: selectedFocus)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "books.vertical.fill", title: "Trilhas de aprendizado")
            Text("Conteúdos curtos para entender padrões, sono, medicação, recaída e quando pedir ajuda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(modules) { module in
                VStack(alignment: .leading, spacing: 8) {
                    Label(module.title, systemImage: module.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.neuroNavy)
                    Text(module.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(module.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.neuroNavy)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.neuroYellow.opacity(0.35), in: Capsule())
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
            }
        }
        .panelStyle()
    }
}

private struct EducationModule: Identifiable {
    let id: String
    let icon: String
    let title: String
    let summary: String
    let tags: [String]

    static func modules(for focus: CareFocus) -> [EducationModule] {
        [focusModule(for: focus), sleep, medication, relapse, appointment]
    }

    private static func focusModule(for focus: CareFocus) -> EducationModule {
        switch focus {
        case .bipolar:
            return EducationModule(id: "bipolar", icon: "waveform.path", title: "Bipolaridade e sinais precoces", summary: "Sono reduzido, energia elevada, irritabilidade e impulsividade podem aparecer antes de piora. Acompanhar rotina ajuda a agir cedo.", tags: ["sono", "energia", "recaída"])
        case .depression:
            return EducationModule(id: "depression", icon: "cloud.rain.fill", title: "Depressão e ativação gradual", summary: "Humor baixo costuma reduzir ação. Metas pequenas e repetíveis ajudam a recuperar ritmo sem exigir grandes esforços.", tags: ["humor", "rotina"])
        case .anxiety:
            return EducationModule(id: "anxiety", icon: "wind", title: "Ansiedade e corpo", summary: "Sintomas físicos podem parecer ameaça. Respiração, grounding e exposição planejada ajudam a diferenciar risco real de ativação.", tags: ["corpo", "gatilhos"])
        case .borderline:
            return EducationModule(id: "borderline", icon: "heart.circle.fill", title: "Intensidade emocional", summary: "Mapear gatilhos interpessoais, impulsos e estratégias de tolerância ajuda a atravessar picos com menos dano.", tags: ["gatilhos", "apoio"])
        case .burnout:
            return EducationModule(id: "burnout", icon: "battery.25percent", title: "Burnout e recuperação", summary: "Energia, sono e carga mental precisam ser acompanhados juntos. Recuperação exige limites, pausa e reconstrução gradual.", tags: ["energia", "limites"])
        case .adhd:
            return EducationModule(id: "adhd", icon: "timer", title: "TDAH, rotina e medicação", summary: "Sono, horários e adesão influenciam foco e humor. Âncoras visuais e lembretes reduzem dependência de memória.", tags: ["rotina", "foco"])
        case .postpartum:
            return EducationModule(id: "postpartum", icon: "figure.and.child.holdinghands", title: "Pós-parto e rede de apoio", summary: "Sono fragmentado, ansiedade e humor precisam ser vistos com contexto. Acionar apoio cedo é parte do cuidado.", tags: ["sono", "apoio"])
        }
    }

    private static let sleep = EducationModule(id: "sleep", icon: "moon.zzz.fill", title: "Sono como sinal clínico", summary: "Mudanças de sono podem vir antes de alterações importantes de humor, ansiedade e energia.", tags: ["Health", "rotina"])
    private static let medication = EducationModule(id: "medication", icon: "pills.fill", title: "Medicação e adesão", summary: "Registrar dose, horário e efeitos colaterais ajuda a conversar com o profissional sem depender da memória.", tags: ["consulta", "segurança"])
    private static let relapse = EducationModule(id: "relapse", icon: "exclamationmark.triangle.fill", title: "Sinais de recaída", summary: "O objetivo não é prever tudo, mas perceber combinações que costumam anteceder piora no seu próprio padrão.", tags: ["score", "padrões"])
    private static let appointment = EducationModule(id: "appointment", icon: "stethoscope", title: "Como levar dados à consulta", summary: "Leve tendências, exemplos concretos e dúvidas. Relatórios ajudam, mas sua experiência continua sendo central.", tags: ["relatório", "consulta"])
}
