//
//  ContentView.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var patients: [PatientProfile]
    @Query private var checkIns: [DailyCheckIn]
    @Query private var assessments: [ScaleAssessment]
    @Query private var alerts: [ClinicalAlert]
    @Query private var reports: [ClinicalReport]

    @State private var selectedTab = DashboardTab.patient
    @State private var mood = 3.0
    @State private var anxiety = 2.0
    @State private var energy = 3.0
    @State private var irritability = 1.0
    @State private var sleepHours = 7.0
    @State private var appetite = 3.0
    @State private var libido = 3.0
    @State private var medicationTaken = true
    @State private var suicidalIdeation = false
    @State private var sideEffects = ""
    @State private var automaticThoughts = ""
    @State private var journalEntry = ""
    @State private var selectedScale = ScaleKind.phq9
    @State private var scaleAnswers: [ScaleKind: [Int]] = [:]
    @State private var reportPreview = ""

    private var sortedCheckIns: [DailyCheckIn] {
        checkIns.sorted { $0.date > $1.date }
    }

    private var sortedAssessments: [ScaleAssessment] {
        assessments.sorted { $0.date > $1.date }
    }

    private var activeAlerts: [ClinicalAlert] {
        alerts.filter { !$0.acknowledged }.sorted { $0.date > $1.date }
    }

    private var latestReports: [ClinicalReport] {
        reports.sorted { $0.date > $1.date }
    }

    private var summary: LongitudinalSummary {
        ClinicalAnalysis.summary(checkIns: sortedCheckIns, assessments: sortedAssessments)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    privacyConsent
                    tabSelector

                    switch selectedTab {
                    case .patient:
                        patientDashboard
                    case .scales:
                        scalesDashboard
                    case .doctor:
                        doctorDashboard
                    case .security:
                        securityDashboard
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NeuroFlow")
            .onAppear(perform: prepareInitialData)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monitoramento integrado em saúde mental", systemImage: "brain.head.profile")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.teal)

            Text("Dados clínicos longitudinais, escalas validadas e alertas para apoiar o cuidado.")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                StatBadge(title: "Registros", value: "\(checkIns.count)", icon: "calendar.badge.clock")
                StatBadge(title: "Escalas", value: "\(assessments.count)", icon: "checklist.checked")
                StatBadge(title: "Risco", value: summary.riskLevel.rawValue, icon: "waveform.path.ecg")
            }
        }
        .panelStyle()
    }

    private var privacyConsent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.teal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Consentimento e privacidade")
                        .font(.headline)

                    Text("Dados sensíveis devem ser tratados com consentimento explícito, minimização, controle de acesso e regras compatíveis com LGPD/HIPAA antes de uso em produção.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle("Aceito registrar dados clínicos neste dispositivo", isOn: consentBinding)
                .toggleStyle(.switch)
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier("privacyConsentToggle")
        }
        .panelStyle()
    }

    private var tabSelector: some View {
        Picker("Área", selection: $selectedTab) {
            ForEach(DashboardTab.allCases) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var patientDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "person.text.rectangle", title: "Registro diário")

            VStack(spacing: 16) {
                MetricSlider(title: "Humor", icon: "face.smiling", value: $mood, range: 0...5, lowLabel: "baixo", highLabel: "estável")
                MetricSlider(title: "Ansiedade", icon: "waveform.path.ecg", value: $anxiety, range: 0...5, lowLabel: "leve", highLabel: "intensa")
                MetricSlider(title: "Energia", icon: "bolt", value: $energy, range: 0...5, lowLabel: "baixa", highLabel: "alta")
                MetricSlider(title: "Irritabilidade", icon: "exclamationmark.bubble", value: $irritability, range: 0...5, lowLabel: "baixa", highLabel: "alta")
                MetricSlider(title: "Sono", icon: "moon.zzz", value: $sleepHours, range: 0...12, lowLabel: "0h", highLabel: "12h", suffix: "h")
                MetricSlider(title: "Apetite", icon: "fork.knife", value: $appetite, range: 0...5, lowLabel: "baixo", highLabel: "alto")
                MetricSlider(title: "Libido", icon: "heart", value: $libido, range: 0...5, lowLabel: "baixa", highLabel: "alta")

                Toggle("Medicação tomada hoje", isOn: $medicationTaken)
                    .toggleStyle(.switch)
                    .font(.headline)

                Toggle("Triagem positiva para ideação suicida", isOn: $suicidalIdeation)
                    .toggleStyle(.switch)
                    .font(.headline)
                    .foregroundStyle(suicidalIdeation ? .red : .primary)

                LabeledTextEditor(title: "Efeitos colaterais", systemImage: "pills", placeholder: "Ex.: sonolência, náusea, agitação", text: $sideEffects)
                LabeledTextEditor(title: "Pensamentos automáticos", systemImage: "bubble.left.and.text.bubble.right", placeholder: "Ex.: pensamentos recorrentes ou crenças disfuncionais", text: $automaticThoughts)
                LabeledTextEditor(title: "Diário do paciente", systemImage: "square.and.pencil", placeholder: "Registre contexto do dia, sintomas, sono, eventos e observações.", text: $journalEntry)

                Button(action: saveDailyCheckIn) {
                    Label("Salvar registro diário", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSaveClinicalData)
                .accessibilityIdentifier("saveCheckInButton")
            }
            .panelStyle()

            PatientFeedbackCard(summary: summary, canSave: canSaveClinicalData)

            historySection
        }
    }

    private var scalesDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "checklist.checked", title: "Escalas validadas")

            Picker("Escala", selection: $selectedScale) {
                ForEach(ScaleKind.allCases) { scale in
                    Text(scale.rawValue).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedScale) { _, _ in
                ensureAnswers(for: selectedScale)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(selectedScale.focus)
                    .font(.headline)

                Text("Frequência sugerida: \(summary.cadence), ajustada pelo risco longitudinal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(selectedScale.questions.indices, id: \.self) { index in
                    ScaleQuestionRow(
                        number: index + 1,
                        question: selectedScale.questions[index],
                        range: selectedScale.answerRange,
                        answer: answerBinding(for: selectedScale, index: index)
                    )
                }

                Button(action: saveScaleAssessment) {
                    Label("Salvar \(selectedScale.rawValue)", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSaveClinicalData)
            }
            .panelStyle()

            recentScalesSection
        }
    }

    private var doctorDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "stethoscope", title: "Dashboard médico")

            RiskSummaryCard(summary: summary)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(summary.signals, id: \.self) { signal in
                    ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: signal, description: "Sinal calculado a partir dos registros diários, escalas e análise textual.")
                }
            }
            .panelStyle()

            alertsSection
            reportSection
        }
    }

    private var securityDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(icon: "lock.shield", title: "Segurança e governança")

            VStack(alignment: .leading, spacing: 14) {
                ComplianceRow(icon: "person.badge.key", title: "Autenticação", description: "Próxima etapa: login com controle de perfil para paciente e médico.")
                ComplianceRow(icon: "checkmark.seal", title: "Consentimento", description: "Consentimento explícito já modelado localmente para liberar salvamento de dados.")
                ComplianceRow(icon: "externaldrive.badge.lock", title: "Proteção de dados", description: "Persistência local via SwiftData; produção deve adicionar criptografia, trilha de auditoria e política de retenção.")
                ComplianceRow(icon: "doc.text", title: "LGPD/HIPAA", description: "Mapear base legal, direitos do titular, contratos com operadores e regras de acesso antes de implantação clínica.")
            }
            .panelStyle()
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "clock.arrow.circlepath", title: "Histórico recente")

            if sortedCheckIns.isEmpty {
                EmptyState(text: "Nenhum registro diário salvo ainda.")
            } else {
                ForEach(sortedCheckIns.prefix(5)) { checkIn in
                    CheckInRow(checkIn: checkIn)
                }
            }
        }
    }

    private var recentScalesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "list.clipboard", title: "Resultados recentes")

            if sortedAssessments.isEmpty {
                EmptyState(text: "Nenhuma escala aplicada ainda.")
            } else {
                ForEach(sortedAssessments.prefix(6)) { assessment in
                    AssessmentRow(assessment: assessment)
                }
            }
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bell.badge", title: "Alertas acionáveis")

            if activeAlerts.isEmpty {
                EmptyState(text: "Nenhum alerta pendente.")
            } else {
                ForEach(activeAlerts) { alert in
                    AlertRow(alert: alert) {
                        alert.acknowledged = true
                    }
                }
            }
        }
    }

    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "doc.text.magnifyingglass", title: "Relatórios")

            Button(action: generateReport) {
                Label("Gerar relatório clínico", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sortedCheckIns.isEmpty && sortedAssessments.isEmpty)

            if !reportPreview.isEmpty {
                Text(reportPreview)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ForEach(latestReports.prefix(3)) { report in
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Risco: \(report.riskLevel)")
                        .font(.headline)

                    Text(report.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                .panelStyle()
            }
        }
    }

    private var canSaveClinicalData: Bool {
        patients.first?.consentAccepted == true
    }

    private var consentBinding: Binding<Bool> {
        Binding(
            get: { patients.first?.consentAccepted ?? false },
            set: { newValue in
                let patient = ensurePatient()
                patient.consentAccepted = newValue
            }
        )
    }

    private func prepareInitialData() {
        _ = ensurePatient()
        ensureAnswers(for: selectedScale)
    }

    @discardableResult
    private func ensurePatient() -> PatientProfile {
        if let patient = patients.first {
            return patient
        }

        let patient = PatientProfile()
        modelContext.insert(patient)
        return patient
    }

    private func ensureAnswers(for scale: ScaleKind) {
        if scaleAnswers[scale]?.count != scale.questions.count {
            scaleAnswers[scale] = Array(repeating: 0, count: scale.questions.count)
        }
    }

    private func answerBinding(for scale: ScaleKind, index: Int) -> Binding<Int> {
        Binding(
            get: {
                scaleAnswers[scale, default: Array(repeating: 0, count: scale.questions.count)][index]
            },
            set: { newValue in
                ensureAnswers(for: scale)
                scaleAnswers[scale]?[index] = newValue
            }
        )
    }

    private func saveDailyCheckIn() {
        let checkIn = DailyCheckIn(
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            sleepHours: sleepHours,
            appetite: appetite,
            libido: libido,
            medicationTaken: medicationTaken,
            sideEffects: sideEffects,
            automaticThoughts: automaticThoughts,
            suicidalIdeation: suicidalIdeation,
            journalEntry: journalEntry
        )
        modelContext.insert(checkIn)

        let textRisk = suicidalIdeation ? ClinicalRiskLevel.high : ClinicalAnalysis.textRisk(for: "\(journalEntry) \(automaticThoughts)")
        if textRisk != .low || mood <= 2 || anxiety >= 3.5 || !medicationTaken {
            modelContext.insert(ClinicalAlert(level: textRisk == .low ? .moderate : textRisk, title: textRisk.alertTitle, message: "Revisar registro diário, adesão medicamentosa e sintomas recentes."))
        }

        sideEffects = ""
        automaticThoughts = ""
        journalEntry = ""
        suicidalIdeation = false
    }

    private func saveScaleAssessment() {
        ensureAnswers(for: selectedScale)
        let answers = scaleAnswers[selectedScale] ?? []
        let score = ClinicalAnalysis.score(for: selectedScale, answers: answers)
        let interpretation = ClinicalAnalysis.interpretation(for: selectedScale, score: score)
        modelContext.insert(ScaleAssessment(scaleName: selectedScale.rawValue, answers: answers, score: score, interpretation: interpretation))

        if scoreRequiresAlert(scale: selectedScale, score: score) {
            modelContext.insert(ClinicalAlert(level: .moderate, title: "Escala alterada", message: "\(selectedScale.rawValue): \(score) pontos, interpretação \(interpretation)."))
        }
    }

    private func scoreRequiresAlert(scale: ScaleKind, score: Int) -> Bool {
        switch scale {
        case .phq9:
            score >= 10
        case .gad7:
            score >= 10
        case .ymrs:
            score >= 14
        }
    }

    private func generateReport() {
        let text = ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments)
        reportPreview = text
        modelContext.insert(ClinicalReport(summary: text, riskLevel: summary.riskLevel))
    }
}

private enum DashboardTab: String, CaseIterable, Identifiable {
    case patient
    case scales
    case doctor
    case security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .patient:
            "Paciente"
        case .scales:
            "Escalas"
        case .doctor:
            "Médico"
        case .security:
            "Segurança"
        }
    }

    var icon: String {
        switch self {
        case .patient:
            "person"
        case .scales:
            "list.clipboard"
        case .doctor:
            "cross.case"
        case .security:
            "lock.shield"
        }
    }
}

private struct SectionTitle: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
    }
}

private struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.teal)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricSlider: View {
    let title: String
    let icon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let lowLabel: String
    let highLabel: String
    var suffix = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                Text("\(value, format: .number.precision(.fractionLength(1)))\(suffix)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.teal)
            }

            Slider(value: $value, in: range, step: 0.5)

            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct LabeledTextEditor: View {
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

private struct PatientFeedbackCard: View {
    let summary: LongitudinalSummary
    let canSave: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Risco atual: \(summary.riskLevel.rawValue)", systemImage: "sparkline")
                .font(.headline)
                .foregroundStyle(color)

            Text(canSave ? patientText : "Aceite o consentimento para liberar o salvamento de dados clínicos.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var patientText: String {
        switch summary.riskLevel {
        case .low:
            "Padrão estável. Continue os registros diários e as escalas no prazo sugerido."
        case .moderate:
            "Padrão de piora possível. O sistema recomenda revisão do sono, adesão e sintomas recentes."
        case .high:
            "Alerta prioritário. O médico assistente deve revisar os dados com urgência."
        }
    }
}

private struct ScaleQuestionRow: View {
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

private struct RiskSummaryCard: View {
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
                StatBadge(title: "Sono médio", value: "\(summary.averageSleep, format: .number.precision(.fractionLength(1)))h", icon: "moon.zzz")
                StatBadge(title: "Adesão", value: "\(summary.medicationAdherence * 100, format: .number.precision(.fractionLength(0)))%", icon: "pills")
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

private struct ClinicalSignal: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.teal)
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

private struct CheckInRow: View {
    let checkIn: DailyCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(checkIn.date, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label("Humor \(checkIn.mood, format: .number.precision(.fractionLength(1)))", systemImage: "face.smiling")
                Label("Ansiedade \(checkIn.anxiety, format: .number.precision(.fractionLength(1)))", systemImage: "waveform.path.ecg")
                Label("Sono \(checkIn.sleepHours, format: .number.precision(.fractionLength(1)))h", systemImage: "moon.zzz")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct AssessmentRow: View {
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

private struct AlertRow: View {
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

private struct ComplianceRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        ClinicalSignal(icon: icon, title: title, description: description)
    }
}

private struct EmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelStyle()
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PatientProfile.self, DailyCheckIn.self, ScaleAssessment.self, ClinicalAlert.self, ClinicalReport.self], inMemory: true)
}
