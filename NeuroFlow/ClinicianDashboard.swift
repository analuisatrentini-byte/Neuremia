//
//  ClinicianDashboard.swift
//  NeuroFlow
//

import SwiftUI
import Charts
import SwiftData

extension ContentView {
    // MARK: - Root containers (Sprint 19 / U1' — TabView raiz para paciente)

    // M5 (UX-P0): clínico agora tem TabView própria — antes era um único
    // scroll vertical com todos os contextos misturados (lista de pacientes,
    // análise clínica, relatórios). Cada aba tem NavigationStack própria;
    // o detalhe do paciente navega por push, não expande inline.
    @ViewBuilder
    var clinicianRoot: some View {
        TabView(selection: $clinicianTab) {
            clinicianPatientsTab
                .tabItem { Label(ClinicianTab.patients.rawValue, systemImage: ClinicianTab.patients.icon) }
                .tag(ClinicianTab.patients)
            clinicianAnalysisTab
                .tabItem { Label(ClinicianTab.analysis.rawValue, systemImage: ClinicianTab.analysis.icon) }
                .tag(ClinicianTab.analysis)
            clinicianReportsTab
                .tabItem { Label(ClinicianTab.reports.rawValue, systemImage: ClinicianTab.reports.icon) }
                .tag(ClinicianTab.reports)
        }
        .tint(.neuroOrange)
    }

    // Aba 1: lista de pacientes + detalhe via push
    @ViewBuilder
    var clinicianPatientsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                        .padding(20)
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            clinicianPatientsSection
                            clinicianSentInvitesSection
                        }
                        .padding(20)
                    }
                }
            }
            .refreshable {
                await loadClinicianPatients()
                await loadClinicianSentInvites()
            }
            .background(appBackground)
            .navigationTitle("Pacientes")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar {
                toolbarContent
                if let ts = clinicianPatientsLastLoaded {
                    ToolbarItem(placement: .bottomBar) {
                        Text("Atualizado \(ts.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Push navigation para o detalhe do paciente (M5)
            .navigationDestination(for: BackendUser.self) { patient in
                clinicianPatientDetailPage(for: patient)
            }
        }
    }

    // Aba 2: análise clínica agregada
    @ViewBuilder
    var clinicianAnalysisTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                    } else {
                        RiskSummaryCard(summary: summary)
                        TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                        ClinicianPopulationRiskCard(signature: neuroFlowRiskSignature, alerts: activeAlerts, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                        ClinicianPreConsultInsightCard(
                            summary: summary,
                            checkIns: sortedCheckIns,
                            assessments: sortedAssessments,
                            medicationPlans: medicationPlans,
                            signature: neuroFlowRiskSignature
                        )
                        longitudinalTrendsSection
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(summary.signals, id: \.self) { signal in
                                ClinicalSignal(icon: "chart.line.uptrend.xyaxis", title: signal, description: "Sinal calculado a partir dos registros diários, escalas e análise textual.")
                            }
                        }
                        .panelStyle()
                        alertsSection
                    }
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Análise")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    // Aba 3: relatórios
    @ViewBuilder
    var clinicianReportsTab: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !canViewClinicianData {
                        AccessGateCard(
                            activeRole: activeRole,
                            hasSharingConsent: patients.first?.shareWithClinician == true
                        )
                    } else {
                        reportSection
                    }
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Relatórios")
            .navigationBarTitleDisplayMode(.large)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    // Tela de detalhe do paciente — empurrada via NavigationLink (M5).
    // Carrega dados remotos ao entrar e apresenta as sub-tabs com labels.
    @ViewBuilder
    func clinicianPatientDetailPage(for patient: BackendUser) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Sub-tabs com ícone + label (M5 + P1-10)
                Picker("Seção", selection: $remotePatientSubTab) {
                    ForEach(RemotePatientSubTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if !remotePatientStatusMessage.isEmpty && remotePatientStatusMessage != "Dados carregados." {
                    Text(remotePatientStatusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Group {
                    if isLoadingRemotePatientData {
                        remotePatientSkeleton
                    } else {
                        switch remotePatientSubTab {
                        case .overview:
                            RemotePatientSnapshotCard(
                                patient: patient,
                                checkIns: remoteCheckIns,
                                assessments: remoteAssessments,
                                alerts: remoteAlerts,
                                reports: remoteReports
                            )
                        case .checkIns:
                            remotePatientCheckInsList
                        case .assessments:
                            remotePatientAssessmentsList
                        case .alerts:
                            remotePatientAlertsList
                        case .reports:
                            remotePatientReportsList
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
        }
        .background(appBackground)
        .navigationTitle(patient.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .privacySensitive(true)
        .task(id: patient.id) {
            await loadRemotePatientData(patient)
        }
    }

    @ViewBuilder
    var patientRoot: some View {
        // UX: tab "Sinais" removida da navegação primária — PPG e análise de
        // voz são funcionalidades opcionais de uso episódico. Foram movidas
        // para Ferramentas > Sinais do corpo para não competir visualmente
        // com o check-in diário. 3 abas comunica propósito mais claramente.
        TabView(selection: $selectedPatientPage) {
            patientTabHome
                .tabItem { Label(PatientPage.diary.rawValue, systemImage: PatientPage.diary.icon) }
                // Sprint 23: badge sinaliza convites pendentes + alertas não
                // reconhecidos sem o paciente precisar voltar à aba Hoje.
                .badge(homeTabBadgeCount)
                .tag(PatientPage.diary)

            patientTabEvolution
                .tabItem { Label(PatientPage.evolution.rawValue, systemImage: PatientPage.evolution.icon) }
                .tag(PatientPage.evolution)

            patientTabTools
                .tabItem { Label(PatientPage.tools.rawValue, systemImage: PatientPage.tools.icon) }
                .tag(PatientPage.tools)
        }
        .tint(.neuroOrange)
    }

    @ViewBuilder
    var patientTabHome: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientDashboard
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Hoje")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                // Save flutuante (Sprint 19) com consent inline (Sprint 20).
                // Se o paciente ainda não aceitou compartilhar, em vez de
                // mostrar um save cinza sem explicação, mostramos um toggle
                // claro: "Aceito compartilhar para salvar meus registros".
                Group {
                    if canSaveClinicalData {
                        Button(action: saveDailyCheckIn) {
                            Label("Salvar registro de hoje", systemImage: "tray.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityHint("Salva o registro de hoje no histórico local e sincroniza com o backend.")
                    } else if let patient = patients.first {
                        // M4 (UX-P0): antes o botão ficava desabilitado sem
                        // nenhuma explicação visível. Agora exibimos a razão
                        // do bloqueio e o toggle de consentimento lado a lado,
                        // eliminando o estado silencioso de "botão cinza".
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("Ative o consentimento para salvar seus registros.")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Toggle(isOn: Binding(
                                get: { patient.consentAccepted },
                                set: { newValue in
                                    patient.consentAccepted = newValue
                                    try? modelContext.save()
                                }
                            )) {
                                Text("Aceito acompanhar meu humor com segurança.")
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.switch)
                            .tint(.neuroOrange)
                            // Sprint A: identifier herdado da view `privacyConsent` órfã
                            // (removida nesta sprint) para o UI test seguir achando este switch.
                            .accessibilityIdentifier("privacyConsentToggle")
                            .accessibilityHint("Ao aceitar, você libera o salvamento do seu primeiro registro diário.")
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: canSaveClinicalData)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .padding(.bottom, 4)
                .background(.regularMaterial)
            }
        }
    }

    @ViewBuilder
    var patientTabBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientBodySignalsPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Corpo")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    var patientTabEvolution: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientEvolutionPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Evolução")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    @ViewBuilder
    var patientTabTools: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientToolsPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Ferramentas")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

}
