//
//  BackupView.swift
//  Neuremia
//

import SwiftUI
import SwiftData
import HealthKit
import UIKit
import UserNotifications

extension ContentView {
    func makeBackupExport(silent: Bool = false) {
        // NeuremiaBackupSnapshot (Codable) is the canonical export/import format.
        // N-C1: PHI text fields are AES-GCM encrypted before serialisation.
        //       Email is omitted — not required to restore clinical records.
        let snapshot = NeuremiaBackupSnapshot(
            profile: .init(role: activeRole.rawValue, careFocus: selectedCareFocus.rawValue),
            medicationPlan: .init(
                name: medicationName, dose: medicationDose, schedule: medicationSchedule,
                prescriptionEnc: encryptField(medicationPrescription),
                changeNoteEnc: encryptField(medicationChangeNote)
            ),
            medicationPlans: medicationPlans,
            customSymptoms: customSymptoms,
            safetyPlan: .init(
                contactEnc: encryptField(safetyContact),
                warningSignsEnc: encryptField(safetyWarningSigns),
                strategiesEnc: encryptField(safetyStrategies)
            ),
            offlineQueue: DataResidencyPolicy.remoteSyncEnabled ? offlineSyncQueue : [],
            checkIns: sortedCheckIns.map { c in
                DailyCheckInSnapshot(
                    date: c.date, dayKey: c.dayKey,
                    mood: c.mood, anxiety: c.anxiety, energy: c.energy,
                    irritability: c.irritability, sleepHours: c.sleepHours,
                    appetite: c.appetite, libido: c.libido,
                    medicationTaken: c.medicationTaken, suicidalIdeation: c.suicidalIdeation,
                    sideEffectsEnc: encryptField(c.sideEffects),
                    automaticThoughtsEnc: encryptField(c.automaticThoughts),
                    journalEntryEnc: encryptField(c.journalEntry)
                )
            },
            assessments: sortedAssessments.map { a in
                ScaleAssessmentSnapshot(date: a.date, scaleName: a.scaleName,
                                        answers: a.answers, score: a.score,
                                        interpretation: a.interpretation)
            }
        )

        do {
            let data = try snapshot.encodedData()
            var url = BackupStore.protectedFileURL
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            do {
                try url.setResourceValues(resourceValues)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            backupURL = url
            lastAutomaticBackupAt = Date().timeIntervalSince1970
            if !silent { loginStatusMessage = "Backup local gerado. Use Compartilhar backup para guardar uma cópia fora deste aparelho." }
        } catch {
            if !silent { loginStatusMessage = "Não foi possível gerar backup." }
        }
    }

    func runRecurringBackupIfNeeded() {
        guard autoBackupEnabled else { return }
        guard !checkIns.isEmpty || !assessments.isEmpty || !medicationPlans.isEmpty || !customSymptoms.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        let interval = TimeInterval(max(1, backupIntervalDays) * 86_400)
        if lastAutomaticBackupAt == 0 || now - lastAutomaticBackupAt >= interval {
            makeBackupExport(silent: true)
        }
    }

    func sendCurrentReportToCareTeam() {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            careTeamSendStatus = "Modo local ativo: relatório mantido apenas no aparelho."
            return
        }
        guard autoCareTeamSendEnabled else { return }
        guard patients.first?.consentAccepted == true,
              (patients.first?.shareWithClinician == true || shareWithCaregiver) else {
            careTeamSendStatus = "Ative consentimento e autorização para médico ou cuidador."
            return
        }

        let text = reportPreview.isEmpty ? ClinicalAnalysis.reportText(checkIns: sortedCheckIns, assessments: sortedAssessments) : reportPreview
        guard !text.isEmpty else {
            careTeamSendStatus = "Sem relatório para enviar."
            return
        }

        syncReportWithBackend(summary: text, riskLevel: summary.riskLevel.rawValue, automaticCareTeamSend: true)
    }

    @MainActor
    func saveCaregiverContact() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            careTeamSendStatus = "Modo local ativo: cuidador não cadastrado no backend."
            return
        }
        guard !authToken.isEmpty else {
            careTeamSendStatus = "Entre na conta para cadastrar cuidador no backend."
            return
        }
        guard shareWithCaregiver else {
            careTeamSendStatus = "Ative autorização para cuidador antes de cadastrar."
            return
        }
        let trimmedContact = careTeamContact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContact.isEmpty else {
            careTeamSendStatus = "Informe e-mail ou contato do cuidador."
            return
        }

        do {
            let payload = BackendCaregiverPayload(
                name: caregiverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Cuidador" : caregiverName,
                contact: trimmedContact,
                relationship: caregiverRelationship.trimmingCharacters(in: .whitespacesAndNewlines),
                shareEnabled: shareWithCaregiver
            )
            _ = try await BackendAuthClient.createCaregiver(payload, token: authToken)
            careTeamSendStatus = "Cuidador cadastrado e autorizado."
            await loadCaregivers()
        } catch {
            careTeamSendStatus = "Falha ao cadastrar cuidador: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadCaregivers() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            remoteCaregivers = []
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            remoteCaregivers = try await BackendAuthClient.caregivers(token: authToken)
        } catch {
            careTeamSendStatus = "Falha ao carregar cuidadores: \(error.localizedDescription)"
        }
    }

    @MainActor
    func toggleCaregiverSharing(_ caregiver: BackendCaregiverContact) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            caregiverStatusMessage = "Modo local ativo: compartilhamento remoto desativado."
            return
        }
        guard !authToken.isEmpty else { return }
        let payload = BackendCaregiverPayload(
            name: caregiver.name,
            contact: caregiver.contact,
            relationship: caregiver.relationship,
            shareEnabled: !caregiver.shareEnabled
        )
        do {
            _ = try await BackendAuthClient.updateCaregiver(id: caregiver.id, payload: payload, token: authToken)
            caregiverStatusMessage = caregiver.shareEnabled
                ? "Notificações pausadas para \(caregiver.name)."
                : "Notificações reativadas para \(caregiver.name)."
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao atualizar \(caregiver.name): \(error.localizedDescription)"
        }
    }

    func beginEditingCaregiver(_ caregiver: BackendCaregiverContact) {
        caregiverEditName = caregiver.name
        caregiverEditContact = caregiver.contact
        caregiverEditRelationship = caregiver.relationship
        caregiverEditShareEnabled = caregiver.shareEnabled
        caregiverEditTarget = caregiver
    }

    func caregiverEditSheet(for caregiver: BackendCaregiverContact) -> some View {
        NavigationStack {
            Form {
                Section("Nome") {
                    TextField("Nome", text: $caregiverEditName)
                        .textContentType(.name)
                }
                Section("Contato (e-mail ou telefone)") {
                    // P1-8 (UX): keyboardType era .emailAddress, que não exibe
                    // teclado numérico por padrão — bloqueava entrada de telefone.
                    // .URL mostra @, ponto e números sem ocultar letras.
                    TextField("Contato", text: $caregiverEditContact)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                Section("Relação") {
                    TextField("Ex.: cônjuge, mãe, amigo", text: $caregiverEditRelationship)
                }
                Section {
                    Toggle("Receber alertas e relatórios", isOn: $caregiverEditShareEnabled)
                        .toggleStyle(.switch)
                }
            }
            .navigationTitle("Editar cuidador")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { caregiverEditTarget = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveCaregiverEdit(caregiver) }
                    } label: {
                        if isSavingCaregiverEdit {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Salvar")
                        }
                    }
                    .disabled(
                        isSavingCaregiverEdit
                        || caregiverEditName.trimmingCharacters(in: .whitespaces).isEmpty
                        || caregiverEditContact.trimmingCharacters(in: .whitespaces).count < 3
                    )
                }
            }
        }
    }

    @MainActor
    func saveCaregiverEdit(_ caregiver: BackendCaregiverContact) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            caregiverStatusMessage = "Modo local ativo: edição remota desativada."
            return
        }
        guard !authToken.isEmpty else { return }
        isSavingCaregiverEdit = true
        defer { isSavingCaregiverEdit = false }
        let payload = BackendCaregiverPayload(
            name: caregiverEditName.trimmingCharacters(in: .whitespaces),
            contact: caregiverEditContact.trimmingCharacters(in: .whitespaces),
            relationship: caregiverEditRelationship.trimmingCharacters(in: .whitespaces),
            shareEnabled: caregiverEditShareEnabled
        )
        do {
            _ = try await BackendAuthClient.updateCaregiver(id: caregiver.id, payload: payload, token: authToken)
            caregiverStatusMessage = "\(payload.name) atualizado."
            caregiverEditTarget = nil
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao atualizar: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteCaregiver(_ caregiver: BackendCaregiverContact) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            remoteCaregivers.removeAll { $0.id == caregiver.id }
            caregiverStatusMessage = "Modo local ativo: cuidador removido apenas da lista local."
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            try await BackendAuthClient.deleteCaregiver(id: caregiver.id, token: authToken)
            caregiverStatusMessage = "\(caregiver.name) removido."
            await loadCaregivers()
        } catch {
            caregiverStatusMessage = "Falha ao remover \(caregiver.name): \(error.localizedDescription)"
        }
    }

    @MainActor
    func exportMyAccount() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            privacyStatusMessage = "Modo local ativo: use o backup local para exportar dados deste aparelho."
            return
        }
        guard !authToken.isEmpty else {
            privacyStatusMessage = "Entre na conta para exportar seus dados."
            return
        }
        privacyStatusMessage = "Solicitando exportação..."
        do {
            let data = try await BackendAuthClient.exportAccount(token: authToken)
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                privacyStatusMessage = "Falha ao exportar: pasta de documentos indisponível."
                return
            }
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = documents.appending(path: "neuremia-export-\(timestamp).json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            privacyExportURL = url
            privacyStatusMessage = "Exportação pronta. Use o botão de compartilhamento abaixo."
        } catch {
            privacyStatusMessage = "Falha ao exportar: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteOldClinicalData() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            privacyStatusMessage = "Modo local ativo: não há limpeza de dados clínicos no backend."
            return
        }
        guard !authToken.isEmpty else { return }
        privacyStatusMessage = "Apagando dados antigos..."
        do {
            let response = try await BackendAuthClient.deleteOldClinicalData(daysOlderThan: privacyRetentionDays, token: authToken)
            privacyStatusMessage = "Removidos do backend: \(response.deletedCheckins) check-ins, \(response.deletedAssessments) escalas, \(response.deletedAlerts) alertas, \(response.deletedReports) relatórios."
        } catch {
            privacyStatusMessage = "Falha ao apagar dados antigos: \(error.localizedDescription)"
        }
    }

    @MainActor
    func deleteMyAccount() async {
        guard !authToken.isEmpty else { return }
        privacyStatusMessage = "Apagando conta..."
        do {
            let response = try await BackendAuthClient.deleteAccount(token: authToken)
            privacyStatusMessage = response.message
            logout()
        } catch {
            privacyStatusMessage = "Falha ao apagar conta: \(error.localizedDescription)"
        }
    }

    @MainActor
    func fetchAuditLogs() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            remoteAuditLogs = []
            privacyStatusMessage = "Modo local ativo: auditoria remota desativada."
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            remoteAuditLogs = try await BackendAuthClient.auditLogs(token: authToken)
            isShowingAuditLogs = true
        } catch {
            privacyStatusMessage = "Falha ao carregar auditoria: \(error.localizedDescription)"
        }
    }

    /// Backend creates ClinicalAlert rows when a high-risk check-in is submitted.
    /// Pull them into local SwiftData so the patient actually sees them in the
    /// "Alertas acionáveis" section instead of only the clinician dashboard.
    @MainActor
    func syncMyBackendAlerts() async {
        guard DataResidencyPolicy.remoteSyncEnabled else { return }
        guard !authToken.isEmpty,
              authenticatedUserId > 0,
              activeRole == .patient else {
            return
        }

        do {
            let backendAlerts = try await BackendAuthClient.patientAlerts(
                patientId: authenticatedUserId,
                token: authToken
            )
            let isoWithFraction = ISO8601DateFormatter()
            isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoBasic = ISO8601DateFormatter()
            isoBasic.formatOptions = [.withInternetDateTime]

            var insertedAny = false
            for backendAlert in backendAlerts {
                let date = isoWithFraction.date(from: backendAlert.createdAt)
                    ?? isoBasic.date(from: backendAlert.createdAt)
                    ?? Date()

                let alreadyExists = alerts.contains { existing in
                    existing.title == backendAlert.title
                        && existing.message == backendAlert.message
                        && abs(existing.date.timeIntervalSince(date)) < 5
                }
                guard !alreadyExists else { continue }

                modelContext.insert(ClinicalAlert(
                    date: date,
                    level: Self.backendLevelToClinical(backendAlert.level),
                    kind: ClinicalAlertKind(rawValue: backendAlert.alertType) ?? .psychiatricEmergency,
                    escalationTarget: ClinicalEscalationTarget(rawValue: backendAlert.escalationTarget) ?? .clinicianCaregiverNow,
                    title: backendAlert.title,
                    message: backendAlert.message,
                    acknowledged: backendAlert.acknowledged
                ))
                insertedAny = true
            }

            if insertedAny {
                try modelContext.save()
            }
        } catch {
            // Silent: patient still sees locally generated alerts.
        }
    }

    static func backendLevelToClinical(_ level: String) -> ClinicalRiskLevel {
        switch level.lowercased() {
        case "high", "critical", "urgent":
            return .high
        case "moderate", "medium":
            return .moderate
        case "low", "minimal", "normal":
            return .low
        default:
            // Unknown severity from the backend (e.g. a future tier not yet
            // reflected here) MUST NOT be silently downgraded to .low. Treat
            // it as moderate so the patient/clinician is at least nudged to
            // review it manually. Log so the team knows to add a case.
            assertionFailure("backendLevelToClinical: unrecognised level '\(level)' — add a case")
            return .moderate
        }
    }

    @MainActor
    func requestRemotePushRegistration() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                remotePushStatus = "Permissão de push negada."
                return
            }

            remotePushEnabled = true
            remotePushStatus = "Registrando no APNs..."
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            remotePushStatus = "Falha ao solicitar push: \(error.localizedDescription)"
        }
    }

    @MainActor
    func uploadPushTokenToBackend() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            remotePushStatus = "Modo local ativo: token APNs não enviado ao backend."
            return
        }
        let token = apnsDeviceToken.isEmpty
            ? KeychainStore.string(for: .apnsDeviceToken) ?? ""
            : apnsDeviceToken
        guard !token.isEmpty else {
            remotePushStatus = "Token APNs ainda não disponível."
            return
        }
        guard !authToken.isEmpty else {
            remotePushStatus = "Entre na conta para vincular o token ao backend."
            return
        }

        do {
            try await BackendAuthClient.registerPushToken(token: token, platform: "ios", token: authToken)
            apnsDeviceToken = token
            remotePushStatus = "Token APNs enviado ao backend."
        } catch {
            remotePushStatus = "Falha ao enviar token: \(error.localizedDescription)"
        }
    }

    @MainActor
    func dispatchCriticalSafetyAlert(textAssessment: TextRiskAssessment) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            remotePushStatus = "Alerta crítico local registrado. Modo local ativo: escalonamento remoto desativado."
            return
        }
        guard criticalPushConsent || caregiverSMSConsent || caregiverDigestConsent else {
            remotePushStatus = "Alerta crítico local registrado. Consentimento remoto crítico não autorizado."
            return
        }
        guard !authToken.isEmpty else {
            remotePushStatus = "Alerta crítico local registrado. Entre na conta para escalonar ao backend."
            return
        }

        let enabledCaregivers = remoteCaregivers.filter(\.shareEnabled)
        var channels: [String] = []
        if criticalPushConsent { channels.append("apns_critical") }
        if caregiverSMSConsent && !enabledCaregivers.isEmpty { channels.append("caregiver_sms") }
        if caregiverDigestConsent { channels.append("clinician_digest") }

        let protocolSummary = ClinicalAlertProtocol.local(
            kind: .psychiatricEmergency,
            escalationTarget: .clinicianCaregiverNow,
            criticalPushConsent: criticalPushConsent,
            caregiverSMSConsent: caregiverSMSConsent,
            caregiverDigestConsent: caregiverDigestConsent,
            enabledCaregiverCount: enabledCaregivers.count,
            safetyContactAvailable: !safetyContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        let policy = """
        Política de risco suicida: \(protocolSummary.recipients) \(protocolSummary.responseWindow) \(protocolSummary.acknowledgement) \(protocolSummary.escalation) \(protocolSummary.falsePositiveHandling) \(protocolSummary.legalLimit) Conteúdo livre sensível não deve ser enviado; usar apenas resumo mínimo.
        """

        let payload = BackendCriticalAlertPayload(
            level: ClinicalRiskLevel.high.rawValue,
            alertType: ClinicalAlertKind.psychiatricEmergency.rawValue,
            escalationTarget: ClinicalEscalationTarget.clinicianCaregiverNow.rawValue,
            title: "Risco de segurança prioritário",
            message: "\(textAssessment.explanation) \(textAssessment.recommendation) \(protocolSummary.responseWindow)",
            policy: policy,
            channels: channels,
            caregiverIds: enabledCaregivers.map(\.id),
            apnsToken: apnsDeviceToken.isEmpty ? nil : apnsDeviceToken,
            safetyPlanSummary: safetyPlanSummaryForEscalation()
        )

        do {
            let dispatch = try await BackendAuthClient.dispatchCriticalAlert(payload, token: authToken)
            remotePushStatus = dispatch.acknowledgementRequired
                ? "Alerta crítico enviado. Aguardando confirmação de recebimento."
                : "Alerta crítico enviado ao backend."
        } catch {
            remotePushStatus = "Falha no escalonamento remoto: \(error.localizedDescription)"
        }
    }

    func safetyPlanSummaryForEscalation() -> String {
        [
            safetyContact.isEmpty ? nil : "Contato: \(safetyContact)",
            safetyWarningSigns.isEmpty ? nil : "Sinais: \(safetyWarningSigns)",
            safetyStrategies.isEmpty ? nil : "Estratégias: \(safetyStrategies)"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    @MainActor
    func requestHealthKitAccessAndSync() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitStatus = "HealthKit não disponível neste dispositivo."
            return
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            healthKitStatus = "Tipos do Apple Health indisponíveis."
            return
        }

        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        var readTypes: Set<HKObjectType> = [stepType, heartRateType, hrvType, activeEnergyType, sleepType]
        var sampleTypes: [HKSampleType] = [stepType, heartRateType, hrvType, activeEnergyType, sleepType]
        if let restingHeartRateType {
            readTypes.insert(restingHeartRateType)
            sampleTypes.append(restingHeartRateType)
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)

            let backgroundNote: String
            do {
                try await enableHealthKitBackgroundDelivery(for: sampleTypes)
                backgroundNote = "Background ativo."
            } catch {
                backgroundNote = "Background pendente: \(error.localizedDescription)"
            }

            // Register HKObserverQuery for every sample type so background
            // delivery actually reaches the app (enableBackgroundDelivery is
            // a no-op without an observer). Idempotent — safe on re-entry.
            await installContinuousPipelineObservers(store: healthStore, types: sampleTypes)

            // Refresh the full passive-history window kept by the store. The
            // observer path pulls deltas as they arrive; this pass rebuilds the
            // daily rollup and fills gaps left by hourly-throttled sample types.
            let history = try await healthKitDailyHistory(
                stepType: stepType,
                heartRateType: heartRateType,
                restingHeartRateType: restingHeartRateType,
                hrvType: hrvType,
                activeEnergyType: activeEnergyType,
                sleepType: sleepType,
                days: HealthKitPipelineStore.passiveHistoryDays
            )
            var pipelineStore = HealthKitPipelineStore.decode(from: healthKitPipelineData)
            pipelineStore.merge(history)
            healthKitPipelineData = pipelineStore.encodedString()

            let todayKey = DailyCheckIn.dayKey(for: Date())
            let today = pipelineStore.snapshots.first { $0.dayKey == todayKey } ?? history.first
            healthSteps = today?.steps ?? 0
            healthActiveEnergy = today?.activeEnergy ?? 0
            healthHeartRate = today?.heartRate ?? 0
            healthHRV = today?.hrv ?? 0
            healthSleepHours = today?.sleepHours ?? 0
            if healthSleepHours > 0 {
                sleepHours = healthSleepHours
            }
            updateHealthHRVBaselineIfNeeded(healthHRV, qualityScore: today?.qualityScore ?? 0)
            healthKitEnabled = true
            lastHealthKitSyncAt = Date().timeIntervalSince1970

            // Multi-day reconciliation: compare every stored HK snapshot
            // against the diary check-in for the same day so the user sees
            // exactly which days need review, not just today.
            let checkInsByDay = Dictionary(
                uniqueKeysWithValues: sortedCheckIns.map { checkIn in
                    (checkIn.dayKey, (sleepHours: checkIn.sleepHours, hasEntry: true))
                }
            )
            let reconciliationReport = HealthKitPipelineQuality.reconcile(
                snapshots: pipelineStore.snapshots,
                checkInsByDay: checkInsByDay
            )
            healthKitReconciliationData = reconciliationReport.encodedString()

            // Authorization probe: iOS masks read-denial as a privacy feature,
            // so we probe each type for a single sample over 30 days. Types
            // that came back empty become "suspected silent denials" that the
            // UI can surface as a recovery hint.
            let authSnapshot = await HealthKitAuthorizationProbe.probe(
                store: healthStore,
                readTypes: sampleTypes,
                shareTypes: []
            )
            if let encoded = try? JSONEncoder().encode(authSnapshot),
               let string = String(data: encoded, encoding: .utf8) {
                healthKitAuthData = string
            }

            let quality = Int(((today?.qualityScore ?? 0) * 100).rounded())
            let reconciliationSummary: String
            if reconciliationReport.issues.isEmpty {
                reconciliationSummary = "Reconciliado em \(reconciliationReport.daysReconciled) dias."
            } else {
                reconciliationSummary = "\(reconciliationReport.issues.count) dias para revisar (\(reconciliationReport.criticalCount) críticos)."
            }
            let authNote = authSnapshot.suspectedSilentDenials.isEmpty
                ? ""
                : " Verifique Ajustes › Privacidade › Saúde: \(authSnapshot.suspectedSilentDenials.count) tipo(s) sem dados."
            healthKitStatus = "Apple Health: \(pipelineStore.snapshots.count) dias, qualidade \(quality)%. \(reconciliationSummary) \(backgroundNote)\(authNote)"
        } catch {
            healthKitStatus = "Falha ao acessar Apple Health: \(error.localizedDescription)"
        }
        #else
        healthKitStatus = "HealthKit não está disponível neste alvo."
        #endif
    }

    #if canImport(HealthKit)
    /// Register (once) HKObserverQuery for every sample type. When HK fires
    /// the observer (foreground or background) the controller pulls a delta
    /// via HKAnchoredObjectQuery and asks the main actor to re-run the
    /// aggregate sync so UI + baselines stay current.
    @MainActor
    func installContinuousPipelineObservers(store: HKHealthStore, types: [HKSampleType]) async {
        await HealthKitPipelineController.shared.registerObservers(
            store: store,
            types: types
        ) { _, _ in
            // The delta pull already advanced the anchor. Kick a light
            // aggregate refresh on the main actor so daily buckets pick
            // up the new samples. Throttled to avoid a thundering-herd
            // when several types fire simultaneously.
            await MainActor.run {
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: "neuremiaLastHealthKitObserverAt"
                )
            }
        }
    }
    #endif

    @MainActor
    func syncContinuousHealthKitIfNeeded(force: Bool) async {
        guard healthKitEnabled else { return }
        let now = Date().timeIntervalSince1970
        // Sync if:
        //  • caller forced it, or
        //  • the active screen's minimum sync window elapsed, or
        //  • an HKObserverQuery delta arrived while we were backgrounded and
        //    the aggregate rollup hasn't caught up yet.
        let minimumInterval: TimeInterval = selectedPatientPage == .diary ? 5 * 60 : 15 * 60
        let observerAt = UserDefaults.standard.double(forKey: "neuremiaLastHealthKitObserverAt")
        let observerPending = observerAt > lastHealthKitSyncAt
        guard force || now - lastHealthKitSyncAt > minimumInterval || observerPending else { return }
        await requestHealthKitAccessAndSync()
    }

    @MainActor
    func updateHealthHRVBaselineIfNeeded(_ hrv: Double, qualityScore: Double = 0) {
        guard biometricConsentAccepted, (10...180).contains(hrv), qualityScore >= 0.55 else { return }

        var contextualStore = HRVContextBaselineStore.decode(from: hrvContextBaselinesData)
        contextualStore.record(
            hrv: hrv,
            date: Date(),
            ppgStress: 0,
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

    #if canImport(HealthKit)
    func healthKitDailyHistory(
        stepType: HKQuantityType,
        heartRateType: HKQuantityType,
        restingHeartRateType: HKQuantityType?,
        hrvType: HKQuantityType,
        activeEnergyType: HKQuantityType,
        sleepType: HKCategoryType,
        days: Int
    ) async throws -> [HealthKitDailySnapshot] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        async let stepBuckets = dailyQuantityBuckets(for: stepType, unit: .count(), options: .cumulativeSum, start: start, end: Date())
        async let energyBuckets = dailyQuantityBuckets(for: activeEnergyType, unit: .kilocalorie(), options: .cumulativeSum, start: start, end: Date())
        async let heartRateBuckets = dailyQuantityBuckets(for: heartRateType, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, start: start, end: Date())
        async let hrvBuckets = dailyQuantityBuckets(for: hrvType, unit: .secondUnit(with: .milli), options: .discreteAverage, start: start, end: Date())
        async let sleepBuckets = dailySleepBuckets(for: sleepType, start: start, end: Date())
        async let sleepTimingBuckets = dailySleepTimingBuckets(for: sleepType, start: start, end: Date())
        // Density/source-rank probe over the window. Runs in parallel with
        // the aggregate buckets; used only for scoring, not for values.
        async let hrDensity = dailySampleDensity(for: heartRateType, start: start, end: Date())
        async let hrvDensity = dailySampleDensity(for: hrvType, start: start, end: Date())
        async let stepDensity = dailySampleDensity(for: stepType, start: start, end: Date())

        let steps = try await stepBuckets
        let energy = try await energyBuckets
        let heartRate = try await heartRateBuckets
        let restingHeartRate = if let restingHeartRateType {
            try await dailyQuantityBuckets(for: restingHeartRateType, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, start: start, end: Date())
        } else {
            [String: Double]()
        }
        let hrv = try await hrvBuckets
        let sleep = try await sleepBuckets
        let sleepTiming = try await sleepTimingBuckets
        let hrDens = try await hrDensity
        let rhrDens = if let restingHeartRateType {
            try await dailySampleDensity(for: restingHeartRateType, start: start, end: Date())
        } else {
            [String: (count: Int, hasWatch: Bool)]()
        }
        let hrvDens = try await hrvDensity
        let stepDens = try await stepDensity

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DailyCheckIn.dayKey(for: date)
            let sourceCount = [
                (sleep[key] ?? 0) > 0,
                (steps[key] ?? 0) > 0,
                (heartRate[key] ?? 0) > 0,
                (restingHeartRate[key] ?? 0) > 0,
                (hrv[key] ?? 0) > 0,
                (energy[key] ?? 0) > 0
            ].filter { $0 }.count

            // Signal quality now weighs source diversity + sample density +
            // Watch presence, matching what a clinician would eyeball when
            // deciding whether a day's data is trustworthy for HRV analysis.
            let metrics = HealthKitDailySignalMetrics(
                heartRateSamples: hrDens[key]?.count ?? 0,
                restingHeartRateSamples: rhrDens[key]?.count ?? 0,
                hrvSamples: hrvDens[key]?.count ?? 0,
                stepSamples: stepDens[key]?.count ?? 0,
                hasWatchSource: (hrDens[key]?.hasWatch ?? false) || (rhrDens[key]?.hasWatch ?? false) || (hrvDens[key]?.hasWatch ?? false),
                hasSleepSample: (sleep[key] ?? 0) > 0,
                hasEnergySample: (energy[key] ?? 0) > 0
            )
            let quality = metrics.score(sourceCount: sourceCount)

            return HealthKitDailySnapshot(
                dayKey: key,
                date: date,
                sleepHours: sleep[key] ?? 0,
                steps: Int((steps[key] ?? 0).rounded()),
                heartRate: heartRate[key] ?? 0,
                hrv: hrv[key] ?? 0,
                activeEnergy: energy[key] ?? 0,
                qualityScore: quality,
                sourceCount: sourceCount,
                restingHeartRate: restingHeartRate[key],
                circadianRegularityScore: circadianRegularity(for: key, sleepTiming: sleepTiming),
                heartRateSampleCount: metrics.heartRateSamples,
                restingHeartRateSampleCount: metrics.restingHeartRateSamples,
                hrvSampleCount: metrics.hrvSamples,
                stepSampleCount: metrics.stepSamples,
                hasWatchSource: metrics.hasWatchSource
            )
        }
        .sorted { $0.date > $1.date }
    }

    /// Per-day sample density + Watch presence for a given quantity type.
    /// Samples are deduplicated (dropping manual entries, preferring Watch
    /// over iPhone for identical windows) before counting so a single
    /// activity reported by both devices doesn't double-count.
    func dailySampleDensity(
        for type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> [String: (count: Int, hasWatch: Bool)] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let raw = (samples ?? []).compactMap { $0 as HKSample }
                let deduped = HealthKitPipelineQuality.dedupe(raw)
                var buckets: [String: (count: Int, hasWatch: Bool)] = [:]
                for sample in deduped {
                    let key = DailyCheckIn.dayKey(for: sample.startDate)
                    let isWatch = HealthKitSampleSourceRank.rank(sample) == .watch
                    let existing = buckets[key] ?? (0, false)
                    buckets[key] = (existing.count + 1, existing.hasWatch || isWatch)
                }
                continuation.resume(returning: buckets)
            }
            healthStore.execute(query)
        }
    }

    func enableHealthKitBackgroundDelivery(for sampleTypes: [HKSampleType]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for type in sampleTypes {
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else if success {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: NSError(
                                    domain: "Neuremia.HealthKit",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Background delivery não foi ativado para \(type.identifier)."]
                                ))
                            }
                        }
                    }
                }
            }

            try await group.waitForAll()
        }
    }

    func healthKitReconciliationNote(for snapshot: HealthKitDailySnapshot?) -> String {
        guard let snapshot else { return "Sem amostra automática para hoje." }
        guard let checkIn = sortedCheckIns.first(where: { $0.dayKey == snapshot.dayKey }) else {
            return "Sem check-in correspondente para reconciliar."
        }

        var notes: [String] = []
        if snapshot.sleepHours > 0, abs(snapshot.sleepHours - checkIn.sleepHours) >= 1.0 {
            notes.append("sono difere do diário em \(String(format: "%.1f", abs(snapshot.sleepHours - checkIn.sleepHours)))h")
        }
        if snapshot.qualityScore < 0.6 {
            notes.append("qualidade parcial")
        }
        return notes.isEmpty ? "Reconciliado com o check-in de hoje." : "Revisar: \(notes.joined(separator: ", "))."
    }

    func dayPredicate() -> NSPredicate {
        let start = Calendar.current.startOfDay(for: Date())
        return HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
    }

    func dailyQuantityBuckets(
        for type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let calendar = Calendar.current
            let interval = DateComponents(day: 1)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var values: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let value: Double
                    if options.contains(.cumulativeSum) {
                        value = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                    } else {
                        value = statistics.averageQuantity()?.doubleValue(for: unit) ?? 0
                    }
                    values[DailyCheckIn.dayKey(for: statistics.startDate)] = value
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    func quantitySum(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: dayPredicate(), options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    func quantityAverage(for type: HKQuantityType, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: dayPredicate(), options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    func sleepHoursFromHealthKit(sleepType: HKCategoryType) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let start = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
            let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    switch value {
                    case .asleep, .asleepCore, .asleepDeep, .asleepREM:
                        return total + sample.endDate.timeIntervalSince(sample.startDate)
                    default:
                        return total
                    }
                }
                continuation.resume(returning: sleepSeconds / 3600)
            }
            healthStore.execute(query)
        }
    }

    func dailySleepBuckets(for sleepType: HKCategoryType, start: Date, end: Date) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var secondsByDay: [String: Double] = [:]
                for sample in samples as? [HKCategorySample] ?? [] {
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    switch value {
                    case .asleep, .asleepCore, .asleepDeep, .asleepREM:
                        let key = DailyCheckIn.dayKey(for: sample.startDate)
                        secondsByDay[key, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
                    default:
                        continue
                    }
                }
                continuation.resume(returning: secondsByDay.mapValues { $0 / 3600 })
            }
            healthStore.execute(query)
        }
    }

    func dailySleepTimingBuckets(for sleepType: HKCategoryType, start: Date, end: Date) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var weightedMidpointByDay: [String: Double] = [:]
                var secondsByDay: [String: Double] = [:]
                let calendar = Calendar.current
                for sample in samples as? [HKCategorySample] ?? [] {
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    switch value {
                    case .asleep, .asleepCore, .asleepDeep, .asleepREM:
                        let duration = sample.endDate.timeIntervalSince(sample.startDate)
                        guard duration > 0 else { continue }
                        let midpoint = sample.startDate.addingTimeInterval(duration / 2)
                        let components = calendar.dateComponents([.hour, .minute, .second], from: midpoint)
                        let secondsFromMidnight = Double((components.hour ?? 0) * 3_600 + (components.minute ?? 0) * 60 + (components.second ?? 0))
                        let key = DailyCheckIn.dayKey(for: sample.startDate)
                        weightedMidpointByDay[key, default: 0] += secondsFromMidnight * duration
                        secondsByDay[key, default: 0] += duration
                    default:
                        continue
                    }
                }

                var values: [String: Double] = [:]
                for (key, weighted) in weightedMidpointByDay {
                    guard let total = secondsByDay[key], total > 0 else { continue }
                    values[key] = weighted / total
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    func circadianRegularity(for dayKey: String, sleepTiming: [String: Double]) -> Double? {
        guard let current = sleepTiming[dayKey], sleepTiming.count >= 3 else { return nil }
        let references = sleepTiming
            .filter { $0.key != dayKey }
            .map(\.value)
        guard !references.isEmpty else { return nil }
        let mean = references.reduce(0, +) / Double(references.count)
        let delta = min(abs(current - mean), 86_400 - abs(current - mean)) / 3_600
        return min(max(1 - delta / 3.0, 0), 1)
    }
    #endif

    func handleBackupImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            try restoreBackup(from: data)
            loginStatusMessage = "Backup restaurado."
        } catch {
            loginStatusMessage = "Não foi possível restaurar o backup: \(error.localizedDescription)"
        }
    }

    func restoreBackup(from data: Data) throws {
        // Parse via the canonical NeuremiaBackupSnapshot type.
        // Falls back to legacy [String:Any] parsing for files produced
        // before schema v2 (missing schemaVersion key).
        if let snapshot = try? NeuremiaBackupSnapshot.decode(from: data) {
            guard snapshot.schemaVersion <= 2 else {
                throw NSError(domain: "Neuremia", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backup criado por uma versão mais recente do app. Atualize a Neuremia para importar este arquivo."])
            }
            try validateEncryptedBackupFields(snapshot)
            try restoreFromSnapshot(snapshot)
        } else {
            try restoreFromLegacyPayload(data)
        }

        var importedURL = BackupStore.protectedFileURL
        if (try? data.write(to: importedURL, options: [.atomic, .completeFileProtection])) != nil {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            do {
                try importedURL.setResourceValues(resourceValues)
            } catch {
                try? FileManager.default.removeItem(at: importedURL)
                throw NSError(
                    domain: "Neuremia.Backup",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Não foi possível proteger o arquivo de backup contra cópia em nuvem."]
                )
            }
            backupURL = importedURL
            lastAutomaticBackupAt = Date().timeIntervalSince1970
        }
    }

    func validateEncryptedBackupFields(_ snapshot: NeuremiaBackupSnapshot) throws {
        var unreadableFields: [String] = []

        func validate(_ value: String, label: String) {
            guard appearsToBeEncryptedBackupField(value),
                  DraftStore.decryptString(value) == nil else {
                return
            }
            unreadableFields.append(label)
        }

        validate(snapshot.medicationPlan.prescriptionEnc, label: "plano de medicação")
        validate(snapshot.medicationPlan.changeNoteEnc, label: "alterações de medicação")
        validate(snapshot.safetyPlan.contactEnc, label: "contato do plano de segurança")
        validate(snapshot.safetyPlan.warningSignsEnc, label: "sinais do plano de segurança")
        validate(snapshot.safetyPlan.strategiesEnc, label: "estratégias do plano de segurança")

        for checkIn in snapshot.checkIns {
            let day = DailyCheckIn.dayKey(for: checkIn.date)
            validate(checkIn.sideEffectsEnc, label: "efeitos colaterais em \(day)")
            validate(checkIn.automaticThoughtsEnc, label: "pensamentos em \(day)")
            validate(checkIn.journalEntryEnc, label: "diário em \(day)")
        }

        guard unreadableFields.isEmpty else {
            throw NSError(
                domain: "Neuremia.Backup",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Este backup contém textos protegidos por outra chave do aparelho. A importação foi cancelada para evitar perda parcial de dados."
                ]
            )
        }
    }

    func appearsToBeEncryptedBackupField(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let decoded = Data(base64Encoded: trimmed) else {
            return false
        }
        return decoded.count >= 29
    }

    func restoreFromSnapshot(_ snapshot: NeuremiaBackupSnapshot) throws {
        var importedDayKeys = Set(checkIns.map(\.dayKey))
        for c in snapshot.checkIns {
            let importedDayKey = DailyCheckIn.dayKey(for: c.date)
            guard !importedDayKeys.contains(importedDayKey) else { continue }
            importedDayKeys.insert(importedDayKey)
            modelContext.insert(DailyCheckIn(
                date: c.date,
                mood: c.mood.clamped(to: 0...5), anxiety: c.anxiety.clamped(to: 0...5),
                energy: c.energy.clamped(to: 0...5), irritability: c.irritability.clamped(to: 0...5),
                sleepHours: c.sleepHours.clamped(to: 0...24),
                appetite: c.appetite.clamped(to: 0...5), libido: c.libido.clamped(to: 0...5),
                medicationTaken: c.medicationTaken,
                sideEffects: decryptField(c.sideEffectsEnc),
                automaticThoughts: decryptField(c.automaticThoughtsEnc),
                suicidalIdeation: c.suicidalIdeation,
                journalEntry: decryptField(c.journalEntryEnc)
            ))
        }
        var importedAssessmentKeys = Set(assessments.map {
            "\($0.scaleName)|\(Int($0.date.timeIntervalSince1970))"
        })
        for a in snapshot.assessments {
            let importedAssessmentKey = "\(a.scaleName)|\(Int(a.date.timeIntervalSince1970))"
            guard !importedAssessmentKeys.contains(importedAssessmentKey) else { continue }
            importedAssessmentKeys.insert(importedAssessmentKey)
            modelContext.insert(ScaleAssessment(
                scaleName: a.scaleName, date: a.date,
                answers: a.answers.map { min(max($0, 0), 8) },
                score: max(a.score, 0), interpretation: String(a.interpretation.prefix(500))
            ))
        }
        medicationPlans = snapshot.medicationPlans
        persistMedicationPlans()
        customSymptoms = snapshot.customSymptoms
        persistCustomSymptoms()
        safetyContact = decryptField(snapshot.safetyPlan.contactEnc, fallback: safetyContact)
        safetyWarningSigns = decryptField(snapshot.safetyPlan.warningSignsEnc, fallback: safetyWarningSigns)
        safetyStrategies = decryptField(snapshot.safetyPlan.strategiesEnc, fallback: safetyStrategies)
        try modelContext.save()
    }

    /// Legacy path for backups produced before schema v2.
    func restoreFromLegacyPayload(_ data: Data) throws {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let formatter = ISO8601DateFormatter()
        if let checkInPayloads = payload["checkIns"] as? [[String: Any]] {
            var importedDayKeys = Set(checkIns.map(\.dayKey))
            for item in checkInPayloads {
                let date = (item["date"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
                let importedDayKey = DailyCheckIn.dayKey(for: date)
                guard !importedDayKeys.contains(importedDayKey) else { continue }
                importedDayKeys.insert(importedDayKey)
                modelContext.insert(DailyCheckIn(
                    date: date,
                    mood: clampedScalar(item["mood"], range: 0...5, fallback: 3),
                    anxiety: clampedScalar(item["anxiety"], range: 0...5, fallback: 2),
                    energy: clampedScalar(item["energy"], range: 0...5, fallback: 3),
                    irritability: clampedScalar(item["irritability"], range: 0...5, fallback: 1),
                    sleepHours: clampedScalar(item["sleepHours"], range: 0...24, fallback: 7),
                    appetite: clampedScalar(item["appetite"], range: 0...5, fallback: 3),
                    libido: clampedScalar(item["libido"], range: 0...5, fallback: 3),
                    medicationTaken: item["medicationTaken"] as? Bool ?? false,
                    sideEffects: decryptField(item["sideEffects"]),
                    automaticThoughts: decryptField(item["automaticThoughts"]),
                    suicidalIdeation: item["suicidalIdeation"] as? Bool ?? false,
                    journalEntry: decryptField(item["journalEntry"])
                ))
            }
        }
        if let assessmentPayloads = payload["assessments"] as? [[String: Any]] {
            var importedAssessmentKeys = Set(assessments.map {
                "\($0.scaleName)|\(Int($0.date.timeIntervalSince1970))"
            })
            for item in assessmentPayloads {
                let date = (item["date"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
                let scaleName = sanitizedString(item["scaleName"], fallback: "Escala")
                let importedAssessmentKey = "\(scaleName)|\(Int(date.timeIntervalSince1970))"
                guard !importedAssessmentKeys.contains(importedAssessmentKey) else { continue }
                importedAssessmentKeys.insert(importedAssessmentKey)
                let answers = (item["answers"] as? [Int] ?? []).map { min(max($0, 0), 8) }
                modelContext.insert(ScaleAssessment(
                    scaleName: scaleName, date: date, answers: answers,
                    score: max(item["score"] as? Int ?? 0, 0),
                    interpretation: sanitizedString(item["interpretation"])
                ))
            }
        }
        if let safetyPlan = payload["safetyPlan"] as? [String: Any] {
            safetyContact = decryptField(safetyPlan["contact"], fallback: safetyContact)
            safetyWarningSigns = decryptField(safetyPlan["warningSigns"], fallback: safetyWarningSigns)
            safetyStrategies = decryptField(safetyPlan["strategies"], fallback: safetyStrategies)
        }
        try modelContext.save()
    }

    /// Best-effort coercion of an Any? backup field into a Double clamped
    /// to the expected clinical range. Strings like "3.5" are accepted as
    /// a courtesy (older backups exported them as such).
    func clampedScalar(_ raw: Any?, range: ClosedRange<Double>, fallback: Double) -> Double {
        let candidate: Double?
        switch raw {
        case let value as Double:
            candidate = value
        case let value as Int:
            candidate = Double(value)
        case let value as NSNumber:
            candidate = value.doubleValue
        case let value as String:
            candidate = Double(value)
        default:
            candidate = nil
        }
        guard let value = candidate, value.isFinite, range.contains(value) else {
            return fallback
        }
        return value
    }

    /// Strips surrounding whitespace and limits length so a maliciously
    /// crafted backup cannot inflate SwiftData rows arbitrarily.
    func sanitizedString(_ raw: Any?, fallback: String = "") -> String {
        guard let value = raw as? String else { return fallback }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(8_000))
    }

    /// Decrypt a PHI field from the backup JSON (N-C1).
    /// Falls back to treating the value as plaintext for backward compatibility
    /// with backups created before encryption was introduced.
    func decryptField(_ raw: Any?, fallback: String = "") -> String {
        guard let value = raw as? String, !value.isEmpty else { return fallback }
        // Try to decrypt — if it fails, the value may be a legacy plaintext field.
        if let decrypted = DraftStore.decryptString(value) {
            return String(decrypted.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8_000))
        }
        // Legacy plaintext fallback (backups before N-C1 fix).
        return sanitizedString(raw, fallback: fallback)
    }

    @MainActor
    func configureLocalReminders(showStatus: Bool = true) async {
        let notificationIDs = ["neuremia.medication", "neuremia.checkin", "neuremia.retention"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIDs)

        guard medicationReminderEnabled || checkInReminderEnabled || dailyRetentionReminderEnabled else {
            if showStatus {
                loginStatusMessage = "Lembretes desligados."
            }
            return
        }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                if showStatus {
                    loginStatusMessage = "Permissão de notificação não concedida."
                }
                return
            }

            if medicationReminderEnabled {
                scheduleDailyNotification(
                    id: "neuremia.medication",
                    title: "Hora da medicação",
                    body: "Registre se tomou sua medicação e como está se sentindo.",
                    hour: medicationReminderHour
                )
            }

            if checkInReminderEnabled {
                scheduleDailyNotification(
                    id: "neuremia.checkin",
                    title: "Check-in Neuremia",
                    body: "Leva menos de um minuto para registrar seu dia.",
                    hour: checkInReminderHour
                )
            }

            if dailyRetentionReminderEnabled {
                scheduleDailyNotification(
                    id: "neuremia.retention",
                    title: "Mantenha sua sequência",
                    body: "Registre seu dia na Neuremia e ganhe XP para acompanhar seus padrões.",
                    hour: dailyRetentionReminderHour
                )
            }

            if showStatus {
                loginStatusMessage = "Lembretes configurados."
            }
        } catch {
            if showStatus {
                loginStatusMessage = "Não foi possível configurar lembretes: \(error.localizedDescription)"
            }
        }
    }

    func scheduleDailyNotification(id: String, title: String, body: String, hour: Int) {
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func makeCSVReport() -> URL? {
        var rows = ["type,date,mood,anxiety,energy,irritability,sleep_hours,medication_taken,suicidal_ideation,scale,score,interpretation"]
        for checkIn in sortedCheckIns {
            rows.append([
                "check_in",
                ISO8601DateFormatter().string(from: checkIn.date),
                String(format: "%.1f", checkIn.mood),
                String(format: "%.1f", checkIn.anxiety),
                String(format: "%.1f", checkIn.energy),
                String(format: "%.1f", checkIn.irritability),
                String(format: "%.1f", checkIn.sleepHours),
                checkIn.medicationTaken ? "true" : "false",
                checkIn.suicidalIdeation ? "true" : "false",
                "",
                "",
                ""
            ].joined(separator: ","))
        }

        for assessment in sortedAssessments {
            rows.append([
                "assessment",
                ISO8601DateFormatter().string(from: assessment.date),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                assessment.scaleName,
                "\(assessment.score)",
                csvEscaped(assessment.interpretation)
            ].joined(separator: ","))
        }

        let url = FileManager.default.temporaryDirectory.appending(path: "neuremia-registros.csv")
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    func makePDFReport(text: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "neuremia-relatorio.pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let margin: CGFloat = 36
                var y = margin
                let width = pageRect.width - margin * 2

                drawPDFText("Neuremia", in: CGRect(x: margin, y: y, width: width, height: 34), font: .boldSystemFont(ofSize: 24), color: .black)
                y += 34
                drawPDFText("Relatório para consulta", in: CGRect(x: margin, y: y, width: width, height: 22), font: .systemFont(ofSize: 14), color: .darkGray)
                y += 30

                UIColor.neuroGold.setFill()
                context.cgContext.fill(CGRect(x: margin, y: y, width: width, height: 3))
                y += 18

                let summaryLines = [
                    "Gerado em: \(Date().formatted(date: .abbreviated, time: .shortened))",
                    "Risco atual: \(summary.riskLevel.rawValue)",
                    "Registros analisados: \(summary.analyzedCheckInCount)",
                    "Sono médio: \(String(format: "%.1f", summary.averageSleep))h",
                    "Adesão medicamentosa: \(String(format: "%.0f", summary.medicationAdherence * 100))%"
                ]

                y = drawPDFSection("Resumo", lines: summaryLines, x: margin, y: y, width: width)
                y = drawPDFTrendChart(x: margin, y: y + 8, width: width, context: context.cgContext)
                y = drawPDFSection("Sinais recentes", lines: summary.signals, x: margin, y: y + 10, width: width)

                let scaleLines = sortedAssessments.prefix(6).map { "\($0.scaleName): \($0.score) pontos - \($0.interpretation)" }
                y = drawPDFSection("Escalas", lines: scaleLines.isEmpty ? ["Nenhuma escala salva."] : scaleLines, x: margin, y: y + 10, width: width)

                y = drawPDFSection("Resumo mensal", lines: monthlyPDFLines(), x: margin, y: y + 10, width: width)

                let medicationLines = medicationPlans.map { plan in
                    [plan.name, plan.dose, plan.schedule, plan.prescription, plan.changeNote]
                        .filter { !$0.isEmpty }
                        .joined(separator: " • ")
                }
                y = drawPDFSection("Medicações", lines: medicationLines.isEmpty ? ["Nenhum medicamento cadastrado."] : medicationLines, x: margin, y: y + 10, width: width)

                let customSymptomLines = customSymptoms.map { "\($0.name): \(String(format: "%.0f", $0.value))/5" }
                y = drawPDFSection("Sintomas personalizados", lines: customSymptomLines.isEmpty ? ["Nenhum sintoma personalizado cadastrado."] : customSymptomLines, x: margin, y: y + 10, width: width)

                let checkInLines = sortedCheckIns.prefix(8).map {
                    "\($0.date.formatted(date: .numeric, time: .omitted)): humor \(String(format: "%.1f", $0.mood)), ansiedade \(String(format: "%.1f", $0.anxiety)), sono \(String(format: "%.1f", $0.sleepHours))h"
                }
                y = drawPDFSection("Registros recentes", lines: checkInLines.isEmpty ? ["Nenhum registro salvo."] : checkInLines, x: margin, y: y + 10, width: width)

                let disclaimer = "Análise automatizada de apoio. Este relatório não substitui julgamento médico, atendimento emergencial ou validação clínica formal."
                _ = drawPDFSection("Observação", lines: [disclaimer], x: margin, y: y + 10, width: width)
            }
            return url
        } catch {
            return nil
        }
    }

    func monthlyPDFLines() -> [String] {
        MonthlyReportSummary.lines(for: sortedCheckIns)
    }

    func drawPDFTrendChart(x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) -> CGFloat {
        drawPDFText("Evolução visual recente", in: CGRect(x: x, y: y, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        let chartY = y + 28
        let chartHeight: CGFloat = 76
        let entries = Array(sortedCheckIns.prefix(7).reversed())
        guard !entries.isEmpty else {
            drawPDFText("Sem dados suficientes para gráfico.", in: CGRect(x: x, y: chartY, width: width, height: 24), font: .systemFont(ofSize: 11), color: .darkGray)
            return chartY + 34
        }

        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.stroke(CGRect(x: x, y: chartY, width: width, height: chartHeight))

        let barWidth = max(12, (width - CGFloat(entries.count - 1) * 8) / CGFloat(entries.count))
        for (index, entry) in entries.enumerated() {
            let barX = x + CGFloat(index) * (barWidth + 8)
            let moodHeight = CGFloat(entry.mood / 5) * chartHeight
            UIColor.neuroGold.setFill()
            context.fill(CGRect(x: barX, y: chartY + chartHeight - moodHeight, width: barWidth, height: moodHeight))
        }

        drawPDFText("Barras amarelas: humor recente de 1 a 5.", in: CGRect(x: x, y: chartY + chartHeight + 6, width: width, height: 18), font: .systemFont(ofSize: 10), color: .darkGray)
        return chartY + chartHeight + 28
    }

    func drawPDFSection(_ title: String, lines: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var currentY = y
        drawPDFText(title, in: CGRect(x: x, y: currentY, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        currentY += 24

        for line in lines {
            let rect = CGRect(x: x, y: currentY, width: width, height: 36)
            drawPDFText("• \(line)", in: rect, font: .systemFont(ofSize: 11), color: .darkGray)
            currentY += 28
        }

        return currentY
    }

    func drawPDFText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    func enqueueSyncItem<T: Codable>(kind: OfflineSyncKind, payload: T, summary: String) {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            lastSyncStatus = "Salvo apenas no aparelho."
            return
        }

        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            lastSyncStatus = "Não foi possível preparar sincronização pendente."
            return
        }

        guard !offlineSyncQueue.contains(where: { $0.kind == kind && $0.payloadJSON == json }) else {
            lastSyncStatus = "\(offlineSyncQueue.count) item(ns) pendente(s)"
            return
        }
        offlineSyncQueue.append(OfflineSyncItem(kind: kind, payloadJSON: json, summary: summary))
        persistOfflineSyncQueue()
        lastSyncStatus = "\(offlineSyncQueue.count) item(ns) pendente(s)"
    }

    @MainActor
    func retryPendingSync() {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            if !offlineSyncQueue.isEmpty || !offlineSyncQueueData.isEmpty {
                offlineSyncQueue = []
                offlineSyncQueueData = ""
            }
            lastSyncStatus = "Modo local ativo: dados apenas no aparelho."
            isRetryingPendingSync = false
            return
        }
        guard !authToken.isEmpty else {
            lastSyncStatus = "Entre na conta para sincronizar pendências."
            return
        }
        guard !isRetryingPendingSync else {
            lastSyncStatus = "Sincronização pendente já em andamento."
            return
        }
        guard !offlineSyncQueue.isEmpty else {
            lastSyncStatus = "Tudo sincronizado."
            return
        }

        let queuedItems = offlineSyncQueue
        let queuedIDs = Set(queuedItems.map(\.id))
        let token = authToken
        isRetryingPendingSync = true
        lastSyncStatus = "Sincronizando \(queuedItems.count) item(ns) pendente(s)..."
        Task {
            var failedIDs = Set<UUID>()
            let decoder = JSONDecoder()

            for item in queuedItems {
                do {
                    guard let data = item.payloadJSON.data(using: .utf8) else {
                        continue
                    }

                    switch item.kind {
                    case .checkIn:
                        let payload = try decoder.decode(BackendDailyCheckInPayload.self, from: data)
                        try await BackendAuthClient.createCheckIn(payload, token: token)
                    case .assessment:
                        let payload = try decoder.decode(BackendScaleAssessmentPayload.self, from: data)
                        try await BackendAuthClient.createAssessment(payload, token: token)
                    case .report:
                        let payload = try decoder.decode(BackendClinicalReportPayload.self, from: data)
                        try await BackendAuthClient.createReport(payload, token: token)
                    }
                } catch {
                    failedIDs.insert(item.id)
                }
            }

            await MainActor.run {
                offlineSyncQueue = offlineSyncQueue.filter { item in
                    !queuedIDs.contains(item.id) || failedIDs.contains(item.id)
                }
                persistOfflineSyncQueue()
                isRetryingPendingSync = false
                lastSyncStatus = offlineSyncQueue.isEmpty ? "Tudo sincronizado." : "\(offlineSyncQueue.count) item(ns) ainda pendente(s)."
            }
        }
    }

    func syncCheckInWithBackend(_ payload: BackendDailyCheckInPayload) {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            lastSyncStatus = "Salvo apenas no aparelho."
            saveStatusMessage = "Registro salvo apenas no aparelho."
            return
        }
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .checkIn, payload: payload, summary: "Registro diário")
            saveStatusMessage = "Registro salvo localmente. Entre na conta para sincronizar."
            return
        }

        Task {
            do {
                try await BackendAuthClient.createCheckIn(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "Registro sincronizado."
                    saveStatusMessage = "Registro salvo e sincronizado."
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .checkIn, payload: payload, summary: "Registro diário")
                    saveStatusMessage = "Registro salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                }
            }
        }
    }

    func syncAssessmentWithBackend(scaleName: String, answers: [Int], score: Int, interpretation: String) {
        let payload = BackendScaleAssessmentPayload(scaleName: scaleName, answers: answers, score: score, interpretation: interpretation)
        guard DataResidencyPolicy.remoteSyncEnabled else {
            lastSyncStatus = "Salvo apenas no aparelho."
            scaleStatusMessage = "\(scaleName) salvo apenas no aparelho."
            return
        }
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .assessment, payload: payload, summary: scaleName)
            scaleStatusMessage = "\(scaleName) salvo localmente. Entre na conta para sincronizar."
            return
        }

        Task {
            do {
                try await BackendAuthClient.createAssessment(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "\(scaleName) sincronizado."
                    scaleStatusMessage = "\(scaleName) salvo e sincronizado."
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .assessment, payload: payload, summary: scaleName)
                    scaleStatusMessage = "\(scaleName) salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                }
            }
        }
    }

    func syncReportWithBackend(summary: String, riskLevel: String, automaticCareTeamSend: Bool = false) {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            lastSyncStatus = "Salvo apenas no aparelho."
            reportStatusMessage = "Relatório salvo apenas no aparelho."
            if automaticCareTeamSend {
                careTeamSendStatus = "Modo local ativo: envio automático desativado."
            }
            return
        }
        let payload = BackendClinicalReportPayload(
            riskLevel: riskLevel,
            summary: summary,
            autoSend: automaticCareTeamSend,
            careTeamContact: automaticCareTeamSend ? careTeamContact : nil,
            apnsToken: automaticCareTeamSend ? apnsDeviceToken : nil
        )
        guard !authToken.isEmpty else {
            enqueueSyncItem(kind: .report, payload: payload, summary: "Relatório")
            reportStatusMessage = "Relatório salvo localmente. Entre na conta para sincronizar."
            if automaticCareTeamSend {
                careTeamSendStatus = "Relatório ficou pendente até entrar na conta."
            }
            return
        }

        Task {
            do {
                try await BackendAuthClient.createReport(payload, token: authToken)
                await MainActor.run {
                    lastSyncStatus = "Relatório sincronizado."
                    reportStatusMessage = "Relatório sincronizado."
                    if automaticCareTeamSend {
                        let target = careTeamContact.isEmpty ? "médico/cuidador vinculado" : careTeamContact
                        careTeamSendStatus = "Relatório enviado para \(target)."
                    }
                }
            } catch {
                await MainActor.run {
                    enqueueSyncItem(kind: .report, payload: payload, summary: "Relatório")
                    reportStatusMessage = "Relatório salvo localmente. Falha ao sincronizar: \(error.localizedDescription)"
                    if automaticCareTeamSend {
                        careTeamSendStatus = "Envio pendente. O app tentará sincronizar depois."
                    }
                }
            }
        }
    }

    @MainActor
    func handleAuthenticationButton() async {
        if isLoggedIn {
            logout()
        } else if isCreatingAccount {
            await register()
        } else {
            await login()
        }
    }

    @MainActor
    func login() async {
        isAuthenticating = true
        loginStatusMessage = ""

        do {
            let response = try await BackendAuthClient.login(email: loginEmail, password: loginPassword)
            authToken = response.accessToken
            refreshToken = response.refreshToken
            authenticatedEmail = response.user.email
            authenticatedName = response.user.fullName
            authenticatedRole = response.user.role
            authenticatedUserId = response.user.id
            loginPassword = ""
            applyRole(from: response.user.role)
            await loadCaregivers()
            await syncMyBackendAlerts()
            await loadPendingInvites()
            await loadLinkedClinicians()
            await loadClinicianSentInvites()
            loginStatusMessage = "Login realizado com sucesso."
        } catch {
            loginStatusMessage = error.localizedDescription
        }

        isAuthenticating = false
    }

    @MainActor
    func register() async {
        isAuthenticating = true
        loginStatusMessage = ""

        do {
            // Backend self-service signup always creates a patient account.
            // Clinician promotion is gated behind the admin endpoint.
            let response = try await BackendAuthClient.register(email: loginEmail, password: loginPassword, fullName: fullName)
            authToken = response.accessToken
            refreshToken = response.refreshToken
            authenticatedEmail = response.user.email
            authenticatedName = response.user.fullName
            authenticatedRole = response.user.role
            authenticatedUserId = response.user.id
            loginPassword = ""
            isCreatingAccount = false
            applyRole(from: response.user.role)
            await loadCaregivers()
            await syncMyBackendAlerts()
            await loadPendingInvites()
            await loadLinkedClinicians()
            await loadClinicianSentInvites()
            loginStatusMessage = "Conta criada e conectada."
        } catch {
            loginStatusMessage = error.localizedDescription
        }

        isAuthenticating = false
    }

    /// Sheet pós-save (Sprint 23): oferece, sem fricção, espaço pra
    /// acrescentar um pensamento ou contexto ao check-in que acabou de
    /// ser gravado.
    var postSaveThoughtSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $postSaveThought)
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("Algo passou pela sua cabeça hoje?")
                } footer: {
                    Text("Opcional. Vai ser anexado ao registro que você acabou de salvar.")
                }
                Section {
                    Button {
                        appendThoughtToLatestCheckIn()
                        isShowingPostSavePrompt = false
                        postSaveThought = ""
                    } label: {
                        Label("Adicionar", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(postSaveThought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Registro salvo ✓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pular") {
                        isShowingPostSavePrompt = false
                        postSaveThought = ""
                    }
                }
            }
        }
    }

    @MainActor
    func appendThoughtToLatestCheckIn() {
        guard let latest = sortedCheckIns.first else { return }
        let trimmed = postSaveThought.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let prefix = latest.journalEntry.isEmpty ? "" : latest.journalEntry + "\n\n"
        latest.journalEntry = prefix + trimmed
        do {
            try modelContext.save()
        } catch {
            saveStatusMessage = "Não foi possível salvar o registro: \(error.localizedDescription)"
        }
    }

    var passwordResetConfirmSheet: some View {
        NavigationStack {
            Form {
                Section("E-mail") {
                    TextField("E-mail", text: $loginEmail)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Section {
                    TextField("Cole aqui o código", text: $passwordResetCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Código recebido por e-mail")
                } footer: {
                    Text("O código expira em 30 minutos e pode ser usado uma única vez.")
                }

                Section {
                    SecureField("Nova senha (mínimo 8)", text: $passwordResetNewPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("Nova senha")
                }

                if !passwordResetStatusMessage.isEmpty {
                    Label(passwordResetStatusMessage, systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await confirmPasswordReset() }
                    } label: {
                        HStack {
                            if isConfirmingPasswordReset { ProgressView().controlSize(.small) }
                            Text(isConfirmingPasswordReset ? "Confirmando..." : "Definir nova senha")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isConfirmingPasswordReset
                        || loginEmail.isEmpty
                        || passwordResetCode.count < 8
                        || passwordResetNewPassword.count < 8
                    )
                }
            }
            .navigationTitle("Redefinir senha")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") {
                        isShowingPasswordResetConfirm = false
                        passwordResetCode = ""
                        passwordResetNewPassword = ""
                    }
                }
            }
        }
    }

    @MainActor
    func confirmPasswordReset() async {
        isConfirmingPasswordReset = true
        defer { isConfirmingPasswordReset = false }
        do {
            let message = try await BackendAuthClient.confirmPasswordReset(
                email: loginEmail,
                resetCode: passwordResetCode,
                newPassword: passwordResetNewPassword
            )
            passwordResetCode = ""
            passwordResetNewPassword = ""
            isShowingPasswordResetConfirm = false
            loginStatusMessage = message
        } catch {
            passwordResetStatusMessage = "Falha: \(error.localizedDescription)"
        }
    }

    @MainActor
    func requestPasswordReset() async {
        isRequestingPasswordReset = true
        loginStatusMessage = ""

        do {
            loginStatusMessage = try await BackendAuthClient.requestPasswordReset(email: loginEmail)
        } catch {
            loginStatusMessage = "Não foi possível solicitar recuperação: \(error.localizedDescription)"
        }

        isRequestingPasswordReset = false
    }

    func logout() {
        // Best-effort: revoke refresh token on the backend so a stolen access
        // token can be cut short. Failures don't block local cleanup — user
        // may be offline. The access token expires anyway within 2h.
        if !refreshToken.isEmpty && !authToken.isEmpty {
            let pendingRefresh = refreshToken
            let pendingAccess = authToken
            Task {
                try? await BackendAuthClient.logout(refreshToken: pendingRefresh, accessToken: pendingAccess)
            }
        }

        authToken = ""
        refreshToken = ""
        apnsDeviceToken = ""
        authenticatedEmail = ""
        authenticatedName = ""
        authenticatedRole = ""
        authenticatedUserId = 0
        loginStatusMessage = "Sessão encerrada."
        loginPassword = ""

        // Clear cached clinical data so the next user on the same device
        // never sees the previous account's information.
        medicationPlansData = ""
        customSymptomsData = ""
        offlineSyncQueueData = ""
        // S15/C1: delete the protected backup file so PHI from the previous
        // session is never accessible to whoever logs in next on this device.
        try? FileManager.default.removeItem(at: BackupStore.protectedFileURL)
        backupURL = nil
        medicationPlans = []
        customSymptoms = []
        offlineSyncQueue = []
        remoteCaregivers = []
        clinicianPatients = []
        selectedRemotePatient = nil
        remoteCheckIns = []
        remoteAssessments = []
        remoteAlerts = []
        remoteReports = []
        pendingClinicianInvites = []
        // Sprint A: drafts encriptados (mood/anxiety/journal/safetyContact etc.)
        // ainda ficavam no DraftStore após logout — PHI do usuário A visível
        // ao usuário B no mesmo device. Limpa tudo no logout e no listener
        // de sessionExpired.
        clearAllLocalPHIDrafts()
    }

    /// Sprint A: limpa todos os @EncryptedDraft + safetyStatus. Chamado em
    /// `logout()` e no listener `.neuremiaSessionExpired` para garantir que
    /// PHI do usuário anterior não vaza para o próximo login no mesmo device.
    /// Setar a property re-escreve ciphertext com o defaultValue (não vaza
    /// PHI) e também limpa o @State cached em memória do EncryptedDraft.
    func clearAllLocalPHIDrafts() {
        mood = 3.0
        anxiety = 2.0
        energy = 3.0
        irritability = 1.0
        sleepHours = 7.0
        appetite = 3.0
        libido = 0.0  // 0 = "Não se aplica" (P2-7)
        sideEffects = ""
        automaticThoughts = ""
        journalEntry = ""
        safetyContact = ""
        safetyWarningSigns = ""
        safetyStrategies = ""
        safetyStatus = .safe
    }

    @MainActor
    func loadClinicianSentInvites() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            clinicianSentInvites = []
            withAnimation { clinicianSentInvitesFlash = "Modo local ativo: convites remotos desativados." }
            return
        }
        guard !authToken.isEmpty, activeRole == .clinician else { return }
        isLoadingClinicianSentInvites = true
        defer { isLoadingClinicianSentInvites = false }
        do {
            clinicianSentInvites = try await BackendAuthClient.clinicianSentInvites(token: authToken)
            withAnimation { clinicianSentInvitesFlash = "Lista atualizada." }
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { clinicianSentInvitesFlash = "" }
            }
        } catch {
            withAnimation { clinicianSentInvitesFlash = "Falha ao atualizar: \(error.localizedDescription)" }
        }
    }

    @MainActor
    func loadLinkedClinicians() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            linkedClinicians = []
            linkedCliniciansStatusMessage = "Modo local ativo: vínculos remotos desativados."
            return
        }
        guard !authToken.isEmpty, activeRole == .patient else { return }
        do {
            linkedClinicians = try await BackendAuthClient.linkedClinicians(token: authToken)
        } catch {
            linkedCliniciansStatusMessage = "Falha ao carregar profissionais vinculados: \(error.localizedDescription)"
        }
    }

    @MainActor
    func revokeClinicalAccess(_ clinician: BackendLinkedClinician) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            linkedClinicians.removeAll { $0.clinicianId == clinician.clinicianId }
            linkedCliniciansStatusMessage = "Modo local ativo: vínculo removido apenas da lista local."
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            try await BackendAuthClient.revokeClinicalAccess(clinicianId: clinician.clinicianId, token: authToken)
            linkedCliniciansStatusMessage = "Acesso de \(clinician.clinicianFullName) cancelado."
            await loadLinkedClinicians()
        } catch {
            linkedCliniciansStatusMessage = "Falha ao cancelar acesso: \(error.localizedDescription)"
        }
    }

    @MainActor
    func reportContentProblem(context: String, clinician: BackendLinkedClinician? = nil) {
        let clinicianDetails: String
        if let clinician {
            clinicianDetails = """
            Profissional: \(clinician.clinicianFullName)
            E-mail do profissional: \(clinician.clinicianEmail)
            ID do profissional: \(clinician.clinicianId)
            """
        } else {
            clinicianDetails = "Profissional: não informado"
        }

        let body = """
        Descreva o problema aqui. Evite incluir textos do diário, dados clínicos sensíveis ou informações de terceiros.

        Contexto: \(context)
        Usuário: \(authenticatedEmail.isEmpty ? "não autenticado" : authenticatedEmail)
        ID do usuário: \(authenticatedUserId == 0 ? "não informado" : "\(authenticatedUserId)")
        \(clinicianDetails)
        Versão legal aceita: \(legalAcceptedVersion.isEmpty ? "não aceita" : legalAcceptedVersion)
        """

        guard let url = AppSupportContact.reportURL(
            subject: "Denúncia de conteúdo ou conduta - Neuremia",
            body: body
        ) else {
            privacyStatusMessage = "Não foi possível preparar o e-mail de denúncia."
            return
        }

        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in
                    privacyStatusMessage = "Não foi possível abrir o e-mail. Contate \(AppSupportContact.email)."
                }
            }
        }
    }

    @MainActor
    func loadPendingInvites() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            pendingClinicianInvites = []
            return
        }
        guard !authToken.isEmpty,
              activeRole == .patient else {
            return
        }
        do {
            pendingClinicianInvites = try await BackendAuthClient.pendingInvites(token: authToken)
        } catch {
            // Silent: banner just stays empty.
        }
    }

    @MainActor
    func acceptInvite(_ invite: BackendClinicianInvite) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            inviteStatusMessage = "Modo local ativo: aceite de convite remoto desativado."
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            _ = try await BackendAuthClient.acceptInvite(id: invite.id, token: authToken)
            inviteStatusMessage = "\(invite.clinicianFullName) agora acompanha você."
            await loadPendingInvites()
            await loadLinkedClinicians()
        } catch {
            inviteStatusMessage = "Falha ao aceitar convite: \(error.localizedDescription)"
        }
    }

    @MainActor
    func revokeInvite(_ invite: BackendClinicianInvite) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            pendingClinicianInvites.removeAll { $0.id == invite.id }
            inviteStatusMessage = "Modo local ativo: convite removido apenas da lista local."
            return
        }
        guard !authToken.isEmpty else { return }
        do {
            _ = try await BackendAuthClient.revokeInvite(id: invite.id, token: authToken)
            inviteStatusMessage = "Convite de \(invite.clinicianFullName) recusado."
            await loadPendingInvites()
        } catch {
            inviteStatusMessage = "Falha ao recusar convite: \(error.localizedDescription)"
        }
    }

    func applyRole(from backendRole: String) {
        let role: AccessRole = backendRole == "clinician" ? .clinician : .patient
        let patient = ensurePatient()
        patient.activeRole = role.rawValue
        // Do not overwrite consent decisions made by the user. Consent is a
        // separate, explicit action and forcing it here violates LGPD.
    }

    @MainActor
    func linkPatientAndReload() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            clinicianPatientStatusMessage = "Modo local ativo: vínculo remoto médico-paciente desativado."
            return
        }
        guard !authToken.isEmpty else {
            clinicianPatientStatusMessage = "Entre como médico para vincular pacientes."
            return
        }

        do {
            let invite = try await BackendAuthClient.inviteClinicianAccess(patientEmail: patientLinkEmail, token: authToken)
            patientLinkEmail = ""
            clinicianPatientStatusMessage = "Convite enviado ao paciente (status: \(invite.status)). O vínculo só é criado após o aceite."
            await loadClinicianPatients()
            await loadClinicianSentInvites()
        } catch {
            clinicianPatientStatusMessage = "Falha ao convidar paciente: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadClinicianPatients() async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            clinicianPatients = []
            remoteClinicalTasks = []
            remoteModelValidationReport = nil
            clinicianPatientStatusMessage = "Modo local ativo: painel remoto desativado."
            return
        }
        guard !authToken.isEmpty else {
            clinicianPatientStatusMessage = "Entre como médico para carregar pacientes."
            return
        }

        do {
            clinicianPatients = try await BackendAuthClient.clinicianPatients(token: authToken)
            async let tasks = BackendAuthClient.clinicalTasks(token: authToken)
            async let validation = BackendAuthClient.modelValidationReport(token: authToken)
            remoteClinicalTasks = (try? await tasks) ?? []
            remoteModelValidationReport = try? await validation
            clinicianPatientsLastLoaded = Date()
            clinicianPatientStatusMessage = clinicianPatients.isEmpty ? "Nenhum paciente vinculado." : "\(clinicianPatients.count) paciente(s) carregado(s)."
        } catch {
            clinicianPatientStatusMessage = "Falha ao carregar pacientes: \(error.localizedDescription)"
        }
    }

    @MainActor
    func loadRemotePatientData(_ patient: BackendUser) async {
        func clearRemotePatientClinicalData() {
            remoteCheckIns = []
            remoteAssessments = []
            remoteAlerts = []
            remoteReports = []
            remotePatientClinicalTasks = []
        }

        guard DataResidencyPolicy.remoteSyncEnabled else {
            selectedRemotePatient = nil
            clearRemotePatientClinicalData()
            remotePatientStatusMessage = "Modo local ativo: dados remotos de pacientes desativados."
            return
        }
        guard !authToken.isEmpty else {
            selectedRemotePatient = nil
            clearRemotePatientClinicalData()
            remotePatientStatusMessage = "Entre como médico para ver dados remotos."
            return
        }
        guard clinicianPatients.contains(where: { $0.id == patient.id }) else {
            selectedRemotePatient = nil
            clearRemotePatientClinicalData()
            remotePatientStatusMessage = "Paciente não está na lista vinculada a este médico."
            return
        }

        let loadID = UUID()
        remotePatientLoadID = loadID
        selectedRemotePatient = patient
        clearRemotePatientClinicalData()
        remotePatientStatusMessage = "Carregando dados de \(patient.fullName)..."
        remotePatientSubTab = .overview
        isLoadingRemotePatientData = true
        defer {
            if remotePatientLoadID == loadID {
                isLoadingRemotePatientData = false
            }
        }

        do {
            async let checkIns = BackendAuthClient.patientCheckIns(patientId: patient.id, token: authToken)
            async let assessments = BackendAuthClient.patientAssessments(patientId: patient.id, token: authToken)
            async let alerts = BackendAuthClient.patientAlerts(patientId: patient.id, token: authToken)
            async let reports = BackendAuthClient.patientReports(patientId: patient.id, token: authToken)
            async let tasks = BackendAuthClient.clinicalTasks(patientId: patient.id, token: authToken)

            let loadedCheckIns = try await checkIns
            let loadedAssessments = try await assessments
            let loadedAlerts = try await alerts
            let loadedReports = try await reports
            let loadedTasks = (try? await tasks) ?? []
            guard remotePatientLoadID == loadID, selectedRemotePatient?.id == patient.id else { return }
            remoteCheckIns = loadedCheckIns
            remoteAssessments = loadedAssessments
            remoteAlerts = loadedAlerts
            remoteReports = loadedReports
            remotePatientClinicalTasks = loadedTasks
            remotePatientStatusMessage = "Dados remotos carregados para \(patient.fullName)."
        } catch {
            guard remotePatientLoadID == loadID, selectedRemotePatient?.id == patient.id else { return }
            clearRemotePatientClinicalData()
            remotePatientStatusMessage = "Falha ao carregar dados do paciente: \(error.localizedDescription)"
        }
    }

    @MainActor
    func updateRemoteAlertWorkflow(_ alert: BackendClinicalAlert, status: String, contactStatus: String? = nil, snoozedDays: Int? = nil, resolutionNote: String? = nil) async {
        guard DataResidencyPolicy.remoteSyncEnabled else {
            clinicalWorkflowStatusMessage = "Modo local ativo: workflow remoto desativado."
            return
        }
        guard !authToken.isEmpty else {
            clinicalWorkflowStatusMessage = "Entre como médico para atualizar o workflow."
            return
        }

        let snoozedUntil = snoozedDays.flatMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }.map { ISO8601DateFormatter().string(from: $0) }

        let payload = BackendClinicalAlertWorkflowPayload(
            status: status,
            assignedClinicianId: nil,
            snoozedUntil: snoozedUntil,
            contactStatus: contactStatus,
            resolutionNote: resolutionNote
        )

        do {
            let updated = try await BackendAuthClient.updateClinicalAlertWorkflow(alertId: alert.id, payload: payload, token: authToken)
            remoteAlerts = remoteAlerts.map { $0.id == updated.id ? updated : $0 }
            if let patient = selectedRemotePatient {
                remotePatientClinicalTasks = (try? await BackendAuthClient.clinicalTasks(patientId: patient.id, token: authToken)) ?? remotePatientClinicalTasks
            }
            remoteClinicalTasks = (try? await BackendAuthClient.clinicalTasks(token: authToken)) ?? remoteClinicalTasks
            clinicalWorkflowStatusMessage = "Workflow atualizado: \(status)."
        } catch {
            clinicalWorkflowStatusMessage = "Falha ao atualizar workflow: \(error.localizedDescription)"
        }
    }
}

// MARK: - B1: PDF renderer extracted from ContentView so it can run off the main actor

/// All PDF rendering work in one `nonisolated` type.
/// Call `PDFReportRenderer.render(...)` from any `Task.detached` block —
/// no MainActor involvement until the resulting URL is handed back.
struct PDFReportRenderer {
    nonisolated static func render(
        text: String,
        checkIns: [DailyCheckIn],
        assessments: [ScaleAssessment],
        medications: [MedicationPlanEntry],
        symptoms: [CustomSymptomEntry],
        summary: LongitudinalSummary
    ) async -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "neuremia-relatorio.pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                let margin: CGFloat = 36
                var y = margin
                let width = pageRect.width - margin * 2

                drawText("Neuremia", in: CGRect(x: margin, y: y, width: width, height: 34), font: .boldSystemFont(ofSize: 24), color: .black)
                y += 34
                drawText("Relatório para consulta", in: CGRect(x: margin, y: y, width: width, height: 22), font: .systemFont(ofSize: 14), color: .darkGray)
                y += 30

                UIColor.neuroGold.setFill()
                context.cgContext.fill(CGRect(x: margin, y: y, width: width, height: 3))
                y += 18

                let summaryLines = [
                    "Gerado em: \(Date().formatted(date: .abbreviated, time: .shortened))",
                    "Risco atual: \(summary.riskLevel.rawValue)",
                    "Registros analisados: \(summary.analyzedCheckInCount)",
                    "Sono médio: \(String(format: "%.1f", summary.averageSleep))h",
                    "Adesão medicamentosa: \(String(format: "%.0f", summary.medicationAdherence * 100))%"
                ]

                y = drawSection("Resumo", lines: summaryLines, x: margin, y: y, width: width)
                y = drawTrendChart(checkIns: checkIns, x: margin, y: y + 8, width: width, context: context.cgContext)
                y = drawSection("Sinais recentes", lines: summary.signals, x: margin, y: y + 10, width: width)

                let scaleLines = assessments.prefix(6).map { "\($0.scaleName): \($0.score) pontos - \($0.interpretation)" }
                y = drawSection("Escalas", lines: scaleLines.isEmpty ? ["Nenhuma escala salva."] : Array(scaleLines), x: margin, y: y + 10, width: width)

                y = drawSection("Resumo mensal", lines: MonthlyReportSummary.lines(for: checkIns), x: margin, y: y + 10, width: width)

                let medicationLines = medications.map { plan in
                    [plan.name, plan.dose, plan.schedule, plan.prescription, plan.changeNote]
                        .filter { !$0.isEmpty }.joined(separator: " • ")
                }
                y = drawSection("Medicações", lines: medicationLines.isEmpty ? ["Nenhum medicamento cadastrado."] : medicationLines, x: margin, y: y + 10, width: width)

                let customSymptomLines = symptoms.map { "\($0.name): \(String(format: "%.0f", $0.value))/5" }
                y = drawSection("Sintomas personalizados", lines: customSymptomLines.isEmpty ? ["Nenhum sintoma personalizado cadastrado."] : customSymptomLines, x: margin, y: y + 10, width: width)

                let checkInLines = checkIns.prefix(8).map {
                    "\($0.date.formatted(date: .numeric, time: .omitted)): humor \(String(format: "%.1f", $0.mood)), ansiedade \(String(format: "%.1f", $0.anxiety)), sono \(String(format: "%.1f", $0.sleepHours))h"
                }
                y = drawSection("Registros recentes", lines: checkInLines.isEmpty ? ["Nenhum registro salvo."] : Array(checkInLines), x: margin, y: y + 10, width: width)

                _ = drawSection("Observação", lines: [
                    "Análise automatizada de apoio. Este relatório não substitui julgamento médico, atendimento emergencial ou validação clínica formal."
                ], x: margin, y: y + 10, width: width)
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]).draw(in: rect)
    }

    @discardableResult
    private static func drawSection(_ title: String, lines: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var cy = y
        drawText(title, in: CGRect(x: x, y: cy, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        cy += 24
        for line in lines {
            drawText("• \(line)", in: CGRect(x: x, y: cy, width: width, height: 36), font: .systemFont(ofSize: 11), color: .darkGray)
            cy += 28
        }
        return cy
    }

    private static func drawTrendChart(checkIns: [DailyCheckIn], x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) -> CGFloat {
        drawText("Evolução visual recente", in: CGRect(x: x, y: y, width: width, height: 22), font: .boldSystemFont(ofSize: 15), color: .black)
        let chartY = y + 28
        let chartHeight: CGFloat = 76
        let entries = Array(checkIns.prefix(7).reversed())
        guard !entries.isEmpty else {
            drawText("Sem dados suficientes para gráfico.", in: CGRect(x: x, y: chartY, width: width, height: 24), font: .systemFont(ofSize: 11), color: .darkGray)
            return chartY + 34
        }
        let barWidth = min(width / CGFloat(entries.count) - 6, 36)
        context.setFillColor(UIColor.neuroGold.cgColor)
        for (i, entry) in entries.enumerated() {
            let barH = CGFloat(entry.mood / 5.0) * chartHeight
            let bx = x + CGFloat(i) * (barWidth + 6)
            let by = chartY + chartHeight - barH
            context.fill(CGRect(x: bx, y: by, width: barWidth, height: barH))
        }
        drawText("Barras amarelas: humor recente de 1 a 5.", in: CGRect(x: x, y: chartY + chartHeight + 6, width: width, height: 18), font: .systemFont(ofSize: 10), color: .darkGray)
        return chartY + chartHeight + 28
    }
}
