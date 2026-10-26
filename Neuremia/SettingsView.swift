//
//  SettingsView.swift
//  Neuremia
//

import SwiftUI
import SwiftData
import HealthKit
import UIKit
import Network

extension ContentView {
    var settingsDashboard: some View {
        // S6 (UX): consolidado de 6 seções técnicas para 6 seções orientadas
        // por intenção do usuário. Jargão técnico removido do texto visível.
        Form {
            // ── 1. Conta e acesso ─────────────────────────────────────────────
            Section("Conta e acesso") {
                if DataResidencyPolicy.remoteSyncEnabled {
                    settingsNavLink(
                        icon: "person.crop.circle.fill",
                        tint: .blue,
                        label: isLoggedIn ? "Minha conta" : "Entrar na conta",
                        subtitle: authenticatedEmail.isEmpty ? "Não autenticado" : authenticatedEmail
                    ) {
                        scrollableDetail(title: "Conta") { loginSettingsCard }
                    }

                    if authenticatedRole == "clinician" || activeRole == .clinician {
                        settingsNavLink(
                            icon: "person.text.rectangle.fill",
                            tint: .indigo,
                            label: "Perfil de acesso",
                            subtitle: activeRole == .clinician ? "Médico" : "Paciente"
                        ) {
                            scrollableDetail(title: "Perfil de acesso") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Picker("Perfil de acesso", selection: roleBinding) {
                                        ForEach(AccessRole.allCases) { role in
                                            Label(role.rawValue, systemImage: role.icon).tag(role)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .confirmationDialog(
                                        roleChangePending == .clinician
                                            ? "Trocar para perfil médico?"
                                            : "Trocar para perfil paciente?",
                                        isPresented: Binding(
                                            get: { roleChangePending != nil },
                                            set: { if !$0 { roleChangePending = nil } }
                                        ),
                                        titleVisibility: .visible
                                    ) {
                                        Button(roleChangePending == .clinician ? "Alternar para médico" : "Alternar para paciente") {
                                            if let pending = roleChangePending { applyRoleChange(pending) }
                                            roleChangePending = nil
                                        }
                                        Button("Cancelar", role: .cancel) { roleChangePending = nil }
                                    } message: {
                                        Text("A troca muda o dashboard ativo e os dados visíveis. Você pode reverter a qualquer momento.")
                                    }

                                    PrivacyStatusGrid(
                                        consentAccepted: patients.first?.consentAccepted == true,
                                        shareWithClinician: patients.first?.shareWithClinician == true,
                                        shareWithCaregiver: shareWithCaregiver,
                                        activeRole: activeRole
                                    )
                                }
                                .panelStyle()
                            }
                        }
                    }
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Modo local")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("Seus registros ficam neste aparelho. Login e sincronização remota não estão disponíveis nesta versão.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                Button {
                    hasCompletedOnboarding = false
                    onboardingStep = 0
                    isShowingSettings = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Refazer apresentação")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("Veja as boas-vindas e ajuste seu foco de cuidado.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            // ── 2. Meu médico e cuidadores ────────────────────────────────────
            if DataResidencyPolicy.remoteSyncEnabled {
                Section("Meu médico e cuidadores") {
                settingsNavLink(
                    icon: "stethoscope",
                    tint: .green,
                    label: "Profissionais com acesso",
                    subtitle: linkedClinicians.isEmpty ? "Nenhum vínculo ativo" : "\(linkedClinicians.count) profissionais"
                ) {
                    scrollableDetail(title: "Profissionais") { linkedCliniciansCard }
                }

                settingsNavLink(
                    icon: "person.2.fill",
                    tint: .blue,
                    label: "Cuidadores",
                    subtitle: remoteCaregivers.isEmpty ? "Nenhum cadastrado" : "\(remoteCaregivers.count) cadastrados"
                ) {
                    scrollableDetail(title: "Cuidadores") { caregiverManagementCard }
                }

                settingsNavLink(
                    icon: "envelope.arrow.triangle.branch.fill",
                    tint: .teal,
                    label: "Compartilhar com minha equipe",
                    subtitle: careTeamSendStatus
                ) {
                    scrollableDetail(title: "Equipe de cuidado") {
                        CareTeamAutoSendCard(
                            isEnabled: $autoCareTeamSendEnabled,
                            contact: $careTeamContact,
                            caregiverName: $caregiverName,
                            caregiverRelationship: $caregiverRelationship,
                            canShare: patients.first?.consentAccepted == true && (patients.first?.shareWithClinician == true || shareWithCaregiver),
                            canShareCaregiver: patients.first?.consentAccepted == true && shareWithCaregiver,
                            status: careTeamSendStatus,
                            caregivers: remoteCaregivers,
                            saveCaregiver: { Task { await saveCaregiverContact() } },
                            refreshCaregivers: { Task { await loadCaregivers() } },
                            sendNow: sendCurrentReportToCareTeam
                        )
                    }
                }

                settingsNavLink(
                    icon: "slider.horizontal.3",
                    tint: .purple,
                    label: "Governança clínica",
                    subtitle: "Limiar, digest e consentimentos"
                ) {
                    scrollableDetail(title: "Governança clínica") {
                        ClinicalGovernanceSettingsCard(
                            moodThreshold: $patientMoodModerateThreshold,
                            anxietyThreshold: $patientAnxietyModerateThreshold,
                            sleepThreshold: $patientMinimumSleepThreshold,
                            caregiverDigestConsent: $caregiverDigestConsent,
                            caregiverSMSConsent: $caregiverSMSConsent,
                            criticalPushConsent: $criticalPushConsent,
                            shareWithClinician: patients.first?.shareWithClinician == true,
                            shareWithCaregiver: shareWithCaregiver
                        )
                    }
                }
            }
            }

            // ── 3. Privacidade ────────────────────────────────────────────────
            Section("Privacidade") {
                settingsNavLink(
                    icon: "lock.shield.fill",
                    tint: .red,
                    label: "Meus dados",
                    subtitle: "Exportar, apagar, histórico de acesso"
                ) {
                    scrollableDetail(title: "Meus dados") { privacyAndDataCard }
                }

                settingsNavLink(
                    icon: "lock.shield",
                    tint: .blue,
                    label: "Como seus dados são protegidos",
                    subtitle: nil
                ) {
                    scrollableDetail(title: "Segurança") {
                        VStack(alignment: .leading, spacing: 14) {
                            if DataResidencyPolicy.remoteSyncEnabled {
                                ComplianceRow(icon: "person.badge.key", title: "Acesso seguro", description: "Suas credenciais nunca ficam salvas em texto puro. A sessão expira automaticamente e pode ser encerrada a qualquer momento.")
                                ComplianceRow(icon: "checkmark.seal", title: "Você decide o que compartilha", description: "O app bloqueia o salvamento até que você aceite expressamente. Autorizar o registro é independente de autorizar o compartilhamento com seu médico.")
                                ComplianceRow(icon: "eye.slash", title: "Acesso do seu médico é controlado", description: "Seu médico só consegue ver seus dados após você aceitar o convite. Você pode revogar esse acesso a qualquer momento.")
                            } else {
                                ComplianceRow(icon: "iphone.and.arrow.forward", title: "Uso local", description: "Esta versão não usa login, convites ou sincronização clínica remota. Seus registros ficam neste aparelho, salvo quando você exporta ou compartilha manualmente um arquivo.")
                                ComplianceRow(icon: "checkmark.seal", title: "Você decide o que registra", description: "O app bloqueia o salvamento até que você aceite expressamente o uso local dos dados de saúde.")
                            }
                            ComplianceRow(icon: "lock.doc", title: "Dados criptografados no dispositivo", description: "Textos sensíveis (diário, pensamentos, efeitos colaterais) são criptografados antes de serem armazenados no seu aparelho.")
                            ComplianceRow(icon: "doc.text", title: "Lei Geral de Proteção de Dados (LGPD)", description: "Você pode exportar seus dados em Meus dados e remover registros locais apagando os dados do app.")
                        }
                        .panelStyle()
                    }
                }
            }

            // ── 4. Lembretes ──────────────────────────────────────────────────
            Section("Lembretes") {
                settingsNavLink(
                    icon: "bell.badge.fill",
                    tint: .orange,
                    label: "Lembretes diários",
                    subtitle: nil
                ) {
                    scrollableDetail(title: "Lembretes") { reminderSettingsCard }
                }

                if DataResidencyPolicy.remoteSyncEnabled {
                    settingsNavLink(
                        icon: "bell.and.waves.left.and.right",
                        tint: .purple,
                        label: "Notificações pelo app do médico",
                        subtitle: remotePushStatus
                    ) {
                        scrollableDetail(title: "Notificações") {
                            RemotePushCard(
                                isEnabled: $remotePushEnabled,
                                status: remotePushStatus,
                                token: apnsDeviceToken,
                                register: { Task { await requestRemotePushRegistration() } },
                                uploadToken: { Task { await uploadPushTokenToBackend() } }
                            )
                        }
                    }
                }
            }

            // ── 5. Integrações ────────────────────────────────────────────────
            Section("Integrações") {
                settingsNavLink(
                    icon: "heart.fill",
                    tint: .pink,
                    label: "Apple Health",
                    subtitle: healthKitStatus
                ) {
                    scrollableDetail(title: "Apple Health") {
                        HealthKitIntegrationCard(
                            isEnabled: $healthKitEnabled,
                            status: healthKitStatus,
                            sleepHours: healthSleepHours,
                            steps: healthSteps,
                            heartRate: healthHeartRate,
                            activeEnergy: healthActiveEnergy,
                            hrv: healthHRV,
                            lastSyncAt: lastHealthKitSyncAt,
                            snapshots: healthKitPipelineStore.snapshots,
                            sync: { Task { await requestHealthKitAccessAndSync() } }
                        )
                    }
                }

                settingsNavLink(
                    icon: "externaldrive.fill",
                    tint: .gray,
                    label: "Cópia de segurança",
                    subtitle: backgroundBackupStatus
                ) {
                    scrollableDetail(title: "Cópia de segurança") {
                        BackupExportCard(
                            backupURL: backupURL,
                            isAutomatic: $autoBackupEnabled,
                            intervalDays: $backupIntervalDays,
                            lastAutomaticBackupAt: lastAutomaticBackupAt,
                            backupStatus: loginStatusMessage,
                            backgroundStatus: backgroundBackupStatus,
                            localOnlyMode: DataResidencyPolicy.localOnlyMode,
                            makeBackup: { makeBackupExport() },
                            restoreBackup: { isImportingBackup = true }
                        )
                    }
                }
            }

            // ── 6. Documentos ─────────────────────────────────────────────────
            Section("Documentos") {
                settingsNavLink(
                    icon: "doc.text",
                    tint: .secondary,
                    label: "Termos de uso",
                    subtitle: nil
                ) {
                    LegalDocumentView(title: "Termos de Uso", documentText: neuremiaTermsOfUse)
                }

                settingsNavLink(
                    icon: "hand.raised.fill",
                    tint: .secondary,
                    label: "Política de privacidade",
                    subtitle: nil
                ) {
                    LegalDocumentView(title: "Política de Privacidade", documentText: neuremiaPrivacyPolicy)
                }
            }

            #if DEBUG
            Section("Diagnóstico") {
                NavigationLink("Status de produção") {
                    scrollableDetail(title: "Status de produção") { ProductionReadinessCard() }
                }
                NavigationLink("Validação clínica") {
                    scrollableDetail(title: "Validação clínica") { ClinicalValidationRoadmapCard() }
                }
            }
            #endif
        }
    }

    /// Linha padrão de Settings — ícone colorido com tint + label + subtítulo.
    /// Cor da bolinha distingue grupos sem precisar ler.
    @ViewBuilder
    func settingsNavLink<Destination: View>(
        icon: String,
        tint: Color,
        label: String,
        subtitle: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    var privacyAndDataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "lock.shield", title: "Privacidade e dados (LGPD)")

            Text("Direitos do titular: exportar tudo que está armazenado, apagar registros antigos ou encerrar sua conta. Estas ações usam endpoints autenticados do backend.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Conteúdo e segurança", systemImage: "exclamationmark.bubble")
                    .font(.subheadline.weight(.semibold))
                Text("Se encontrar conteúdo abusivo, uso indevido dos seus dados ou conduta inadequada ligada ao cuidado, denuncie pelo suporte. Para impedir acesso de um profissional, cancele o vínculo em Profissionais com acesso.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    reportContentProblem(context: "Denúncia geral iniciada em Privacidade e dados.")
                } label: {
                    Label("Denunciar conteúdo ou conduta", systemImage: "exclamationmark.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Abre o e-mail de suporte para denunciar conteúdo, abuso ou uso indevido.")
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !privacyStatusMessage.isEmpty {
                Label(privacyStatusMessage, systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await exportMyAccount() }
            } label: {
                Label("Baixar meus dados (JSON)", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Solicita ao backend uma exportação completa da sua conta em JSON.")

            if let exportURL = privacyExportURL {
                ShareLink(item: exportURL) {
                    Label("Compartilhar exportação", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Picker semântico no lugar do Stepper (Sprint 21) — paciente
            // pensa em "1 ano" ou "6 meses", não em "1290 dias".
            // P2-11 (UX): label sem reticências + valor selecionado visível.
            Picker("Retenção de dados", selection: $privacyRetentionDays) {
                Text("90 dias").tag(90)
                Text("6 meses").tag(180)
                Text("1 ano").tag(365)
                Text("2 anos").tag(730)
                Text("5 anos").tag(1825)
            }
            .pickerStyle(.menu)
            .accessibilityHint("Define a janela mantida no backend. Registros mais antigos podem ser apagados pelo botão abaixo.")

            Button(role: .destructive) {
                isConfirmingClinicalWipe = true
            } label: {
                Label("Apagar dados clínicos antigos", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Remove do backend registros com mais de \(privacyRetentionDays) dias.")

            Button {
                Task { await fetchAuditLogs() }
            } label: {
                Label("Ver minha auditoria", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)

            Divider()

            // LGPD Art. 9 § 1 — consentimento para dados biométricos deve ser
            // destacado, específico e revogável a qualquer momento.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sinais biométricos (câmera e voz)")
                        .font(.subheadline.weight(.semibold))
                    if biometricConsentAccepted && biometricConsentGrantedAt > 0 {
                        Text("Consentimento ativo desde \(Date(timeIntervalSince1970: biometricConsentGrantedAt).formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text(biometricConsentAccepted ? "Consentimento ativo — processamento local." : "Consentimento não concedido.")
                            .font(.caption)
                            .foregroundStyle(biometricConsentAccepted ? .green : .secondary)
                    }
                }
                Spacer()
                if biometricConsentAccepted {
                    Button(role: .destructive) {
                        ppgManager.stop()
                        voiceManager.stop()
                        biometricConsentAccepted = false
                        biometricConsentGrantedAt = 0
                        // M4 — sync revocation with backend consent registry.
                        if !authToken.isEmpty {
                            Task { try? await BackendAuthClient.revokeBiometricConsent(token: authToken) }
                        }
                    } label: {
                        Text("Revogar")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
            .accessibilityElement(children: .combine)

            Button(role: .destructive) {
                isConfirmingAccountDelete = true
            } label: {
                Label("Apagar minha conta", systemImage: "person.crop.circle.badge.xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(authToken.isEmpty)
            .accessibilityHint("Remove conta, vínculos médicos, alertas, relatórios e tokens do backend.")

            Divider()

            // ── Documentos legais ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("Documentos legais")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        activeLegalDocument = .terms
                    } label: {
                        Label("Termos de Uso", systemImage: "doc.text")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        activeLegalDocument = .privacy
                    } label: {
                        Label("Privacidade", systemImage: "lock.doc")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if legalAcceptedVersion == LegalVersion.current {
                    Label("Versão \(LegalVersion.current) aceita", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        legalAcceptedVersion = ""  // force re-presentation of consent gate
                    } label: {
                        Label("Revisar consentimento (v\(LegalVersion.current))", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
        .alert("Apagar dados clínicos antigos?", isPresented: $isConfirmingClinicalWipe) {
            Button("Apagar", role: .destructive) {
                Task { await deleteOldClinicalData() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Apaga do backend todos os check-ins, escalas, alertas e relatórios com mais de \(privacyRetentionDays) dias. Os dados locais no aparelho permanecem.")
        }
        .alert("Apagar minha conta definitivamente?", isPresented: $isConfirmingAccountDelete) {
            Button("Apagar minha conta", role: .destructive) {
                Task { await deleteMyAccount() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta ação remove conta, vínculos clínicos, alertas, relatórios, tokens e cuidadores no backend. Não pode ser desfeita.")
        }
        .sheet(isPresented: $isShowingAuditLogs) {
            NavigationStack {
                List(remoteAuditLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.action)
                            .font(.subheadline.weight(.semibold))
                        Text("\(log.resourceType) · \(log.resourceId)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(log.createdAt)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                .navigationTitle("Minha auditoria")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") { isShowingAuditLogs = false }
                    }
                }
            }
        }
        .sheet(item: $activeLegalDocument) { document in
            LegalDocumentView(title: document.title, documentText: document.text)
        }
    }

    var linkedCliniciansCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "stethoscope", title: "Profissionais com acesso")

            Text("Profissionais que aceitaram acompanhar você. Você pode cancelar o acesso a qualquer momento.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if linkedClinicians.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para ver quem acompanha você." : "Ninguém está acompanhando você no momento. Quando aceitar um convite, o profissional aparece aqui.")
            } else {
                ForEach(linkedClinicians) { clinician in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.fill.checkmark")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(clinician.clinicianFullName)
                                .font(.subheadline.weight(.semibold))
                            Text(clinician.clinicianEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Menu {
                            Button {
                                reportContentProblem(
                                    context: "Denúncia sobre profissional vinculado.",
                                    clinician: clinician
                                )
                            } label: {
                                Label("Denunciar problema", systemImage: "exclamationmark.bubble")
                            }

                            Button(role: .destructive) {
                                clinicianToRevoke = clinician
                            } label: {
                                Label("Cancelar acesso", systemImage: "xmark.shield")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Ações para \(clinician.clinicianFullName)")
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // P1-2: status migrado para toast central.
        }
        .panelStyle()
        // Borda lateral verde — "médico já tem acesso ativo aos meus dados".
        // Sprint 21: diferenciação visual contra cards de cuidadores e
        // convites enviados.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
        .alert(
            "Cancelar acesso?",
            isPresented: Binding(
                get: { clinicianToRevoke != nil },
                set: { if !$0 { clinicianToRevoke = nil } }
            ),
            presenting: clinicianToRevoke
        ) { clinician in
            Button("Cancelar acesso", role: .destructive) {
                Task { await revokeClinicalAccess(clinician) }
                clinicianToRevoke = nil
            }
            Button("Manter", role: .cancel) {
                clinicianToRevoke = nil
            }
        } message: { clinician in
            Text("\(clinician.clinicianFullName) perderá acesso aos seus check-ins, escalas e alertas. Você pode aceitar um novo convite no futuro.")
        }
    }

    var caregiverManagementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.2.gobackward", title: "Cuidadores cadastrados")

            if remoteCaregivers.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para convidar pessoas de confiança." : "Você pode adicionar alguém de confiança que receberá alertas se algo precisar de atenção.")
            } else {
                ForEach(remoteCaregivers) { caregiver in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: caregiver.shareEnabled ? "checkmark.shield.fill" : "shield.slash")
                            .foregroundStyle(caregiver.shareEnabled ? .green : .secondary)
                            .accessibilityLabel(caregiver.shareEnabled ? "Compartilhamento ativo" : "Compartilhamento desativado")

                        VStack(alignment: .leading, spacing: 4) {
                            Text(caregiver.name)
                                .font(.subheadline.weight(.semibold))
                            Text(caregiver.contact)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !caregiver.relationship.isEmpty {
                                Text(caregiver.relationship)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer()

                        Button {
                            beginEditingCaregiver(caregiver)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel("Editar dados de \(caregiver.name)")

                        Button(role: .destructive) {
                            caregiverDeleteTarget = caregiver
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Remover cuidador \(caregiver.name)")

                        Button {
                            caregiverToggleTarget = caregiver
                        } label: {
                            Image(systemName: caregiver.shareEnabled ? "bell.slash" : "bell")
                        }
                        .accessibilityLabel(caregiver.shareEnabled ? "Pausar notificações para \(caregiver.name)" : "Reativar notificações para \(caregiver.name)")
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // P1-2: status migrado para toast central.
        }
        .confirmationDialog(
            caregiverToggleTarget.map { $0.shareEnabled ? "Pausar notificações para \($0.name)?" : "Reativar notificações para \($0.name)?" } ?? "",
            isPresented: Binding(get: { caregiverToggleTarget != nil }, set: { if !$0 { caregiverToggleTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = caregiverToggleTarget {
                Button(target.shareEnabled ? "Pausar" : "Reativar") {
                    Task { await toggleCaregiverSharing(target) }
                    caregiverToggleTarget = nil
                }
                Button("Cancelar", role: .cancel) { caregiverToggleTarget = nil }
            }
        }
        .confirmationDialog(
            caregiverDeleteTarget.map { "Remover \($0.name)?" } ?? "Remover cuidador?",
            isPresented: Binding(get: { caregiverDeleteTarget != nil }, set: { if !$0 { caregiverDeleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = caregiverDeleteTarget {
                Button("Remover cuidador", role: .destructive) {
                    Task { await deleteCaregiver(target) }
                    caregiverDeleteTarget = nil
                }
                Button("Cancelar", role: .cancel) { caregiverDeleteTarget = nil }
            }
        } message: {
            Text("A pessoa removida deixará de receber alertas e relatórios autorizados.")
        }
        .panelStyle()
        // Borda lateral azul — "cuidador/rede de apoio com permissão de
        // alertas" (Sprint 21).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
    }

    var reminderSettingsCard: some View {
        // S7 (UX): lembretes salvam automaticamente ao mudar toggle ou horário.
        // O modelo mental do usuário é "liguei = ativado" — exigir um botão
        // extra após o toggle quebrava esse modelo e gerava suporte ("por que
        // meu lembrete não chegou?"). Feedback dado via toast central.
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(icon: "bell.badge", title: "Lembretes")

            Toggle("Lembrar de tomar medicação", isOn: $medicationReminderEnabled)
                .toggleStyle(.switch)
                .onChange(of: medicationReminderEnabled) { _, _ in
                    Task { await configureLocalReminders() }
                }

            DatePicker(
                "Horário da medicação",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: medicationReminderHour, minute: 0, second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: {
                        medicationReminderHour = Calendar.current.component(.hour, from: $0)
                        Task { await configureLocalReminders() }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!medicationReminderEnabled)

            Toggle("Lembrar de registrar o dia", isOn: $checkInReminderEnabled)
                .toggleStyle(.switch)
                .onChange(of: checkInReminderEnabled) { _, _ in
                    Task { await configureLocalReminders() }
                }

            DatePicker(
                "Horário do registro diário",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: checkInReminderHour, minute: 0, second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: {
                        checkInReminderHour = Calendar.current.component(.hour, from: $0)
                        Task { await configureLocalReminders() }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!checkInReminderEnabled)

            Divider()
                .padding(.vertical, 2)

            Toggle("Manter minha sequência diária", isOn: $dailyRetentionReminderEnabled)
                .toggleStyle(.switch)
                .onChange(of: dailyRetentionReminderEnabled) { _, _ in
                    Task { await configureLocalReminders() }
                }

            DatePicker(
                "Horário da sequência",
                selection: Binding(
                    get: {
                        Calendar.current.date(
                            bySettingHour: dailyRetentionReminderHour, minute: 0, second: 0, of: Date()
                        ) ?? Date()
                    },
                    set: {
                        dailyRetentionReminderHour = Calendar.current.component(.hour, from: $0)
                        Task { await configureLocalReminders() }
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .disabled(!dailyRetentionReminderEnabled)

            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Use este lembrete para voltar ao app, manter a rotina e ganhar XP no check-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Os avisos chegam pelo próprio iPhone, mesmo sem internet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }

    var loginSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(isLoggedIn ? Color.white : Color.neuroNavy)
                    .frame(width: 44, height: 44)
                    .background(isLoggedIn ? Color.green : Color.neuroYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLoggedIn ? "Conta conectada" : isCreatingAccount ? "Criar conta" : "Entrar na conta")
                        .font(.headline)

                    Text(isLoggedIn ? "\(authenticatedName) • \(authenticatedEmail)" : loginSettingsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            VStack(spacing: 10) {
                if isCreatingAccount {
                    TextField("Nome completo", text: $fullName)
                        .textContentType(.name)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                TextField("E-mail", text: $loginEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                SecureField("Senha", text: $loginPassword)
                    .textContentType(.password)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // P3-1 (UX): botão de logout separado visualmente do de login —
            // antes usavam o mesmo .borderedProminent e ficavam no mesmo lugar,
            // risco de logout acidental (ação que limpa a sessão local).
            if isLoggedIn {
                Divider()
                Button(role: .destructive) {
                    Task { await handleAuthenticationButton() }
                } label: {
                    Label("Sair da conta", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button {
                    Task { await handleAuthenticationButton() }
                } label: {
                    Label(authButtonTitle, systemImage: "arrow.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthButtonDisabled)
            }

            if !isLoggedIn {
                HStack(spacing: 8) {
                    Button {
                        isCreatingAccount.toggle()
                        loginStatusMessage = ""
                    } label: {
                        Text(isCreatingAccount ? "Já tenho conta" : "Criar nova conta")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task {
                            await requestPasswordReset()
                        }
                    } label: {
                        Text(isRequestingPasswordReset ? "Enviando..." : "Esqueci a senha")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(loginEmail.isEmpty || isRequestingPasswordReset)
                }

                Button {
                    passwordResetStatusMessage = ""
                    isShowingPasswordResetConfirm = true
                } label: {
                    Label("Tenho um código de recuperação", systemImage: "key.horizontal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(loginEmail.isEmpty)
                .accessibilityHint("Abre o formulário para enviar o código recebido por e-mail e definir uma nova senha.")
            }

            // P1-2: loginStatusMessage migrado para toast central.
            // P2-1 (UX): URL do backend e instrução de infraestrutura
            // removidas da UI de produção — expor detalhes técnicos prejudica
            // a confiança do usuário. Visível apenas em builds de Debug.
            #if DEBUG
            Text("Debug: conectando em http://127.0.0.1:8000")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            #endif
        }
        .panelStyle()
    }

    private var loginSettingsSubtitle: String {
        DataResidencyPolicy.localOnlyMode
            ? "Conta opcional. Seus dados clínicos ficam neste aparelho nesta versão."
            : "Entre para sincronizar seus dados com segurança."
    }

    // Sprint 25: histórico passa a respeitar `evolutionFilter` + `evolutionSearchQuery`.
    // O filtro decide quais coleções aparecem; a busca recorta dentro de cada uma.
    @ViewBuilder
    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "clock.arrow.circlepath", title: historySectionTitle)

            if historyHasAnyVisibleContent {
                if evolutionFilter == .all || evolutionFilter == .checkIns {
                    historyCheckInsGroup
                }
                if evolutionFilter == .all || evolutionFilter == .scales {
                    historyScalesGroup
                }
                if evolutionFilter == .all || evolutionFilter == .alerts {
                    historyAlertsGroup
                }
            } else {
                // P2-3 (UX): empty state com ação direta para o diário
                // quando ainda não há registros — elimina o dead-end
                // "leva menos de 1 minuto" sem caminho para começar.
                EmptyState(
                    text: historyEmptyMessage,
                    actionLabel: evolutionFilter == .all && checkIns.isEmpty ? "Fazer primeiro registro" : nil,
                    action: evolutionFilter == .all && checkIns.isEmpty
                        ? { selectedPatientPage = .diary }
                        : nil
                )
            }
        }
    }

    var historySectionTitle: String {
        switch evolutionFilter {
        case .all: "Histórico recente"
        case .checkIns: "Check-ins recentes"
        case .scales: "Escalas recentes"
        case .alerts: "Alertas recentes"
        }
    }

    var historyEmptyMessage: String {
        if !evolutionQueryNormalized.isEmpty {
            return "Nenhum registro corresponde a “\(evolutionSearchQuery)”. Limpe a busca ou tente outro termo."
        }
        switch evolutionFilter {
        case .all: return "Seu primeiro check-in vai aparecer aqui. Leva menos de 1 minuto."
        case .checkIns: return "Nenhum check-in registrado ainda."
        case .scales: return "Nenhuma escala (PHQ-9, GAD-7, YMRS) respondida ainda."
        case .alerts: return "Sem alertas pendentes — tudo tranquilo por aqui."
        }
    }

    var historyHasAnyVisibleContent: Bool {
        switch evolutionFilter {
        case .all:
            return !filteredCheckIns.isEmpty || !filteredAssessments.isEmpty || !filteredActiveAlerts.isEmpty
        case .checkIns: return !filteredCheckIns.isEmpty
        case .scales: return !filteredAssessments.isEmpty
        case .alerts: return !filteredActiveAlerts.isEmpty
        }
    }

    @ViewBuilder
    var historyCheckInsGroup: some View {
        if !filteredCheckIns.isEmpty {
            ForEach(filteredCheckIns.prefix(evolutionFilter == .checkIns ? 20 : 5)) { checkIn in
                CheckInRow(checkIn: checkIn)
            }
        }
    }

    @ViewBuilder
    var historyScalesGroup: some View {
        if !filteredAssessments.isEmpty {
            ForEach(filteredAssessments.prefix(evolutionFilter == .scales ? 20 : 4)) { assessment in
                AssessmentRow(assessment: assessment)
            }
        }
    }

    @ViewBuilder
    var historyAlertsGroup: some View {
        if !filteredActiveAlerts.isEmpty {
            ForEach(filteredActiveAlerts.prefix(evolutionFilter == .alerts ? 20 : 3)) { alert in
                AlertRow(
                    alert: alert,
                    markContacted: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .contacted,
                            contactStatus: .completed,
                            note: "Contato feito e registrado localmente."
                        )
                    },
                    markFalsePositive: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .falsePositive,
                            contactStatus: .falsePositive,
                            note: "Falso positivo documentado após revisão local."
                        )
                    },
                    escalate: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .escalated,
                            contactStatus: .pending,
                            note: "Escalonamento iniciado; acionar contato de segurança ou cuidado autorizado."
                        )
                    }
                )
            }
        }
    }

    var recentScalesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "list.clipboard", title: "Resultados recentes")

            if sortedAssessments.isEmpty {
                EmptyState(text: "Quando você responder PHQ-9, GAD-7 ou YMRS, a evolução das pontuações fica aqui.")
            } else {
                ForEach(sortedAssessments.prefix(6)) { assessment in
                    AssessmentRow(assessment: assessment)
                }
            }
        }
    }

    @ViewBuilder
    var alertsSection: some View {
        let immediateAlerts = activeAlerts.filter { $0.kind == ClinicalAlertKind.psychiatricEmergency.rawValue }
        let watchAlerts = activeAlerts.filter { $0.kind == ClinicalAlertKind.clinicalWatch.rawValue }

        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "bell.badge", title: "Alertas acionáveis")

            if immediateAlerts.isEmpty && watchAlerts.isEmpty {
                EmptyState(text: "Tudo tranquilo por aqui. Continue acompanhando — alertas aparecem quando algo merece atenção.")
            } else {
                if !immediateAlerts.isEmpty {
                    alertQueue(title: "Ação imediata", icon: "exclamationmark.octagon.fill", color: .red, alerts: immediateAlerts)
                }
                if !watchAlerts.isEmpty {
                    alertQueue(title: "Acompanhar", icon: "clock.badge.exclamationmark", color: .orange, alerts: watchAlerts)
                }
            }
        }
    }

    func alertQueue(title: String, icon: String, color: Color, alerts: [ClinicalAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            ForEach(alerts) { alert in
                AlertRow(
                    alert: alert,
                    markContacted: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .contacted,
                            contactStatus: .completed,
                            note: "Contato feito e registrado localmente."
                        )
                    },
                    markFalsePositive: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .falsePositive,
                            contactStatus: .falsePositive,
                            note: "Falso positivo documentado após revisão local."
                        )
                    },
                    escalate: {
                        updateLocalAlertWorkflow(
                            alert,
                            status: .escalated,
                            contactStatus: .pending,
                            note: "Escalonamento iniciado; acionar contato de segurança ou cuidado autorizado."
                        )
                    }
                )
            }
        }
    }

    var reportSection: some View {
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

                ShareLink(item: reportPreview) {
                    Label("Compartilhar relatório", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // P1-2: reportStatusMessage migrado para toast central.
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

    var canSaveClinicalData: Bool {
        patients.first?.consentAccepted == true
    }

    var hasCriticalPHQ9Answer: Bool {
        selectedScale == .phq9 && selectedScaleAnswers.indices.contains(8) && selectedScaleAnswers[8] > 0
    }

    var consentBinding: Binding<Bool> {
        Binding(
            get: { patients.first?.consentAccepted ?? false },
            set: { newValue in
                let patient = ensurePatient()
                patient.consentAccepted = newValue
                if !newValue {
                    patient.shareWithClinician = false
                }
            }
        )
    }

    var shareWithClinicianBinding: Binding<Bool> {
        Binding(
            get: { patients.first?.shareWithClinician ?? false },
            set: { newValue in
                let patient = ensurePatient()
                patient.shareWithClinician = newValue && patient.consentAccepted
            }
        )
    }

    // Sprint A: agora o setter pede confirmação antes de aplicar (toque
    // acidental no segmented picker antes trocava silenciosamente para perfil
    // médico e a TabView raiz sumia). A persistência passa por `saveContext()`
    // para mostrar erro quando SwiftData não conseguir gravar.
    var roleBinding: Binding<AccessRole> {
        Binding(
            get: { activeRole },
            set: { newValue in
                if newValue != activeRole {
                    roleChangePending = newValue
                }
            }
        )
    }

    func applyRoleChange(_ role: AccessRole) {
        let patient = ensurePatient()
        patient.activeRole = role.rawValue
        do { try modelContext.save() } catch { showToast("Erro ao salvar: \(error.localizedDescription)", level: .error) }
    }

    func prepareInitialData() {
        // Surface any store-recovery message produced during app init.
        if let msg = NeuremiaApp.storeRecoveryMessage {
            saveStatusMessage = msg
            NeuremiaApp.storeRecoveryMessage = nil
        }
        _ = ensurePatient()
        ensureAnswers(for: selectedScale)
        loadMedicationPlans()
        loadCustomSymptoms()
        loadOfflineSyncQueue()
        startNetworkMonitor()
        if autoBackupEnabled && backupURL == nil
            && FileManager.default.fileExists(atPath: BackupStore.protectedFileURL.path) {
            backupURL = BackupStore.protectedFileURL
        }
        runRecurringBackupIfNeeded()
        retryPendingSync()
        if loginEmail.isEmpty {
            loginEmail = authenticatedEmail
        }
    }

    func loadMedicationPlans() {
        guard !medicationPlansData.isEmpty, let data = medicationPlansData.data(using: .utf8) else {
            return
        }

        medicationPlans = (try? JSONDecoder().decode([MedicationPlanEntry].self, from: data)) ?? []
    }

    func persistMedicationPlans() {
        guard let data = try? JSONEncoder().encode(medicationPlans),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        medicationPlansData = json
    }

    func addMedicationPlan() {
        let trimmedName = medicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let entry = MedicationPlanEntry(
            name: trimmedName,
            dose: medicationDose.trimmingCharacters(in: .whitespacesAndNewlines),
            schedule: medicationSchedule.trimmingCharacters(in: .whitespacesAndNewlines),
            prescription: medicationPrescription.trimmingCharacters(in: .whitespacesAndNewlines),
            changeNote: medicationChangeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        medicationPlans.insert(entry, at: 0)
        persistMedicationPlans()
        medicationName = ""
        medicationDose = ""
        medicationSchedule = ""
        medicationPrescription = ""
        medicationChangeNote = ""
    }

    func removeMedicationPlan(_ entry: MedicationPlanEntry) {
        medicationPlans.removeAll { $0.id == entry.id }
        persistMedicationPlans()
    }

    func loadCustomSymptoms() {
        guard !customSymptomsData.isEmpty, let data = customSymptomsData.data(using: .utf8) else {
            return
        }

        customSymptoms = (try? JSONDecoder().decode([CustomSymptomEntry].self, from: data)) ?? []
    }

    func persistCustomSymptoms() {
        guard let data = try? JSONEncoder().encode(customSymptoms),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        customSymptomsData = json
    }

    func addCustomSymptom() {
        let trimmedName = customSymptomName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        customSymptoms.insert(CustomSymptomEntry(name: trimmedName, value: customSymptomValue), at: 0)
        persistCustomSymptoms()
        customSymptomName = ""
        customSymptomValue = 3
    }

    func removeCustomSymptom(_ entry: CustomSymptomEntry) {
        customSymptoms.removeAll { $0.id == entry.id }
        persistCustomSymptoms()
    }

    func startNetworkMonitor() {
        guard DataResidencyPolicy.remoteSyncEnabled else { return }
        networkMonitor.cancel()
        networkMonitor = NWPathMonitor()
        networkMonitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in retryPendingSync() }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    func loadOfflineSyncQueue() {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            offlineSyncQueue = []
            offlineSyncQueueData = ""
            lastSyncStatus = "Modo local ativo: dados apenas no aparelho."
            return
        }
        guard !offlineSyncQueueData.isEmpty, let data = offlineSyncQueueData.data(using: .utf8) else {
            return
        }

        offlineSyncQueue = (try? JSONDecoder().decode([OfflineSyncItem].self, from: data)) ?? []
    }

    func persistOfflineSyncQueue() {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            offlineSyncQueueData = ""
            return
        }
        guard let data = try? JSONEncoder().encode(offlineSyncQueue),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        offlineSyncQueueData = json
    }

    @discardableResult
    func ensurePatient() -> PatientProfile {
        if let patient = patients.first {
            return patient
        }

        let patient = PatientProfile()
        modelContext.insert(patient)
        return patient
    }

    func ensureAnswers(for scale: ScaleKind) {
        if scaleAnswers[scale]?.count != scale.questions.count {
            scaleAnswers[scale] = Array(repeating: 0, count: scale.questions.count)
        }
    }

    func answerBinding(for scale: ScaleKind, index: Int) -> Binding<Int> {
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

    // P1-2 (UX): ponto único de exibição de feedback ao usuário.
    // Substitui as 9+ variáveis de status espalhadas por chamadas a esta
    // função. Erros não fazem auto-dismiss; confirmações somem em 2 s;
    // avisos somem em 4 s.
    func showToast(_ message: String, level: ToastLevel = .success) {
        toastTask?.cancel()
        toastMessage = message
        toastLevel = level
        if let delay = level.autoDismissSeconds {
            toastTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled {
                    toastMessage = ""
                }
            }
        }
    }

    /// View que renderiza o toast sobre o conteúdo principal.
    @ViewBuilder
    var toastOverlay: some View {
        if !toastMessage.isEmpty {
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    Image(systemName: toastLevel.icon)
                        .foregroundStyle(.white)
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if toastLevel == .error {
                        Button {
                            toastMessage = ""
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.white.opacity(0.8))
                                .font(.caption.weight(.bold))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(toastLevel.color, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // acima da TabBar
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
            .zIndex(999)
            .accessibilityLabel(toastMessage)
        }
    }

    func markTodayRecommendationCompleted() {
        let recommendation = adjustedDailyRecommendation
        let todayKey = DailyCheckIn.dayKey(for: Date())
        let log = recommendationLogs.first { $0.dayKey == todayKey } ?? DailyRecommendationLog(
            recommendationId: recommendation.id,
            title: recommendation.title,
            action: recommendation.action,
            rationale: recommendation.rationale,
            targetSignal: recommendation.targetSignal,
            baselineMood: mood,
            baselineAnxiety: anxiety,
            baselineSleepHours: sleepHours
        )

        if log.patient == nil {
            log.patient = patients.first
        }
        log.recommendationId = recommendation.id
        log.title = recommendation.title
        log.action = recommendation.action
        log.rationale = recommendation.rationale
        log.targetSignal = recommendation.targetSignal
        log.completed = true
        log.completedAt = Date()

        if recommendationLogs.first(where: { $0.dayKey == todayKey }) == nil {
            modelContext.insert(log)
        }

        do {
            try modelContext.save()
            saveStatusMessage = "Recomendação marcada como feita. Vou medir o impacto nos próximos registros."
        } catch {
            saveStatusMessage = "Não foi possível marcar a recomendação."
        }
    }

    func recordTodayRecommendationExposure(_ recommendation: ClinicalDailyRecommendation, now: Date) {
        let todayKey = DailyCheckIn.dayKey(for: now)
        let log = recommendationLogs.first { $0.dayKey == todayKey } ?? DailyRecommendationLog(
            date: now,
            recommendationId: recommendation.id,
            title: recommendation.title,
            action: recommendation.action,
            rationale: recommendation.rationale,
            targetSignal: recommendation.targetSignal,
            baselineMood: mood,
            baselineAnxiety: anxiety,
            baselineSleepHours: sleepHours
        )

        if log.patient == nil {
            log.patient = patients.first
        }
        if !log.completed {
            log.recommendationId = recommendation.id
            log.title = recommendation.title
            log.action = recommendation.action
            log.rationale = recommendation.rationale
            log.targetSignal = recommendation.targetSignal
            log.baselineMood = mood
            log.baselineAnxiety = anxiety
            log.baselineSleepHours = sleepHours
        }

        if recommendationLogs.first(where: { $0.dayKey == todayKey }) == nil {
            modelContext.insert(log)
        }
    }

    @discardableResult
    func autoCompleteTodayRecommendationIfDetected(currentCheckIn: DailyCheckIn, now: Date) -> String? {
        let recommendation = adjustedDailyRecommendation
        let todayKey = DailyCheckIn.dayKey(for: now)
        guard let log = recommendationLogs.first(where: { $0.dayKey == todayKey }), !log.completed else {
            return nil
        }

        let detection = AutomaticInterventionDetector.detect(
            recommendation: recommendation,
            checkIn: currentCheckIn,
            steps: healthSteps
        )
        guard detection.didComplete else { return nil }

        log.completed = true
        log.completedAt = now
        return detection.evidence
    }

    @discardableResult
    func updateCompletedRecommendationImpacts(currentCheckIn: DailyCheckIn, now: Date) -> Int {
        let calendar = Calendar.current
        var updatedCount = 0
        for log in recommendationLogs where log.completed && log.impactSummary == nil {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: log.date), to: calendar.startOfDay(for: now)).day ?? 0
            guard (1...7).contains(days) else { continue }

            let impact = AdaptiveRecommendationEngine.impact(
                baselineMood: log.baselineMood,
                baselineAnxiety: log.baselineAnxiety,
                baselineSleepHours: log.baselineSleepHours,
                currentMood: currentCheckIn.mood,
                currentAnxiety: currentCheckIn.anxiety,
                currentSleepHours: currentCheckIn.sleepHours
            )
            log.impactMoodDelta = impact.moodDelta
            log.impactAnxietyDelta = impact.anxietyDelta
            log.impactSleepDelta = impact.sleepDelta
            log.impactSummary = impact.summary
            updatedCount += 1
        }
        return updatedCount
    }

    func saveDailyCheckIn() {
        // Sprint A (NEW-2): debounce contra double-tap. M5 colocou
        // @Attribute(.unique) dayKey em DailyCheckIn — duas execuções
        // simultâneas com mesmo dayKey quebram o SwiftData store no save.
        // O upsert abaixo verifica `checkIns.first(where:)`, mas as duas
        // execuções podem ler dayKey ausente, ambas inserir e estourar a
        // unique constraint no `try modelContext.save()`.
        guard !isSavingCheckIn else { return }
        isSavingCheckIn = true
        defer { isSavingCheckIn = false }

        saveStatusMessage = ""

        let now = Date()
        let todayKey = DailyCheckIn.dayKey(for: now)
        let automaticResults = automaticCheckupResults
        let isFirstCheckInOfDay = !checkIns.contains { $0.dayKey == todayKey }
        guard automaticResults.count == ScaleKind.allCases.count else {
            saveStatusMessage = "Não foi possível calcular todas as escalas automáticas. Revise as perguntas configuradas."
            return
        }

        let checkIn: DailyCheckIn
        if let existing = checkIns.first(where: { $0.dayKey == todayKey }) {
            // Upsert: overwrite today's record rather than creating a duplicate.
            checkIn = existing
        } else {
            checkIn = DailyCheckIn(
                mood: mood, anxiety: anxiety, energy: energy,
                irritability: irritability, sleepHours: sleepHours,
                appetite: appetite, libido: libido,
                medicationTaken: isMedicationFullyTaken,
                sideEffects: sideEffects, automaticThoughts: automaticThoughts,
                suicidalIdeation: hasCriticalSafetyRisk,
                journalEntry: journalEntryWithContext
            )
            modelContext.insert(checkIn)
        }
        checkIn.date = now
        checkIn.mood = mood
        checkIn.anxiety = anxiety
        checkIn.energy = energy
        checkIn.irritability = irritability
        checkIn.sleepHours = sleepHours
        checkIn.appetite = appetite
        checkIn.libido = libido
        checkIn.medicationTaken = isMedicationFullyTaken
        checkIn.sideEffects = sideEffects
        checkIn.automaticThoughts = automaticThoughts
        checkIn.suicidalIdeation = hasCriticalSafetyRisk
        checkIn.journalEntry = journalEntryWithContext
        let measuredRecommendationImpactCount = updateCompletedRecommendationImpacts(currentCheckIn: checkIn, now: now)
        recordTodayRecommendationExposure(adjustedDailyRecommendation, now: now)
        let autoCompletedRecommendationEvidence = autoCompleteTodayRecommendationIfDetected(currentCheckIn: checkIn, now: now)
        let backendPayload = BackendDailyCheckInPayload(
            mood: mood,
            anxiety: anxiety,
            energy: energy,
            irritability: irritability,
            sleepHours: sleepHours,
            appetite: appetite,
            libido: libido,
            medicationTaken: isMedicationFullyTaken,
            sideEffects: sideEffects,
            automaticThoughts: automaticThoughts,
            suicidalIdeation: hasCriticalSafetyRisk,
            journalEntry: journalEntryWithContext
        )

        let textAssessment = hasCriticalSafetyRisk
            ? TextRiskAssessment(level: .high, detectedTerms: ["triagem positiva"], explanation: "A triagem estruturada marcou ideação suicida.")
            : ClinicalAnalysis.textAssessment(for: "\(journalEntryWithContext) \(automaticThoughts)")
        if textAssessment.level != .low || mood <= 2 || anxiety >= 3.5 || !isMedicationFullyTaken {
            let alertLevel: ClinicalRiskLevel = textAssessment.level == .low ? .moderate : textAssessment.level
            let isEmergency = hasCriticalSafetyRisk || mood <= 1
            let alertKind: ClinicalAlertKind = isEmergency ? .psychiatricEmergency : .clinicalWatch
            let alreadyHasTodayAlert = alerts.contains { alert in
                alert.kind == alertKind.rawValue
                    && alert.title == alertLevel.alertTitle
                    && Calendar.current.isDate(alert.date, inSameDayAs: now)
            }
            if !alreadyHasTodayAlert {
                modelContext.insert(ClinicalAlert(
                    level: alertLevel,
                    kind: alertKind,
                    escalationTarget: isEmergency ? .clinicianCaregiverNow : .clinicianDigest,
                    title: alertLevel.alertTitle,
                    message: "\(textAssessment.explanation) \(textAssessment.recommendation)"
                ))
            }
        }

        upsertAutomaticCheckups(results: automaticResults, date: now)

        // Sprint A — fluxo de crise (NEW-1): capturar AGORA os flags que
        // dependem do estado pré-reset. Antes:
        //   1. `journalEntry = ""` rodava em (linha do reset), aí logo abaixo
        //      `if journalEntry.trim.isEmpty` era SEMPRE true → postSaveSheet
        //      disparava sempre, inclusive em crise.
        //   2. `safetyStatus = .safe` resetava antes do paciente ver feedback
        //      de que a equipe foi acionada — `CrisisSupportCard` sumia.
        let wasUrgent = (safetyStatus == .urgent) || hasCriticalSafetyRisk
        let hadEmptyJournal = journalEntry
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        do {
            try modelContext.save()

            // Award XP for check-in completion
            gamificationManager.registerSavedCheckIn(checkIn)
            let hasDetails = !sideEffects.isEmpty || !automaticThoughts.isEmpty
            let hasJournal = !journalEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isFirstCheckInOfDay {
                gamificationManager.awardCheckInXP(isFirstOfDay: true, hasDetails: hasDetails, hasJournal: hasJournal)
                gamificationManager.checkAndAwardBadges()
            }

            sideEffects = ""
            automaticThoughts = ""
            journalEntry = ""
            alcoholTrigger = false
            poorSleepTrigger = false
            stressTrigger = false
            conflictTrigger = false
            routineChangeTrigger = false
            menstrualTrigger = false
            customTriggers = []
            // Em crise: NÃO resetar safetyStatus (mantém CrisisSupportCard
            // visível) e dar feedback explícito de que a equipe foi alertada.
            if wasUrgent {
                saveStatusMessage = "Registro salvo e equipe de cuidado alertada. Continue acompanhando o plano de segurança abaixo."
            } else {
                safetyStatus = .safe
                if measuredRecommendationImpactCount > 0 {
                    saveStatusMessage = "Registro salvo. Também medi o impacto da recomendação anterior para ajustar as próximas."
                } else if let autoCompletedRecommendationEvidence {
                    saveStatusMessage = "Registro salvo. Detectei automaticamente a recomendação de hoje: \(autoCompletedRecommendationEvidence)."
                } else {
                    saveStatusMessage = "Registro diário salvo no histórico."
                }
            }
            hasSeenMoodCoachmark = true
            // Sprint 23 + Sprint A: só dispara o sheet de "anotação leve" se
            // o paciente NÃO estava em crise (essa UI seria deslocada) e se o
            // journal estava vazio ANTES do reset desta sessão de save.
            if !wasUrgent && hadEmptyJournal {
                postSaveThought = ""
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    isShowingPostSavePrompt = true
                }
            }
            syncCheckInWithBackend(backendPayload)
            if wasUrgent || textAssessment.level == .high {
                Task { await dispatchCriticalSafetyAlert(textAssessment: textAssessment) }
            }
            if autoBackupEnabled {
                makeBackupExport(silent: true)
            }
            if autoMonthlyReportEnabled {
                prepareReportPreviewOnly()
                reportStatusMessage = "Relatório mensal atualizado."
                if autoCareTeamSendEnabled {
                    sendCurrentReportToCareTeam()
                }
            }
            for result in automaticResults {
                syncAssessmentWithBackend(
                    scaleName: result.scale.rawValue,
                    answers: result.answers,
                    score: result.score,
                    interpretation: result.interpretation
                )
            }
        } catch {
            saveStatusMessage = "Não foi possível salvar o registro."
        }
    }

    @MainActor
    func saveDailyCheckInAfterHealthSync() async {
        await syncContinuousHealthKitIfNeeded(force: true)
        saveDailyCheckIn()
    }

    func saveAutomaticCheckups() {
        scaleStatusMessage = ""
        let results = automaticCheckupResults
        guard results.count == ScaleKind.allCases.count else {
            scaleStatusMessage = "Não foi possível calcular todas as escalas automáticas."
            return
        }

        let savedAssessments = upsertAutomaticCheckups(results: results, date: Date())

        do {
            try modelContext.save()
            savedAssessments.forEach { gamificationManager.registerSavedAssessment($0) }

            // Award XP for scale completion
            let isFirstScale = assessments.isEmpty
            gamificationManager.awardScaleXP(isFirstScale: isFirstScale)
            gamificationManager.checkAndAwardBadges()

            scaleStatusMessage = "Check-up automático salvo com base no diário de hoje."
            for result in results {
                syncAssessmentWithBackend(
                    scaleName: result.scale.rawValue,
                    answers: result.answers,
                    score: result.score,
                    interpretation: result.interpretation
                )
            }
        } catch {
            scaleStatusMessage = "Não foi possível salvar o check-up automático."
        }
    }

    @discardableResult
    func upsertAutomaticCheckups(results: [AutomaticScaleResult], date: Date) -> [ScaleAssessment] {
        var savedAssessments: [ScaleAssessment] = []

        for result in results {
            let assessment = assessments.first { assessment in
                assessment.scaleName == result.scale.rawValue
                    && Calendar.current.isDate(assessment.date, inSameDayAs: date)
            } ?? ScaleAssessment(
                scaleName: result.scale.rawValue,
                date: date,
                answers: result.answers,
                score: result.score,
                interpretation: result.interpretation
            )

            assessment.date = date
            assessment.answers = result.answers
            assessment.score = result.score
            assessment.interpretation = result.interpretation

            if assessment.modelContext == nil {
                modelContext.insert(assessment)
            }
            savedAssessments.append(assessment)

            if result.scale == .phq9 && result.answers.indices.contains(8) && result.answers[8] > 0 {
                modelContext.insert(ClinicalAlert(
                    level: .high,
                    kind: .psychiatricEmergency,
                    escalationTarget: .clinicianCaregiverNow,
                    title: "Check-up automático com item crítico",
                    message: "Sinal de segurança alto. Revisar plano de apoio e contato profissional."
                ))
            } else if scoreRequiresAlert(scale: result.scale, score: result.score) {
                let kind: ClinicalAlertKind = result.scale == .ymrs && result.score >= 22 ? .psychiatricEmergency : .clinicalWatch
                modelContext.insert(ClinicalAlert(
                    level: kind == .psychiatricEmergency ? .high : .moderate,
                    kind: kind,
                    escalationTarget: kind == .psychiatricEmergency ? .clinicianCaregiverNow : .clinicianDigest,
                    title: "Check-up automático alterado",
                    message: "\(result.scale.rawValue): \(result.score) pontos, interpretação \(result.interpretation)."
                ))
            }
        }

        return savedAssessments
    }

    func automaticCheckupResult(for scale: ScaleKind) -> AutomaticScaleResult? {
        guard let answers = validatedAutomaticAnswers(for: scale) else { return nil }
        let score = ClinicalAnalysis.score(for: scale, answers: answers)
        return AutomaticScaleResult(
            scale: scale,
            answers: answers,
            score: score,
            interpretation: ClinicalAnalysis.interpretation(for: scale, score: score)
        )
    }

    func validatedAutomaticAnswers(for scale: ScaleKind) -> [Int]? {
        let answers = automaticAnswers(for: scale)
        guard answers.count == scale.questions.count else { return nil }

        return answers.enumerated().map { index, answer in
            clamped(answer, range: scale.answerRange(for: index))
        }
    }

    func automaticAnswers(for scale: ScaleKind) -> [Int] {
        switch scale {
        case .phq9:
            // Item 9 = "Pensamentos de que seria melhor estar morto ou de se
            // machucar de alguma forma." (PHQ-9, Kroenke 2001).
            // Use max(safetySeverity, textSeverity): the safety toggle covers
            // explicit user disclosure; textSeverity catches written terms
            // ("quero morrer", "sem saida") even when the toggle is not set.
            // Without this, a patient writing high-risk text but not touching
            // the safety control would produce item 9 = 0 — clinical underdetection.
            let phq9Answers = scaleAnswers[.phq9] ?? []
            let explicitItem9 = phq9Answers.indices.contains(8) ? phq9Answers[8] : 0
            let item9 = max(safetySeverity, textSeverity, explicitItem9)
            return [
                lowMoodSeverity,
                max(lowMoodSeverity, textSeverity),
                sleepSeverity,
                lowEnergySeverity,
                appetiteSeverity,
                textSeverity,
                automaticThoughts.isEmpty ? 0 : max(1, anxietySeverity - 1),
                max(lowEnergySeverity, irritabilitySeverity),
                item9
            ]
        case .gad7:
            return [
                anxietySeverity,
                automaticThoughts.isEmpty ? max(0, anxietySeverity - 1) : max(1, anxietySeverity),
                max(anxietySeverity, stressTrigger ? 2 : 0),
                max(anxietySeverity - 1, sleepSeverity),
                max(irritabilitySeverity, energy >= 4 ? 1 : 0),
                irritabilitySeverity,
                max(textSeverity, safetyStatus == .attention ? 1 : 0)
            ].map { clamped($0, range: 0...3) }
        case .ymrs:
            return [
                mood >= 4 ? Int(mood - 3) : 0,
                energy >= 4 ? Int(energy - 2) : 0,
                libido >= 4 ? Int(libido - 3) : 0,
                sleepHours < 5 ? 4 : sleepHours < 6 ? 3 : sleepHours < 7 ? 1 : 0,
                clamped(irritabilitySeverity * 2, range: 0...8),
                energy >= 5 ? 4 : energy >= 4 ? 2 : 0,
                automaticThoughts.count > 120 ? 3 : automaticThoughts.isEmpty ? 0 : 1,
                clamped(max(textSeverity, safetySeverity) * 2, range: 0...8),
                clamped(irritabilitySeverity * 2, range: 0...8),
                0,
                safetyStatus == .urgent ? 2 : safetyStatus == .attention ? 1 : 0
            ]
        }
    }

    var lowMoodSeverity: Int {
        clamped(Int(((5 - mood) / 4 * 3).rounded()), range: 0...3)
    }

    var anxietySeverity: Int {
        clamped(Int(((anxiety - 1) / 4 * 3).rounded()), range: 0...3)
    }

    var lowEnergySeverity: Int {
        clamped(Int(((5 - energy) / 4 * 3).rounded()), range: 0...3)
    }

    var irritabilitySeverity: Int {
        clamped(Int(((irritability - 1) / 4 * 3).rounded()), range: 0...3)
    }

    var sleepSeverity: Int {
        if sleepHours < 5 { return 3 }
        if sleepHours < 6 { return 2 }
        if sleepHours < 7 || sleepHours > 9 { return 1 }
        return 0
    }

    var appetiteSeverity: Int {
        let distance = abs(appetite - 3)
        if distance >= 2 { return 3 }
        if distance >= 1 { return 1 }
        return 0
    }

    var safetySeverity: Int {
        switch safetyStatus {
        case .safe:
            0
        case .attention:
            1
        case .urgent:
            3
        }
    }

    var textSeverity: Int {
        switch currentTextAssessment.level {
        case .low:
            0
        case .moderate:
            2
        case .high:
            3
        }
    }

    func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func saveScaleAssessment() {
        scaleStatusMessage = ""
        ensureAnswers(for: selectedScale)
        let answers = scaleAnswers[selectedScale] ?? []
        let score = ClinicalAnalysis.score(for: selectedScale, answers: answers)
        let interpretation = ClinicalAnalysis.interpretation(for: selectedScale, score: score)
        let assessment = ScaleAssessment(scaleName: selectedScale.rawValue, answers: answers, score: score, interpretation: interpretation)
        modelContext.insert(assessment)

        if selectedScale == .phq9 && answers.indices.contains(8) && answers[8] > 0 {
            modelContext.insert(ClinicalAlert(
                level: .high,
                kind: .psychiatricEmergency,
                escalationTarget: .clinicianCaregiverNow,
                title: "PHQ-9 com item crítico",
                message: "Item 9 positivo. Revisar risco suicida e plano de segurança imediatamente."
            ))
        } else if scoreRequiresAlert(scale: selectedScale, score: score) {
            let kind: ClinicalAlertKind = selectedScale == .ymrs && score >= 22 ? .psychiatricEmergency : .clinicalWatch
            modelContext.insert(ClinicalAlert(
                level: kind == .psychiatricEmergency ? .high : .moderate,
                kind: kind,
                escalationTarget: kind == .psychiatricEmergency ? .clinicianCaregiverNow : .clinicianDigest,
                title: "Escala alterada",
                message: "\(selectedScale.rawValue): \(score) pontos, interpretação \(interpretation)."
            ))
        }

        do {
            try modelContext.save()
            gamificationManager.registerSavedAssessment(assessment)
            scaleAnswers[selectedScale] = Array(repeating: 0, count: selectedScale.questions.count)
            scaleStatusMessage = "\(selectedScale.rawValue) salvo: \(score) pontos, \(interpretation)."
            syncAssessmentWithBackend(scaleName: selectedScale.rawValue, answers: answers, score: score, interpretation: interpretation)
        } catch {
            scaleStatusMessage = "Não foi possível salvar \(selectedScale.rawValue)."
        }
    }

    func scoreRequiresAlert(scale: ScaleKind, score: Int) -> Bool {
        switch scale {
        case .phq9:
            score >= 10
        case .gad7:
            score >= 10
        case .ymrs:
            score >= 13
        }
    }

    func updateTypingSignals(text: String) {
        // B2 — debounce: cancel any pending update and reschedule 100 ms later.
        // This fires at most once per 100 ms regardless of how fast the user types,
        // preventing unnecessary @State mutations on every keystroke.
        _typingDebounceTask?.cancel()
        _typingDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return  // task was cancelled — a newer keystroke is in flight
            }
            bodySignalInteractionCount += 1
            if typingStartedAt == nil && !text.isEmpty {
                typingStartedAt = Date()
                bodySignalTypingLatency = Date().timeIntervalSince(appSessionStartedAt)
            }
            guard let typingStartedAt else { return }
            let elapsedMinutes = max(Date().timeIntervalSince(typingStartedAt) / 60, 0.05)
            bodySignalTypingSpeed = Double(text.count) / elapsedMinutes
        }
    }

    func generateReport() {
        let text = ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments)
        reportPreview = text
        reportCSVURL = makeCSVReport()

        let coveredCheckIns = sortedCheckIns.prefix(14)
        modelContext.insert(ClinicalReport(
            summary: text,
            riskLevel: summary.riskLevel,
            clinicianName: patients.first?.clinicianName ?? "",
            periodStart: coveredCheckIns.last?.date ?? Date(),
            periodEnd: coveredCheckIns.first?.date ?? Date(),
            scalesIncluded: Array(Set(sortedAssessments.prefix(10).map(\.scaleName))).sorted(),
            algorithmVersion: "2.0"
        ))
        reportStatusMessage = ""

        do {
            try modelContext.save()
            syncReportWithBackend(summary: text, riskLevel: summary.riskLevel.rawValue)
            if autoCareTeamSendEnabled {
                sendCurrentReportToCareTeam()
            }
        } catch {
            reportStatusMessage = "Relatório gerado, mas não foi possível salvar localmente."
        }

        // B1 — PDF rendering is CPU-intensive; run off the main actor so the
        // UI stays responsive while the page layout and Core Graphics calls execute.
        let checkInsSnapshot = Array(sortedCheckIns)
        let assessmentsSnapshot = Array(sortedAssessments)
        let medicationSnapshot = medicationPlans
        let symptomsSnapshot = customSymptoms
        let summarySnapshot = summary
        Task.detached(priority: .userInitiated) {
            let url = await PDFReportRenderer.render(
                text: text,
                checkIns: checkInsSnapshot,
                assessments: assessmentsSnapshot,
                medications: medicationSnapshot,
                symptoms: symptomsSnapshot,
                summary: summarySnapshot
            )
            await MainActor.run { self.reportPDFURL = url }
        }
    }

    func prepareReportPreviewOnly() {
        let text = ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments)
        reportPreview = text
        reportCSVURL = makeCSVReport()

        let checkInsSnapshot = Array(sortedCheckIns)
        let assessmentsSnapshot = Array(sortedAssessments)
        let medicationSnapshot = medicationPlans
        let symptomsSnapshot = customSymptoms
        let summarySnapshot = summary
        Task.detached(priority: .userInitiated) {
            let url = await PDFReportRenderer.render(
                text: text,
                checkIns: checkInsSnapshot,
                assessments: assessmentsSnapshot,
                medications: medicationSnapshot,
                symptoms: symptomsSnapshot,
                summary: summarySnapshot
            )
            await MainActor.run { self.reportPDFURL = url }
        }
    }

    /// Encrypt a PHI string field for the backup JSON.
    /// Returns the base-64 AES-GCM ciphertext, or an empty string on failure
    /// (never falls back to plaintext — dropping is safer).
    func encryptField(_ value: String) -> String {
        DraftStore.encryptString(value) ?? ""
    }

    func updateLocalAlertWorkflow(
        _ alert: ClinicalAlert,
        status: ClinicalAlertWorkflowStatus,
        contactStatus: ClinicalAlertContactStatus,
        note: String
    ) {
        let now = Date()
        alert.workflowStatus = status.rawValue
        alert.contactStatus = contactStatus.rawValue
        alert.workflowNote = note
        alert.acknowledgedAt = now

        switch status {
        case .contacted, .falsePositive, .resolved:
            alert.acknowledged = true
            alert.resolvedAt = now
        case .escalated:
            alert.acknowledged = false
            alert.escalatedAt = now
        case .open:
            alert.acknowledged = false
        }

        do {
            try modelContext.save()
        } catch {
            showToast("Erro ao salvar alerta: \(error.localizedDescription)", level: .error)
        }
    }

}
