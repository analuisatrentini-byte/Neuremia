//
//  ContentView+ClinicianPatients.swift
//  Neuremia
//

import SwiftUI
import Charts

extension ContentView {
    var clinicianSentInvitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "envelope.badge", title: "Convites enviados")

            // Sprint 24: filtro por status — agrupa por categoria em vez de
            // misturar pending+accepted+revoked tudo junto.
            if !clinicianSentInvites.isEmpty {
                Picker("Status", selection: $sentInvitesFilter) {
                    ForEach(SentInviteStatusFilter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            if clinicianSentInvites.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para acompanhar seus convites." : "Quando você convidar um paciente, o status do convite aparece aqui.")
            } else if filteredSentInvites.isEmpty {
                EmptyState(text: "Nenhum convite \(sentInvitesFilter.rawValue.lowercased()).")
            } else {
                ForEach(filteredSentInvites) { invite in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: inviteStatusIcon(invite.status))
                            .foregroundStyle(inviteStatusColor(invite.status))
                            .frame(width: 28, height: 28)
                            .accessibilityLabel(inviteStatusLabel(invite.status))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(invite.patientFullName.isEmpty ? invite.patientEmail : invite.patientFullName)
                                .font(.subheadline.weight(.semibold))
                            Text(invite.patientEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(inviteStatusLabel(invite.status))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(inviteStatusColor(invite.status))
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                Task { await loadClinicianSentInvites() }
            } label: {
                HStack {
                    if isLoadingClinicianSentInvites {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isLoadingClinicianSentInvites ? "Atualizando..." : "Atualizar status dos convites")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty || isLoadingClinicianSentInvites)

            if !clinicianSentInvitesFlash.isEmpty {
                Label(clinicianSentInvitesFlash, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .panelStyle()
        // Borda lateral amarela — "convites enviados, aguardando paciente"
        // (Sprint 21). Distingue do card de pacientes vinculados (verde).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.yellow)
                .frame(width: 4)
                .padding(.vertical, 2)
        }
    }

    func inviteStatusIcon(_ status: String) -> String {
        switch status {
        case "accepted":
            "checkmark.circle.fill"
        case "revoked":
            "xmark.octagon.fill"
        default:
            "hourglass"
        }
    }

    func inviteStatusColor(_ status: String) -> Color {
        switch status {
        case "accepted":
            .green
        case "revoked":
            .red
        default:
            .orange
        }
    }

    func inviteStatusLabel(_ status: String) -> String {
        switch status {
        case "accepted":
            "Paciente aceitou"
        case "revoked":
            "Paciente recusou"
        case "pending":
            "Aguardando aceite"
        default:
            status.capitalized
        }
    }

    var clinicianPatientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(icon: "person.2", title: "Pacientes vinculados")

            HStack(spacing: 8) {
                TextField("E-mail do paciente", text: $patientLinkEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    Task {
                        await linkPatientAndReload()
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(authToken.isEmpty || patientLinkEmail.isEmpty)
            }

            Button {
                Task {
                    await loadClinicianPatients()
                }
            } label: {
                Label("Atualizar lista", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(authToken.isEmpty)

            // P1-2: status migrado para toast central.

            if clinicianPatients.isEmpty {
                EmptyState(text: authToken.isEmpty ? "Entre na conta para buscar pacientes." : "Quando um paciente aceitar seu convite, ele aparece aqui.")
            } else {
                // Sprint 24: Picker semântico para filtrar/ordenar a lista
                // de pacientes vinculados. Médico com muitos pacientes não
                // precisa mais rolar para encontrar alto risco.
                Picker("Filtrar", selection: $clinicianPatientFilter) {
                    ForEach(ClinicianPatientFilter.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                // M5 (UX-P0): NavigationLink(value:) empurra o detalhe como
                // push em vez de expandir inline — elimina o scroll infinito.
                ForEach(filteredClinicianPatients, id: \.id) { patient in
                    NavigationLink(value: patient) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(patient.fullName)
                                    .font(.headline)
                                Text(patient.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let riskScore = patient.riskScore {
                                    Text("Risco \(riskScore)/100\(patient.riskLevel.map { " · \($0)" } ?? "")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(riskScore >= 66 ? .red : riskScore >= 34 ? .orange : .green)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            if !remotePatientStatusMessage.isEmpty {
                Text(remotePatientStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // M5 (UX-P0): detalhe do paciente removido daqui — agora é push
            // navigation via NavigationLink(value:) em clinicianPatientsTab.
        }
        .panelStyle()
    }

    /// Detalhe do paciente remoto com sub-tabs (Sprint 24).
    /// Substitui o scroll vertical único pela navegação por seções clínicas.
    @ViewBuilder
    func remotePatientDetail(for patient: BackendUser) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    selectedRemotePatient = nil
                    remoteCheckIns = []
                    remoteAssessments = []
                    remoteAlerts = []
                    remoteReports = []
                } label: {
                    Label("Voltar à lista", systemImage: "chevron.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(patient.fullName)
                        .font(.subheadline.weight(.bold))
                    Text(patient.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Seção", selection: $remotePatientSubTab) {
                ForEach(RemotePatientSubTab.allCases) { tab in
                    Image(systemName: tab.icon)
                        .tag(tab)
                        .accessibilityLabel(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)

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
            .animation(.easeInOut(duration: 0.18), value: remotePatientSubTab)
        }
    }

    var remotePatientSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    Circle().fill(Color.secondary.opacity(0.18)).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.18))
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 60)
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Carregando dados do paciente")
    }

    @ViewBuilder
    var remotePatientCheckInsList: some View {
        if remoteCheckIns.isEmpty {
            EmptyState(text: "Sem check-ins recentes.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteCheckIns) { checkIn in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkIn.createdAt.prefix(10))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 14) {
                            Text("Humor \(Int(checkIn.mood))")
                            Text("Ansiedade \(Int(checkIn.anxiety))")
                            Text("Sono \(checkIn.sleepHours, specifier: "%.1f")h")
                        }
                        .font(.caption2)
                        if !checkIn.journalEntry.isEmpty {
                            Text(checkIn.journalEntry)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    var remotePatientAssessmentsList: some View {
        if remoteAssessments.isEmpty {
            EmptyState(text: "Sem escalas aplicadas.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteAssessments) { assessment in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assessment.scaleName)
                                .font(.subheadline.weight(.semibold))
                            Text(assessment.interpretation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(assessment.score) pts")
                            .font(.headline)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    var remotePatientAlertsList: some View {
        let immediateAlerts = remoteAlerts.filter { $0.alertType == ClinicalAlertKind.psychiatricEmergency.rawValue }
        let watchAlerts = remoteAlerts.filter { $0.alertType == ClinicalAlertKind.clinicalWatch.rawValue }

        if immediateAlerts.isEmpty && watchAlerts.isEmpty {
            EmptyState(text: "Sem alertas registrados.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !clinicalWorkflowStatusMessage.isEmpty {
                    Text(clinicalWorkflowStatusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !immediateAlerts.isEmpty {
                    remoteAlertQueue(title: "Ação imediata", icon: "exclamationmark.octagon.fill", color: .red, alerts: immediateAlerts)
                }
                if !watchAlerts.isEmpty {
                    remoteAlertQueue(title: "Acompanhar", icon: "clock.badge.exclamationmark", color: .orange, alerts: watchAlerts)
                }
            }
        }
    }

    func remoteAlertQueue(title: String, icon: String, color: Color, alerts: [BackendClinicalAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.acknowledged ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(alert.level == "high" ? .red : alert.acknowledged ? .green : .orange)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.title)
                            .font(.subheadline.weight(.semibold))
                        Text(alert.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if alert.escalationTarget == ClinicalEscalationTarget.clinicianDigest.rawValue {
                            Text("Digest clínico")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                        }
                        if let workflowStatus = alert.workflowStatus {
                            Text(workflowLine(for: alert, workflowStatus: workflowStatus))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let auditSummary = alert.auditSummary {
                            Label(auditSummary, systemImage: "lock.doc")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        RemoteAlertProtocolCard(alert: alert)
                        HStack(spacing: 8) {
                            Button("Contato feito") {
                                Task { await updateRemoteAlertWorkflow(alert, status: "contacted", contactStatus: "completed") }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Snooze 24h") {
                                Task { await updateRemoteAlertWorkflow(alert, status: "snoozed", snoozedDays: 1) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Falso positivo") {
                                Task { await updateRemoteAlertWorkflow(alert, status: "resolved", contactStatus: "false_positive", resolutionNote: "Marcado como falso positivo no dashboard clínico iOS após revisão.") }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Escalar agora") {
                                Task { await updateRemoteAlertWorkflow(alert, status: "escalated", contactStatus: "pending", resolutionNote: "Escalonado no dashboard clínico iOS para contato imediato.") }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)

                            Button("Resolver") {
                                Task { await updateRemoteAlertWorkflow(alert, status: "resolved", contactStatus: alert.contactStatus, resolutionNote: "Resolvido no dashboard clínico iOS.") }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.green)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    func workflowLine(for alert: BackendClinicalAlert, workflowStatus: String) -> String {
        [
            "Workflow: \(workflowStatus)",
            alert.contactStatus.map { "contato \($0)" },
            alert.assignedClinicianName.map { "com \($0)" },
            alert.snoozedUntil.map { "snooze até \($0.prefix(10))" },
            alert.resolvedAt.map { "resolvido em \($0.prefix(10))" }
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    @ViewBuilder
    var remotePatientReportsList: some View {
        if remoteReports.isEmpty {
            EmptyState(text: "Sem relatórios gerados.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(remoteReports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(report.createdAt.prefix(10))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(report.riskLevel.capitalized)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(report.riskLevel == "high" ? .red : report.riskLevel == "moderate" ? .orange : .green)
                        }
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    /// Settings nativo (Sprint 21) — Form com Sections + NavigationLinks.
    /// Cada item antes empilhado vira uma sub-tela navegável. Reduz 13 cards
    /// num scroll a 6 grupos hierárquicos no padrão iOS.

}

private struct RemoteAlertProtocolCard: View {
    let alert: BackendClinicalAlert

    private var protocolSummary: ClinicalAlertProtocol {
        ClinicalAlertProtocol.remote(
            kind: ClinicalAlertKind(rawValue: alert.alertType) ?? .psychiatricEmergency,
            escalationTarget: ClinicalEscalationTarget(rawValue: alert.escalationTarget) ?? .clinicianCaregiverNow
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Protocolo operacional", systemImage: "checklist.checked")
                .font(.caption2.weight(.bold))
                .foregroundStyle(alert.level == "high" ? .red : .orange)
            protocolLine("person.2.fill", protocolSummary.recipients)
            protocolLine("clock.badge.exclamationmark", protocolSummary.responseWindow)
            protocolLine("checkmark.seal", protocolSummary.acknowledgement)
            protocolLine("arrow.up.right.circle", protocolSummary.escalation)
            protocolLine("exclamationmark.triangle", protocolSummary.falsePositiveHandling)
            protocolLine("doc.text.magnifyingglass", protocolSummary.legalLimit)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((alert.level == "high" ? Color.red : Color.orange).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func protocolLine(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
