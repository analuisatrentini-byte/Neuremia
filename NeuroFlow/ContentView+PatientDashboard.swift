//
//  ContentView+PatientDashboard.swift
//  NeuroFlow
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
                    Text("NeuroFlow")
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

    /// "Hoje" tab content — streak + banner de convites + status + diário.
    /// Sprint 23 adicionou o `streakBanner` no topo para reforço positivo.
    var patientDashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            if shouldShowMoodCoachmark {
                moodCoachmark
            }
            if currentCheckInStreak >= 2 {
                streakBanner
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
            patientDiaryPage
        }
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
                    icon: "shield.lefthalf.filled",
                    label: "Plano de segurança",
                    subtitle: "Sinais de alerta + contato de confiança",
                    destination: AnyView(
                        scrollableDetail(title: "Plano de segurança") {
                            SafetyPlanEditorCard(
                                safetyContact: $safetyContact,
                                warningSigns: $safetyWarningSigns,
                                strategies: $safetyStrategies,
                                signature: neuroFlowRiskSignature,
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
                                strategies: safetyStrategies
                            )
                        }
                    )
                )
            }

            toolsGroup(title: "Acompanhamento", icon: "stethoscope", tint: .blue) {
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

    var streakBanner: some View {
        HStack(spacing: 10) {
            Text("🔥")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(currentCheckInStreak) dias seguidos")
                    .font(.subheadline.weight(.bold))
                Text("Continue — pequenos passos contam.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.neuroYellow.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Você registrou \(currentCheckInStreak) dias seguidos. Continue.")
    }

    /// Contador combinado para o badge da tab "Hoje" (Sprint 23). Soma
    /// convites pendentes (ignorando snooze — badge é discreto) com alertas
    /// clínicos não reconhecidos.
    var homeTabBadgeCount: Int {
        let pendingInvites = pendingClinicianInvites.count
        let unackedAlerts = activeAlerts.count
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
