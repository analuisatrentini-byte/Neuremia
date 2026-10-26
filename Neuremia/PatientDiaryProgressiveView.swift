//
//  PatientDiaryProgressiveView.swift
//  Neuremia
//
//  Diário progressivo estilo wizard:
//  - Cada seção desbloqueia após preencher a anterior
//  - Design moderno com animações suaves
//  - Feedback visual de progresso
//  - Fluxo fluido e intuitivo
//

import SwiftUI

// MARK: - Diary Step Model (accessible to ContentView)

enum DiaryStep: Int, CaseIterable, Identifiable {
    case mood = 0
    case sleepMedication = 1
    case details = 2
    case journal = 3
    case review = 4

    var id: Int { rawValue }

    var shortTitle: String {
        switch self {
        case .mood: return "Humor"
        case .sleepMedication: return "Sono"
        case .details: return "Detalhes"
        case .journal: return "Diário"
        case .review: return "Revisar"
        }
    }

    var icon: String {
        switch self {
        case .mood: return "face.smiling"
        case .sleepMedication: return "moon.zzz"
        case .details: return "slider.horizontal.3"
        case .journal: return "square.and.pencil"
        case .review: return "checkmark.circle"
        }
    }

    var gradient: [Color] {
        switch self {
        case .mood: return [Color.neuroYellow, Color.neuroOrange]
        case .sleepMedication: return [Color.purple, Color.blue]
        case .details: return [Color.teal, Color.green]
        case .journal: return [Color.pink, Color.purple]
        case .review: return [Color.green, Color.teal]
        }
    }
}

// MARK: - Progressive Diary Extension

extension ContentView {
    var progressiveDiaryPage: some View {
        VStack(spacing: 16) {
            DailyRecommendationCard(
                recommendation: adjustedDailyRecommendation,
                log: todayRecommendationLog,
                responseProfile: currentRecommendationResponseProfile,
                canSave: canSaveClinicalData,
                markCompleted: markTodayRecommendationCompleted
            )

            DiaryProgressStepper(
                currentStep: $diaryCurrentStep,
                completedSteps: completedDiarySteps,
                steps: DiaryStep.allCases
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Sprint 26 (fix): substituído TabView.page por switch condicional.
            // Motivo: TabView.page dentro de ScrollView (patientTabHome) colapsava
            // a altura → botões (humor, "fazer check-in") não recebiam toque; e
            // o swipe horizontal colidia com o scroll vertical do pai. Agora o
            // step atual renderiza inline com transição slide, sem conflito.
            // ZStack + id força SwiftUI a tratar cada step como view distinta
            // para as transitions dispararem consistentemente. Sem o id, a
            // troca do body renderiza tudo no mesmo container e o transition
            // não é aplicado — em iOS 17+ isso ainda pode gerar reavaliação
            // em loop dependendo do state envolvido.
            ZStack {
                switch diaryCurrentStep {
                case .mood:
                    DiaryMoodStep(
                        mood: $mood,
                        anxiety: $anxiety,
                        energy: $energy,
                        onNext: advanceDiaryStep
                    )
                    .id("step-mood")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                case .sleepMedication:
                    DiarySleepMedicationStep(
                        sleepHours: $sleepHours,
                        medicationStatus: $medicationStatus,
                        safetyStatus: $safetyStatus,
                        onNext: advanceDiaryStep,
                        onBack: previousDiaryStep
                    )
                    .id("step-sleep")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                case .details:
                    DiaryDetailsStep(
                        energy: $energy,
                        irritability: $irritability,
                        appetite: $appetite,
                        libido: $libido,
                        onNext: advanceDiaryStep,
                        onBack: previousDiaryStep
                    )
                    .id("step-details")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                case .journal:
                    DiaryJournalStep(
                        journalEntry: $journalEntry,
                        sideEffects: $sideEffects,
                        automaticThoughts: $automaticThoughts,
                        alcoholTrigger: $alcoholTrigger,
                        poorSleepTrigger: $poorSleepTrigger,
                        stressTrigger: $stressTrigger,
                        conflictTrigger: $conflictTrigger,
                        routineChangeTrigger: $routineChangeTrigger,
                        menstrualTrigger: $menstrualTrigger,
                        customTriggerText: $customTriggerText,
                        customTriggers: $customTriggers,
                        checkIns: sortedCheckIns,
                        onNext: advanceDiaryStep,
                        onBack: previousDiaryStep
                    )
                    .id("step-journal")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                case .review:
                    DiaryReviewStep(
                        mood: mood,
                        anxiety: anxiety,
                        sleepHours: sleepHours,
                        automaticResults: automaticCheckupResults,
                        canSave: canSaveClinicalData,
                        onSave: {
                            Task {
                                await saveDailyCheckInAfterHealthSync()
                                HapticManager.shared.success()
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                                    diaryCurrentStep = .mood
                                }
                            }
                        },
                        onBack: previousDiaryStep
                    )
                    .id("step-review")
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: diaryCurrentStep)
        }
    }

    private var completedDiarySteps: Set<DiaryStep> {
        var completed = Set<DiaryStep>()
        if mood != 3.0 || anxiety != 2.0 { completed.insert(.mood) }
        if sleepHours != 7.0 || medicationStatus != .taken || safetyStatus != .safe {
            completed.insert(.sleepMedication)
        }
        if energy != 3.0 || irritability != 1.0 || appetite != 3.0 || libido != 0.0 {
            completed.insert(.details)
        }
        if !sideEffects.isEmpty || !automaticThoughts.isEmpty || !journalEntry.isEmpty || !activeTriggerLabels.isEmpty {
            completed.insert(.journal)
        }
        return completed
    }

    private func advanceDiaryStep() {
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let nextStep = DiaryStep(rawValue: diaryCurrentStep.rawValue + 1) {
                diaryCurrentStep = nextStep
            }
        }
    }

    private func previousDiaryStep() {
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if let prevStep = DiaryStep(rawValue: diaryCurrentStep.rawValue - 1) {
                diaryCurrentStep = prevStep
            }
        }
    }
}

// MARK: - Progress Stepper

struct DiaryProgressStepper: View {
    @Binding var currentStep: DiaryStep
    let completedSteps: Set<DiaryStep>
    let steps: [DiaryStep]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps) { step in
                StepIndicator(
                    step: step,
                    isActive: currentStep == step,
                    isCompleted: completedSteps.contains(step),
                    isAccessible: isAccessible(step),
                    onTap: {
                        if isAccessible(step) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentStep = step
                            }
                            HapticManager.shared.selection()
                        }
                    }
                )

                if step != steps.last {
                    StepConnector(isCompleted: completedSteps.contains(step))
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func isAccessible(_ step: DiaryStep) -> Bool {
        if step == .mood { return true }
        if let prevStep = DiaryStep(rawValue: step.rawValue - 1) {
            return completedSteps.contains(prevStep)
        }
        return true
    }
}

struct StepIndicator: View {
    let step: DiaryStep
    let isActive: Bool
    let isCompleted: Bool
    let isAccessible: Bool
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    backgroundView
                        .shadow(color: shadowColor.opacity(isActive ? 0.3 : 0), radius: 8, y: 2)

                    if isCompleted && !isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white)
                    } else {
                        Image(systemName: step.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(iconColor)
                    }

                    if isActive {
                        Circle()
                            .stroke(Color.neuroOrange.opacity(0.3), lineWidth: 3)
                            .frame(width: 52, height: 52)
                            .scaleEffect(pulseScale)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                    pulseScale = 1.2
                                }
                            }
                    }
                }
                .scaleEffect(isActive ? 1.1 : 1.0)
                .animation(.spring(response: 0.3), value: isActive)

                Text(step.shortTitle)
                    .font(.caption2.weight(isActive ? .bold : .medium))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAccessible)
        .opacity(isAccessible ? 1.0 : 0.5)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isActive {
            Circle()
                .fill(LinearGradient(colors: step.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
        } else if isCompleted {
            Circle()
                .fill(Color.green)
                .frame(width: 44, height: 44)
        } else {
            Circle()
                .fill(Color(.tertiarySystemGroupedBackground))
                .frame(width: 44, height: 44)
        }
    }

    private var iconColor: Color {
        (isActive || isCompleted) ? Color.white : Color.secondary
    }

    private var shadowColor: Color {
        step.gradient.first ?? Color.neuroOrange
    }

    private var titleColor: Color {
        if isActive { return Color.primary }
        else if isCompleted { return Color.green }
        else { return Color.secondary }
    }
}

struct StepConnector: View {
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color(.tertiarySystemGroupedBackground))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.4), value: isCompleted)
    }
}

// MARK: - Step 1: Mood

struct DiaryMoodStep: View {
    @Binding var mood: Double
    @Binding var anxiety: Double
    @Binding var energy: Double
    let onNext: () -> Void

    // Sprint 26: emojis substituídos por símbolos SF — linguagem mais
    // moderna/adulta, alinhada com apps clínicos (não infantiliza).
    let emotions: [(String, String, Color, Double)] = [
        ("Ótimo", "face.smiling.fill", Color.green, 5.0),
        ("Bem", "face.smiling", Color(red: 0.4, green: 0.8, blue: 0.4), 4.0),
        ("Regular", "face.dashed", Color.neuroYellow, 3.0),
        ("Difícil", "cloud.rain.fill", Color.orange, 2.0),
        ("Muito difícil", "cloud.bolt.rain.fill", Color.red, 1.0)
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [Color.neuroYellow, Color.neuroOrange], startPoint: .topLeading, endPoint: .bottomTrailing))

                Text("Como você está?")
                    .font(.title2.weight(.bold))

                Text("Toque para selecionar seu estado atual")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 20)

            // Emotion grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                ForEach(emotions, id: \.0) { emotion in
                    EmotionButton(
                        symbol: emotion.1,
                        label: emotion.0,
                        color: emotion.2,
                        isSelected: Int(mood) == Int(emotion.3)
                    ) {
                        mood = emotion.3
                        HapticManager.shared.selection()
                    }
                }
            }
            .padding(.horizontal, 16)

            // Anxiety quick indicator
            VStack(spacing: 8) {
                Text("Nível de ansiedade")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { level in
                        Button {
                            anxiety = Double(level)
                            HapticManager.shared.selection()
                        } label: {
                            Circle()
                                .fill(level <= Int(anxiety) ? anxietyColor(level) : Color(.tertiarySystemGroupedBackground))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if level <= Int(anxiety) {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            Button(action: onNext) {
                HStack {
                    Text("Continuar")
                        .font(.headline.weight(.semibold))
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [Color.neuroYellow, Color.neuroOrange], startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func anxietyColor(_ level: Int) -> Color {
        switch level {
        case 1: return .green
        case 2: return Color(red: 0.4, green: 0.8, blue: 0.4)
        case 3: return .neuroYellow
        case 4: return .orange
        default: return .red
        }
    }
}

struct EmotionButton: View {
    let symbol: String
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? color : color.opacity(0.18))
                        .frame(width: 64, height: 64)
                        .overlay(Circle().stroke(isSelected ? color : Color.clear, lineWidth: 3))
                        .shadow(color: isSelected ? color.opacity(0.4) : Color.clear, radius: 8, y: 2)

                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : color)
                        .symbolRenderingMode(.hierarchical)
                }

                Text(label)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Step 2: Sleep

struct DiarySleepMedicationStep: View {
    @Binding var sleepHours: Double
    @Binding var medicationStatus: MedicationStatus
    @Binding var safetyStatus: SafetyStatus
    let onNext: () -> Void
    let onBack: () -> Void

    let sleepValues: [Double] = [4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))

                Text("Sono e Medicação")
                    .font(.title2.weight(.bold))

                Text("Quanto tempo você dormiu?")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 20)

            // Sleep display
            VStack(spacing: 4) {
                Text("\(Int(sleepHours))h\(sleepHours.truncatingRemainder(dividingBy: 1) == 0 ? "" : "30")")
                    .font(.system(size: 64, weight: .bold))
                    .contentTransition(.numericText())

                Text(sleepQuality)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(sleepColor)
            }

            // Slider
            VStack(spacing: 8) {
                Slider(value: $sleepHours, in: 4...9, step: 0.5)
                    .tint(LinearGradient(colors: [.red, .neuroYellow, .green], startPoint: .leading, endPoint: .trailing))
                    .onChange(of: sleepHours) { _, _ in HapticManager.shared.selection() }

                HStack {
                    Text("4h").font(.caption).foregroundStyle(Color.secondary)
                    Spacer()
                    Text("9h+").font(.caption).foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 32)

            // Quick buttons
            HStack(spacing: 12) {
                ForEach(sleepValues, id: \.self) { value in
                    Button {
                        sleepHours = value
                        HapticManager.shared.selection()
                    } label: {
                        Text("\(Int(value))h")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Int(sleepHours) == Int(value) ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Int(sleepHours) == Int(value) ? sleepColor : Color(.secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }

            DailySafetyChoices(
                medicationStatus: $medicationStatus,
                safetyStatus: $safetyStatus
            )
            .padding(.horizontal, 16)

            Spacer()

            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Voltar")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button(action: onNext) {
                    HStack {
                        Text("Continuar")
                            .font(.headline.weight(.semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // Sprint 26: background removido — quando renderizado inline no
        // ScrollView do patientTabHome, sobrescrevia o gradient do app.
    }

    private var sleepColor: Color {
        switch sleepHours {
        case 4: return .red
        case 5: return .orange
        case 6: return .neuroYellow
        default: return .green
        }
    }

    private var sleepQuality: String {
        switch sleepHours {
        case ..<5: return "Pouco sono"
        case 5..<6: return "Sono moderado"
        case 6..<7: return "Quase suficiente"
        default: return "Bom sono"
        }
    }
}

// MARK: - Step 3: Details

struct DiaryDetailsStep: View {
    @Binding var energy: Double
    @Binding var irritability: Double
    @Binding var appetite: Double
    @Binding var libido: Double
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [Color.teal, Color.green], startPoint: .topLeading, endPoint: .bottomTrailing))

                Text("Mais detalhes")
                    .font(.title2.weight(.bold))

                Text("Opcional - personalize seu registro")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 16) {
                    DetailSliderCard(title: "Energia", icon: "bolt.fill", value: $energy, color: .neuroYellow,
                        labels: ["Exausto", "Baixa", "Normal", "Boa", "Alta"])

                    DetailSliderCard(title: "Irritabilidade", icon: "exclamationmark.bubble.fill", value: $irritability, color: .orange,
                        labels: ["Calmo", "Leve", "Média", "Alta", "Pico"])

                    DetailSliderCard(title: "Apetite", icon: "fork.knife", value: $appetite, color: .green,
                        labels: ["Muito baixo", "Baixo", "Normal", "Alto", "Voraz"])

                    OptionalDetailSliderCard(
                        title: "Libido",
                        icon: "heart.fill",
                        value: $libido,
                        color: .pink,
                        labels: ["N/A", "Muito baixa", "Baixa", "Normal", "Alta", "Muito alta"]
                    )
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Voltar")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button(action: onNext) {
                    HStack {
                        Text("Continuar")
                            .font(.headline.weight(.semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Color.teal, Color.green], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // Sprint 26: background removido — quando renderizado inline no
        // ScrollView do patientTabHome, sobrescrevia o gradient do app.
    }
}

struct DetailSliderCard: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let color: Color
    let labels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.headline)
                Spacer()
            }

            Slider(value: $value, in: 1...5, step: 1)
                .tint(color)
                .onChange(of: value) { _, _ in HapticManager.shared.selection() }

            HStack {
                ForEach(1...5, id: \.self) { level in
                    Text(labels[level - 1])
                        .font(.caption2)
                        .foregroundStyle(Int(value) == level ? color : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct OptionalDetailSliderCard: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let color: Color
    let labels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.headline)
                Spacer()
                Text(labels[Int(value)])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }

            Slider(value: $value, in: 0...5, step: 1)
                .tint(color)
                .onChange(of: value) { _, _ in HapticManager.shared.selection() }

            HStack {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index])
                        .font(.caption2)
                        .foregroundStyle(Int(value) == index ? color : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Step 4: Journal

struct DiaryJournalStep: View {
    @Binding var journalEntry: String
    @Binding var sideEffects: String
    @Binding var automaticThoughts: String
    @Binding var alcoholTrigger: Bool
    @Binding var poorSleepTrigger: Bool
    @Binding var stressTrigger: Bool
    @Binding var conflictTrigger: Bool
    @Binding var routineChangeTrigger: Bool
    @Binding var menstrualTrigger: Bool
    @Binding var customTriggerText: String
    @Binding var customTriggers: [String]
    let checkIns: [DailyCheckIn]
    let onNext: () -> Void
    let onBack: () -> Void

    @State private var showJournal = true
    @State private var showThoughts = false
    @State private var showSideEffects = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [Color.pink, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))

                Text("Reflexão")
                    .font(.title2.weight(.bold))

                Text("Opcional - escreva livremente")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 16) {
                    JournalCard(
                        title: "Meu diário",
                        icon: "book.fill",
                        placeholder: "Como foi seu dia? O que aconteceu?",
                        text: $journalEntry,
                        isExpanded: $showJournal
                    )

                    JournalCard(
                        title: "Pensamentos recorrentes",
                        icon: "bubble.left.and.text.bubble.right.fill",
                        placeholder: "Algum pensamento apareceu várias vezes hoje?",
                        text: $automaticThoughts,
                        isExpanded: $showThoughts
                    )

                    JournalCard(
                        title: "Efeitos colaterais",
                        icon: "pills.fill",
                        placeholder: "Algum efeito colateral hoje?",
                        text: $sideEffects,
                        isExpanded: $showSideEffects
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
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Voltar")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button(action: onNext) {
                    HStack {
                        Text("Revisar")
                            .font(.headline.weight(.semibold))
                        Image(systemName: "arrow.right")
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient(colors: [Color.pink, Color.purple], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // Sprint 26: background removido — quando renderizado inline no
        // ScrollView do patientTabHome, sobrescrevia o gradient do app.
    }
}

struct JournalCard: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon).foregroundStyle(Color.pink)
                    Text(title).font(.headline).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                TextEditor(text: $text)
                    .frame(minHeight: 100)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scrollContentBackground(.hidden)
            } else if !text.isEmpty {
                Text(text).font(.caption).foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(placeholder).font(.caption).foregroundStyle(Color.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { withAnimation { isExpanded = true } }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Step 5: Review

struct DiaryReviewStep: View {
    let mood: Double
    let anxiety: Double
    let sleepHours: Double
    let automaticResults: [AutomaticScaleResult]
    let canSave: Bool
    let onSave: () -> Void
    let onBack: () -> Void

    @State private var iconBounce = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.green.opacity(0.2), Color.teal.opacity(0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 88, height: 88)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .symbolEffect(.bounce, value: iconBounce)
                }

                Text("Tudo pronto!")
                    .font(.title2.weight(.bold))

                Text("Revise seu registro antes de salvar")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.top, 20)
            .onAppear { iconBounce.toggle() }

            ScrollView {
                VStack(spacing: 16) {
                    ReviewCard(items: [
                        ("face.smiling", "Humor", moodDescription),
                        ("waveform.path.ecg", "Ansiedade", anxietyDescription),
                        ("moon.zzz", "Sono", "\(Int(sleepHours)) horas")
                    ])

                    AutomaticScoreReviewCard(results: automaticResults)

                    if !canSave {
                        // Feedback claro quando o consentimento LGPD ainda
                        // não foi aceito — evita o "botão cinza silencioso".
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.orange)
                            Text("Ative o consentimento no rodapé para salvar.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.12))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Voltar")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button(action: onSave) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Salvar registro")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: canSave
                                ? [Color.green, Color.teal]
                                : [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: canSave ? Color.green.opacity(0.3) : Color.clear, radius: 8, y: 4)
                }
                .disabled(!canSave)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        // Sprint 26: background removido — quando renderizado inline no
        // ScrollView do patientTabHome, sobrescrevia o gradient do app.
    }

    private var moodDescription: String {
        switch mood {
        case 5: return "Ótimo"
        case 4: return "Bem"
        case 3: return "Regular"
        case 2: return "Difícil"
        default: return "Muito difícil"
        }
    }

    private var anxietyDescription: String {
        switch anxiety {
        case 1: return "Tranquilo"
        case 2: return "Leve"
        case 3: return "Médio"
        case 4: return "Alto"
        default: return "Pico"
        }
    }
}

struct AutomaticScoreReviewCard: View {
    let results: [AutomaticScaleResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scores automáticos", systemImage: "sparkline")
                    .font(.headline)
                Spacer()
                Text("\(results.count)/\(ScaleKind.allCases.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(results.count == ScaleKind.allCases.count ? .green : .orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.scale.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("\(result.score)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(color(for: result))
                        Text(result.interpretation)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color(for: result))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(color(for: result).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Text("Calculado dinamicamente com as respostas deste diário.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

struct ReviewCard: View {
    let items: [(String, String, String)]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Resumo do dia")
                    .font(.headline)
                Spacer()
            }

            ForEach(items, id: \.1) { item in
                HStack {
                    Image(systemName: item.0)
                        .foregroundStyle(Color.neuroOrange)
                        .frame(width: 24)
                    Text(item.1)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Text(item.2)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.neuroYellow.opacity(0.1), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.neuroOrange.opacity(0.3), lineWidth: 1))
    }
}
