//
//  ContentView+PatientDashboard.swift
//  Neuremia
//

import SwiftUI

extension ContentView {
    var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: activeRole == .clinician ? "brain.head.profile" : "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        LinearGradient(
                            colors: [.neuroYellow, .neuroGold, .neuroOrange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Neuremia")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(activeRole == .clinician ? "Monitoramento claro, contínuo e conectado ao cuidado." : "Um espaço simples para acompanhar seu dia e perceber padrões com mais clareza.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                StatBadge(title: "Registros", value: "\(checkIns.count)", icon: "calendar.badge.clock")
                StatBadge(title: activeRole == .clinician ? "Escalas" : "Check-ups", value: "\(assessments.count)", icon: "checklist.checked")
                StatBadge(title: activeRole == .clinician ? "Risco" : "Hoje", value: patientMoodStatus, icon: activeRole == .clinician ? "waveform.path.ecg" : "sparkles")
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // P3-2 (UX): "Ok" cobria humor 2/ansiedade 2 (clinicamente impreciso).
    // Agora 4 estados mapeiam melhor o espectro de bem-estar do paciente.
    var patientMoodStatus: String {
        if summary.riskLevel == .high || hasCriticalSafetyRisk {
            return "Atenção"
        }
        if summary.riskLevel == .moderate {
            return "Moderado"
        }
        if mood >= 4 && anxiety <= 2 && energy >= 3 {
            return "Bem"
        }
        if mood >= 3 {
            return "Estável"
        }
        return "Difícil"
    }

    // Sprint A: a view `privacyConsent` foi removida — era órfã (zero callers
    // desde Sprint 19/20). O Toggle de consent agora vive inline no
    // safeAreaInset do diário (linhas 1446-1457) e o accessibilityIdentifier
    // "privacyConsentToggle" foi propagado pra lá para o UI test seguir verde.

    /// "Hoje" tab content — gamificado (estilo missões e streak) hero (top strip + missões + CTA)
    /// no topo, seguido do diário. O streak vive na `GamifiedTopStrip`
    /// persistente (Sprint 26) — o `streakBanner` legado foi removido.
    var patientDashboard: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                DailyCoachCard(
                    checkIns: sortedCheckIns,
                    sleepHours: healthSleepHours > 0 ? healthSleepHours : sleepHours,
                    currentHRV: healthHRV > 0 ? healthHRV : ppgManager.hrv,
                    hrvBaseline: hrvBaseline,
                    ppgStress: ppgManager.isHeartRatePhysiologicallyValid ? ppgManager.stress : 0,
                    ppgQuality: max(ppgManager.signalQuality, healthKitPipelineStore.snapshots.first(where: { $0.dayKey == DailyCheckIn.dayKey(for: Date()) })?.qualityScore ?? 0),
                    mood: mood,
                    anxiety: anxiety,
                    energy: energy,
                    irritability: irritability,
                    medicationStatus: medicationStatus,
                    steps: healthSteps,
                    healthKitSnapshots: healthKitPipelineStore.snapshots,
                    lastHealthKitSyncAt: lastHealthKitSyncAt > 0 ? Date(timeIntervalSince1970: lastHealthKitSyncAt) : nil,
                    recommendation: adjustedDailyRecommendation,
                    recommendationLog: todayRecommendationLog,
                    responseProfile: currentRecommendationResponseProfile,
                    retentionProfile: currentRetentionProfile,
                    markRecommendationCompleted: markTodayRecommendationCompleted
                )

                // Barra de gamificação persistente: streak · nível · XP. Sempre no
                // alto da aba, reforça progresso antes de qualquer scroll.
                GamifiedTopStrip(
                    streak: gamificationManager.currentStreak,
                    level: gamificationManager.currentLevel,
                    currentXP: gamificationManager.profile?.totalXP ?? 0,
                    nextLevelXP: gamificationManager.nextLevel?.xpRequired,
                    progress: gamificationManager.levelProgress
                )
                .padding(.top, 2)

                if shouldShowLocalBackupReminder {
                    LocalOnlyBackupReminderCard(
                        lastBackupAt: lastAutomaticBackupAt,
                        intervalDays: backupIntervalDays,
                        backupURL: backupURL,
                        makeBackup: { makeBackupExport() },
                        restoreBackup: { isImportingBackup = true }
                    )
                }

                // M17/P2 (UX): banner de crise visível no TOPO quando risco é
                // alto, antes de qualquer scroll. Antes o CrisisSupportCard só
                // aparecia no final do diário — inacessível numa situação real.
                if hasCriticalSafetyRisk || currentTextAssessment.level == .high {
                    Button {
                        isShowingCrisisSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cross.case.fill")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apoio disponível agora")
                                    .font(.subheadline.weight(.bold))
                                Text("Toque para ver contatos de crise e seu plano de segurança.")
                                    .font(.caption)
                                    .opacity(0.9)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apoio em crise disponível. Toque para abrir contatos e plano de segurança.")
                }

                // Hero de acolhimento + CTA único que rola até o formulário.
                // Vem depois do score para a home abrir como painel passivo:
                // primeiro leitura do dia, depois check-in manual como complemento.
                HeroCheckInCard(
                    greeting: heroGreeting,
                    subtitle: heroSubtitle,
                    hasCheckedInToday: hasCheckedInToday,
                    onQuickCheckInTap: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            proxy.scrollTo("diaryAnchor", anchor: .top)
                        }
                    }
                )

                // Missões do dia em linha compacta — reforço direto de
                // engajamento. As missões maiores continuam na aba Progresso.
                TodayMissionsRail(
                    missions: gamificationManager.todayMissions,
                    isMissionComplete: { gamificationManager.isMissionComplete($0) },
                    onMissionTap: { mission in
                        if mission.category == .checkIn {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                proxy.scrollTo("diaryAnchor", anchor: .top)
                            }
                        } else if mission.category == .scale {
                            isShowingScales = true
                        } else {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                proxy.scrollTo("diaryAnchor", anchor: .top)
                            }
                        }
                    }
                )

                // Atalhos rápidos — SOS, escalas, aprender. Reduz cliques
                // para as ações secundárias mais frequentes.
                QuickActionsRow(
                    onCrisisTap: { isShowingCrisisSheet = true },
                    onScalesTap: { isShowingScales = true },
                    onLearnTap: { isShowingSettings = true }
                )

                // Estado vazio acolhedor — só na primeira sessão. Sinaliza
                // sem julgamento o que o primeiro check-in destrava.
                if sortedCheckIns.isEmpty {
                    EmptyStateHomeCard()
                }

                if shouldShowMoodCoachmark {
                    moodCoachmark
                }
                if shouldShowInvitesBanner {
                    clinicianInvitesBanner
                }
                if !inviteStatusMessage.isEmpty {
                    Label(inviteStatusMessage, systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Usa diário progressivo estilo wizard ou o diário tradicional
                if useProgressiveDiary {
                    progressiveDiaryPage
                        .id("diaryAnchor")
                } else {
                    patientDiaryPage
                        .id("diaryAnchor")
                }
            }
        }
    }

    // MARK: - Hero copy

    /// Saudação sensível ao horário do dia — evita repetir "Como você está?"
    /// e faz o app se sentir vivo. Curta o suficiente para caber no hero.
    var heroGreeting: String {
        let name = (authenticatedName.split(separator: " ").first).map(String.init)
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix: String
        switch hour {
        case 5..<12: prefix = "Bom dia"
        case 12..<18: prefix = "Boa tarde"
        default: prefix = "Boa noite"
        }
        if let name, !name.isEmpty {
            return "\(prefix), \(name)"
        }
        return "\(prefix)"
    }

    /// Copy do hero adapta-se ao progresso: primeiro dia é acolhedor,
    /// streak alto reforça, dia já registrado reconhece o esforço.
    var heroSubtitle: String {
        if hasCheckedInToday {
            return "Registro de hoje salvo. Toque para revisar ou adicionar algo."
        }
        let streak = gamificationManager.currentStreak
        if streak >= 7 {
            return "\(streak) dias seguidos — um passo por vez. Como está hoje?"
        }
        if streak >= 2 {
            return "Você está construindo uma rotina. Como se sente hoje?"
        }
        return "Um espaço tranquilo para perceber como você está."
    }

    /// Existe check-in registrado com data de hoje (calendário local).
    var hasCheckedInToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return sortedCheckIns.contains { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    var shouldShowLocalBackupReminder: Bool {
        guard DataResidencyPolicy.localOnlyMode else { return false }
        guard !checkIns.isEmpty || !assessments.isEmpty || !medicationPlans.isEmpty || !customSymptoms.isEmpty else { return false }
        guard autoBackupEnabled else { return true }
        guard lastAutomaticBackupAt > 0 else { return true }
        let interval = TimeInterval(max(1, backupIntervalDays) * 86_400)
        return Date().timeIntervalSince1970 - lastAutomaticBackupAt >= interval
    }

    func updateHRVBaselineIfNeeded(_ hrv: Double) {
        guard
            biometricConsentAccepted,
            ppgManager.isHeartRatePhysiologicallyValid,
            ppgManager.signalQuality >= 0.65,
            (10...180).contains(hrv)
        else {
            return
        }

        var contextualStore = HRVContextBaselineStore.decode(from: hrvContextBaselinesData)
        contextualStore.record(
            hrv: hrv,
            date: Date(),
            ppgStress: ppgManager.stress,
            sleepHours: healthSleepHours > 0 ? healthSleepHours : sleepHours,
            medicationTaken: isMedicationFullyTaken,
            socialLoad: activeTriggerLabels.count
        )
        hrvContextBaselinesData = contextualStore.encodedString()

        if hrvBaseline <= 0 || hrvBaselineSamples <= 0 {
            hrvBaseline = hrv
            hrvBaselineSamples = 1
            return
        }

        let cappedSamples = min(hrvBaselineSamples, 21)
        let alpha = 1.0 / Double(cappedSamples + 1)
        hrvBaseline = hrvBaseline * (1 - alpha) + hrv * alpha
        hrvBaselineSamples = min(hrvBaselineSamples + 1, 30)
    }

    /// Conteúdo da tab "Ferramentas" — Sprint 20 substituiu o scroll vertical
    /// de 7 cards por uma `List` com seções nativas + NavigationLinks. Cada
    /// item agora vive em sua própria tela, reduzindo carga cognitiva.
    var patientToolsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tudo que apoia seu cuidado em um lugar só.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            toolsList
        }
    }

    var toolsList: some View {
        VStack(spacing: 0) {
            toolsGroup(title: "Sua segurança", icon: "cross.case.fill", tint: .red) {
                toolRow(
                    icon: "figure.mind.and.body",
                    label: "Intervenções guiadas",
                    subtitle: "Respiração, grounding, TCC e mindfulness",
                    destination: AnyView(
                        scrollableDetail(title: "Intervenções guiadas") {
                            GuidedInterventionsLibraryCard(
                                careFocus: selectedCareFocus,
                                riskLevel: neuremiaRiskSignature.level
                            )
                        }
                    )
                )
                toolRow(
                    icon: "shield.lefthalf.filled",
                    label: "Plano de segurança",
                    subtitle: "Sinais de alerta + contato de confiança",
                    destination: AnyView(
                        scrollableDetail(title: "Plano de segurança") {
                            SafetyPlanEditorCard(
                                safetyContact: $safetyContact,
                                warningSigns: $safetyWarningSigns,
                                strategies: $safetyStrategies,
                                signature: neuremiaRiskSignature,
                                careFocus: selectedCareFocus
                            )
                        }
                    )
                )
                toolRow(
                    icon: "phone.fill.arrow.up.right",
                    label: "Apoio em crise",
                    subtitle: "CVV, SAMU e seu contato de segurança",
                    destination: AnyView(
                        scrollableDetail(title: "Apoio em crise") {
                            CrisisSupportCard(
                                safetyContact: safetyContact,
                                warningSigns: safetyWarningSigns,
                                strategies: safetyStrategies,
                                protocolSummary: currentCrisisProtocol
                            )
                        }
                    )
                )
            }

            toolsGroup(title: "Acompanhamento", icon: "stethoscope", tint: .blue) {
                toolRow(
                    icon: "slider.horizontal.3",
                    label: "Personalizar acompanhamento",
                    subtitle: "Sintomas, hábitos, gatilhos e medicações",
                    destination: AnyView(
                        scrollableDetail(title: "Personalizar") {
                            PersonalizationHubCard(
                                medicationName: $medicationName,
                                medicationDose: $medicationDose,
                                medicationSchedule: $medicationSchedule,
                                medicationPrescription: $medicationPrescription,
                                medicationChangeNote: $medicationChangeNote,
                                medicationPlans: medicationPlans,
                                addMedication: addMedicationPlan,
                                removeMedication: removeMedicationPlan,
                                symptomName: $customSymptomName,
                                symptomValue: $customSymptomValue,
                                symptoms: customSymptoms,
                                addSymptom: addCustomSymptom,
                                removeSymptom: removeCustomSymptom,
                                alcoholTrigger: $alcoholTrigger,
                                poorSleepTrigger: $poorSleepTrigger,
                                stressTrigger: $stressTrigger,
                                conflictTrigger: $conflictTrigger,
                                routineChangeTrigger: $routineChangeTrigger,
                                menstrualTrigger: $menstrualTrigger,
                                customTriggerText: $customTriggerText,
                                customTriggers: $customTriggers,
                                checkIns: sortedCheckIns
                            )
                        }
                    )
                )

                // Sinais do corpo movidos da tab primária para cá — são
                // funcionalidades opcionais de uso episódico (PPG via câmera,
                // análise de voz, Apple Health). Ficam acessíveis sem ocupar
                // espaço permanente na tab bar.
                toolRow(
                    icon: "waveform.path.ecg",
                    label: "Sinais do corpo",
                    subtitle: "PPG, frequência cardíaca, voz e Apple Health",
                    destination: AnyView(
                        NavigationStack {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 22) {
                                    patientBodySignalsPage
                                }
                                .padding(20)
                            }
                            .background(appBackground)
                            .navigationTitle("Sinais do corpo")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    )
                )

                // M3 (UX-P0): navega diretamente ao scalesDashboard sem a
                // tela intermediária ScaleAccessCard, eliminando 1 toque extra.
                toolRowButton(
                    icon: "list.clipboard.fill",
                    label: "Check-up estruturado",
                    subtitle: "PHQ-9 · GAD-7 · YMRS (\(sortedAssessments.count) realizados)"
                ) {
                    isShowingScales = true
                }
                toolRow(
                    icon: "flame.fill",
                    label: "Engajamento",
                    subtitle: "Seu progresso no app",
                    destination: AnyView(
                        scrollableDetail(title: "Engajamento") {
                            EngagementCard(checkInCount: checkIns.count, recentCheckIns: sortedCheckIns)
                        }
                    )
                )
            }

            toolsGroup(title: "Aprender", icon: "book.fill", tint: .purple) {
                toolRow(
                    icon: "books.vertical.fill",
                    label: "Trilhas de aprendizado",
                    subtitle: "Sono, medicação, recaída e consulta",
                    destination: AnyView(
                        scrollableDetail(title: "Trilhas") {
                            EducationPathwaysCard(selectedFocus: selectedCareFocus)
                        }
                    )
                )
                toolRow(
                    icon: "graduationcap.fill",
                    label: "Psicoeducação",
                    subtitle: "Material curado para o seu foco",
                    destination: AnyView(
                        scrollableDetail(title: "Psicoeducação") {
                            PsychoeducationCard()
                        }
                    )
                )
                toolRow(
                    icon: "questionmark.circle.fill",
                    label: "Por que pergunto isso?",
                    subtitle: "Como suas respostas alimentam o cuidado",
                    destination: AnyView(
                        scrollableDetail(title: "Por que pergunto isso?") {
                            DSM5FoundationCard(selectedFocus: selectedCareFocus)
                        }
                    )
                )
            }

            toolsGroup(title: "Compartilhar", icon: "square.and.arrow.up", tint: .green) {
                toolRow(
                    icon: "calendar.badge.clock",
                    label: "Relatório mensal automático",
                    subtitle: "Envio para sua equipe de cuidado",
                    destination: AnyView(
                        scrollableDetail(title: "Relatório mensal") {
                            MonthlyReportAutomationCard(
                                isEnabled: $autoMonthlyReportEnabled,
                                reportStatusMessage: reportStatusMessage,
                                generateReport: generateReport
                            )
                        }
                    )
                )
                toolRow(
                    icon: "doc.text.fill",
                    label: "Exportar PDF / CSV",
                    subtitle: "Levar para consulta",
                    destination: AnyView(
                        scrollableDetail(title: "Exportar relatório") {
                            PatientReportExportCard(
                                reportPreview: reportPreview,
                                pdfURL: reportPDFURL,
                                csvURL: reportCSVURL,
                                generateReport: generateReport
                            )
                        }
                    )
                )
            }
        }
    }

    @ViewBuilder
    func toolsGroup<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 12)
    }

    @ViewBuilder
    func toolRow(
        icon: String,
        label: String,
        subtitle: String,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 54)
        }
    }

    /// Variante de toolRow que executa uma ação imediata em vez de navegar
    /// para uma tela destino — usada quando a sheet já está disponível na
    /// raiz (ex.: scalesDashboard via isShowingScales). M3 (UX-P0).
    func toolRowButton(
        icon: String,
        label: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 54)
        }
    }

    @ViewBuilder
    func scrollableDetail<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(20)
        }
        .background(appBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Dashboard médico (Sprint 24)

    /// Filtro/ordenação da lista de pacientes vinculados.
    var filteredClinicianPatients: [BackendUser] {
        let base = clinicianPatients.sortedByRisk
        switch clinicianPatientFilter {
        case .all:
            return base
        case .highRisk:
            return base.filter { ($0.riskScore ?? 0) >= 66 }
        case .alphabetical:
            return base.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        }
    }

    /// Convites enviados filtrados por status (todos / pendentes / aceitos / recusados).
    var filteredSentInvites: [BackendSentInvite] {
        guard let target = sentInvitesFilter.apiStatus else { return clinicianSentInvites }
        return clinicianSentInvites.filter { $0.status == target }
    }

    /// Coachmark do primeiro check-in (Sprint 23 / J1). Mostra dica
    /// contextual logo após o onboarding até o paciente registrar o primeiro
    /// check-in OU descartar manualmente.
    var shouldShowMoodCoachmark: Bool {
        hasCompletedOnboarding
            && !hasSeenMoodCoachmark
            && activeRole == .patient
            && checkIns.isEmpty
    }

    var moodCoachmark: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.point.down.fill")
                .font(.title2)
                .foregroundStyle(Color.neuroOrange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Comece tocando em uma emoção")
                    .font(.subheadline.weight(.semibold))
                Text("A roda abaixo ajusta humor, ansiedade e energia juntos. Depois, salve no rodapé.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                hasSeenMoodCoachmark = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dispensar dica")
        }
        .padding(12)
        .background(Color.neuroYellow.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.neuroGold.opacity(0.45), lineWidth: 1)
        )
    }

    /// Conta quantos dias consecutivos (terminando hoje ou ontem) o paciente
    /// registrou check-in. Reforço positivo discreto na tab Hoje (Sprint 23).
    var currentCheckInStreak: Int {
        guard !sortedCheckIns.isEmpty else { return 0 }
        let calendar = Calendar.current
        var expected = calendar.startOfDay(for: Date())
        var streak = 0
        // Aceita ontem como início da janela (paciente pode estar acordando
        // antes de registrar hoje).
        if let firstDate = sortedCheckIns.first?.date,
           calendar.isDateInYesterday(firstDate) {
            expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
        }
        for checkIn in sortedCheckIns {
            let day = calendar.startOfDay(for: checkIn.date)
            if calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            } else if day < expected {
                break
            }
        }
        return streak
    }

    /// Contador combinado para o badge da tab "Hoje" (Sprint 23). Soma
    /// convites pendentes (ignorando snooze — badge é discreto) com alertas
    /// clínicos não reconhecidos.
    var homeTabBadgeCount: Int {
        let pendingInvites = pendingClinicianInvites.count
        let unackedAlerts = activeAlerts.filter { $0.kind != ClinicalAlertKind.selfSignal.rawValue }.count
        return pendingInvites + unackedAlerts
    }

    /// Banner aparece quando há convite pendente E o snooze de 24h expirou.
    /// Pacientes podem postergar pra reduzir ansiedade ambiental sem perder
    /// o convite (Sprint 21).
    var shouldShowInvitesBanner: Bool {
        guard !pendingClinicianInvites.isEmpty else { return false }
        return Date().timeIntervalSince1970 >= inviteSnoozedUntil
    }

    var clinicianInvitesBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label("Convites de profissional", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    inviteSnoozedUntil = Date().addingTimeInterval(24 * 3600).timeIntervalSince1970
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Decidir depois")
                .accessibilityHint("Esconde os convites por 24 horas. Eles continuam disponíveis nas configurações.")
            }

            Text("Profissionais que pediram para acompanhar você. O vínculo só é criado depois que você aceitar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(pendingClinicianInvites) { invite in
                VStack(alignment: .leading, spacing: 8) {
                    Text(invite.clinicianFullName)
                        .font(.subheadline.weight(.semibold))
                    Text(invite.clinicianEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            Task { await acceptInvite(invite) }
                        } label: {
                            Label("Aceitar", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Aceita que \(invite.clinicianFullName) acompanhe seus registros.")

                        Button(role: .destructive) {
                            Task { await revokeInvite(invite) }
                        } label: {
                            Label("Recusar", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Rejeita o convite e impede o vínculo.")
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.neuroYellow.opacity(0.18), Color(.secondarySystemGroupedBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.neuroGold.opacity(0.35), lineWidth: 1)
        }
    }


}
