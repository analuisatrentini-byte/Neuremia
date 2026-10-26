//
//  ClinicianDashboard.swift
//  Neuremia
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
        .tint(.neuroYellow)
        .sensoryFeedback(.selection, trigger: clinicianTab)
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
                            ClinicalOperationsQueueCard(tasks: remoteClinicalTasks)
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
                        TemporalRiskPredictionCard(prediction: summary.temporalPrediction)
                        BackendModelValidationCard(report: remoteModelValidationReport)
                        EpisodePipelineCard(forecasts: summary.episodeForecasts)
                        TextRiskCard(title: "Classificação textual longitudinal", assessment: summary.textAssessment)
                        ClinicalDailyDigestCard(digest: summary.clinicalDigest)
                        ClinicianPopulationRiskCard(signature: neuremiaRiskSignature, alerts: activeAlerts.filter { $0.kind != ClinicalAlertKind.selfSignal.rawValue }, checkIns: sortedCheckIns, remotePatients: clinicianPatients)
                        ClinicianPreConsultInsightCard(
                            summary: summary,
                            checkIns: sortedCheckIns,
                            assessments: sortedAssessments,
                            medicationPlans: medicationPlans,
                            signature: neuremiaRiskSignature
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
                                reports: remoteReports,
                                tasks: remotePatientClinicalTasks
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
        // Redesign gamificado (Sprint 26): 3 abas principais
        // - Hoje: hero de acolhimento + missões + check-in rápido
        // - Progresso: XP, streak calendar, badges, meta semanal
        // - Explorar: tendências, padrões, dados
        // Sensory feedback + spring transition tornam a troca perceptível
        // sem exagerar.
        TabView(selection: $selectedPatientPage) {
            patientTabHome
                .tabItem { Label(PatientPage.diary.rawValue, systemImage: PatientPage.diary.icon) }
                .badge(homeTabBadgeCount)
                .tag(PatientPage.diary)

            patientTabEvolve
                .tabItem { Label(PatientPage.evolve.rawValue, systemImage: PatientPage.evolve.icon) }
                .tag(PatientPage.evolve)

            patientTabExplore
                .tabItem { Label(PatientPage.explore.rawValue, systemImage: PatientPage.explore.icon) }
                .tag(PatientPage.explore)
        }
        .tint(.neuroYellow)
        .sensoryFeedback(.selection, trigger: selectedPatientPage)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedPatientPage)
        .onChange(of: selectedPatientPage) { _, newValue in
            guard newValue == .diary else { return }
            Task { await syncContinuousHealthKitIfNeeded(force: false) }
        }
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
            .task {
                await syncContinuousHealthKitIfNeeded(force: false)
            }
            .safeAreaInset(edge: .bottom) {
                // Save flutuante (Sprint 19) com consent inline (Sprint 20).
                // Sprint 26: com o diário progressivo, cada step tem seu
                // próprio CTA (Continuar / Salvar no review) — esconder o
                // save flutuante quando o consent já está ok evita botão
                // duplicado. O consent gate permanece pois é bloqueador.
                Group {
                    if canSaveClinicalData && useProgressiveDiary {
                        EmptyView()
                    } else if canSaveClinicalData {
                        Button {
                            Task { await saveDailyCheckInAfterHealthSync() }
                        } label: {
                            Label("Salvar registro de hoje", systemImage: hasCheckedInToday ? "checkmark.seal.fill" : "tray.and.arrow.down.fill")
                                .frame(maxWidth: .infinity)
                                // Ícone faz bounce sempre que o save conclui —
                                // reforço visual sutil de "algo aconteceu",
                                // sem depender só da celebration overlay.
                                .symbolEffect(.bounce, value: saveStatusMessage)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(hasCheckedInToday ? .green : .accentColor)
                        .accessibilityHint("Atualiza o Apple Health, quando ativo, e salva o registro de hoje no histórico local.")
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
                                    do {
                                        try modelContext.save()
                                    } catch {
                                        saveStatusMessage = "Não foi possível salvar o consentimento: \(error.localizedDescription)"
                                    }
                                }
                            )) {
                                Text("Aceito acompanhar meu humor com segurança.")
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .toggleStyle(.switch)
                            .tint(.neuroYellow)
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

    /// Nova aba "Evoluir" com gamificação inspirada em gamificação
    @ViewBuilder
    var patientTabEvolve: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    evolvePageContent
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Evoluir")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    /// Nova aba "Explorar" - equivalente à antiga "Evolução"
    @ViewBuilder
    var patientTabExplore: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    patientEvolutionPage
                }
                .padding(20)
            }
            .background(appBackground)
            .navigationTitle("Explorar")
            .navigationBarTitleDisplayMode(.inline)
            .privacySensitive(true)
            .toolbar { toolbarContent }
        }
    }

    /// Conteúdo da aba "Progresso" — hero de perfil + streak semanal +
    /// missões (versão detalhada) + meta semanal + badges. A `GamifiedTopStrip`
    /// da Home dá o resumo rápido; aqui o paciente entra pra ver o quadro
    /// completo. Sprint 26: substituímos `GamificationHeader` pelo hero de
    /// perfil `ProgressProfileHeader` (nome + level ring + stats).
    @ViewBuilder
    var evolvePageContent: some View {
        ProgressProfileHeader(
            displayName: progressProfileName,
            level: gamificationManager.currentLevel,
            progress: gamificationManager.levelProgress,
            currentXP: gamificationManager.profile?.totalXP ?? 0,
            nextLevelXP: gamificationManager.nextLevel?.xpRequired,
            currentStreak: gamificationManager.currentStreak,
            longestStreak: gamificationManager.longestStreak,
            unlockedBadgesCount: gamificationManager.unlockedBadges.count
        )

        // Padrão de gamificação: sempre mostra o próximo objetivo
        // atingível — mantém motivação com uma meta plausível a curto prazo.
        NextMilestoneCard(
            currentStreak: gamificationManager.currentStreak,
            currentXP: gamificationManager.profile?.totalXP ?? 0,
            currentLevel: gamificationManager.currentLevel,
            nextLevel: gamificationManager.nextLevel,
            checkInCount: sortedCheckIns.count
        )

        StreakCalendar(
            currentStreak: gamificationManager.currentStreak,
            longestStreak: gamificationManager.longestStreak,
            checkInDates: sortedCheckIns.map(\.date)
        )

        if gamificationManager.shouldShowRecoveryBanner {
            StreakRecoveryBanner(
                previousStreak: gamificationManager.currentStreak,
                onCheckInTap: {
                    selectedPatientPage = .diary
                }
            )
        }

        DailyMissionsCarousel(
            missions: gamificationManager.todayMissions,
            isMissionComplete: { mission in
                gamificationManager.isMissionComplete(mission)
            },
            onMissionTap: { mission in
                if mission.category == .checkIn {
                    selectedPatientPage = .diary
                } else if mission.category == .scale {
                    isShowingScales = true
                }
            }
        )

        if let profile = gamificationManager.profile {
            WeeklyGoalProgressCard(
                weeklyProgress: profile.weeklyCheckInProgress,
                weeklyGoal: profile.weeklyCheckInGoal,
                weekStartDate: profile.weeklyGoalResetDate,
                xpReward: 100
            )
        }

        BadgeGrid(
            unlockedBadges: gamificationManager.unlockedBadges,
            allBadgeDefinitions: BadgeDefinition.allBadges,
            onBadgeTap: { _ in }
        )
    }

    /// Nome de exibição do perfil na aba Progresso. Preferimos primeiro nome
    /// (mais amigável); cai pra "Você" quando não há sessão autenticada.
    var progressProfileName: String {
        let trimmed = authenticatedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.split(separator: " ").first, !first.isEmpty {
            return String(first)
        }
        return "Você"
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
