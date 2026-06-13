//
//  ContentView.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import UniformTypeIdentifiers
import Combine
import Network
#if canImport(HealthKit)
import HealthKit
#endif

// Brand colors are defined in BrandColors.swift (QC1)

// PPGCameraManager moved to BiometricManagers.swift (QC1)
// PPGCameraManager and VoiceSignalManager live in BiometricManagers.swift (QC1)


struct MedicationPlanEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var dose: String
    var schedule: String
    var prescription: String
    var changeNote: String
    var createdAt = Date()

    var summary: String {
        [name, dose, schedule]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

struct CustomSymptomEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var value: Double
    var createdAt = Date()
}

extension Array where Element == BackendUser {
    var sortedByRisk: [BackendUser] {
        sorted { first, second in
            (first.riskScore ?? -1) > (second.riskScore ?? -1)
        }
    }
}

enum OfflineSyncKind: String, Codable {
    case checkIn
    case assessment
    case report
}

struct OfflineSyncItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: OfflineSyncKind
    var payloadJSON: String
    var summary: String
    var createdAt = Date()
}

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Query var patients: [PatientProfile]
    @Query var checkIns: [DailyCheckIn]
    @Query var assessments: [ScaleAssessment]
    @Query var alerts: [ClinicalAlert]
    @Query var reports: [ClinicalReport]
    @StateObject var ppgManager = PPGCameraManager()
    @StateObject var voiceManager = VoiceSignalManager()
    // Sprint E #4: cache central para evitar re-sort + re-summary em cada body.
    // sortedCheckIns/sortedAssessments/summary leem do store quando isReady;
    // o `.task(id:)` no body raiz dispara recompute quando contagens mudam.
    @State var patientStore = PatientStore()

    // Drafts now go through DraftStore: AES-GCM ciphertext in UserDefaults,
    // with the symmetric key kept in the Keychain. Sprint 12 had them in
    // plaintext @AppStorage, which leaked PHI through iCloud Backup of the
    // standard plist (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuroflowDraftMood", defaultValue: 3.0) var mood
    @EncryptedDraft("neuroflowDraftAnxiety", defaultValue: 2.0) var anxiety
    @EncryptedDraft("neuroflowDraftEnergy", defaultValue: 3.0) var energy
    @EncryptedDraft("neuroflowDraftIrritability", defaultValue: 1.0) var irritability
    @EncryptedDraft("neuroflowDraftSleepHours", defaultValue: 7.0) var sleepHours
    @EncryptedDraft("neuroflowDraftAppetite", defaultValue: 3.0) var appetite
    // P2-7: default 0.0 = "Não se aplica" para evitar ruído com valor médio.
    @EncryptedDraft("neuroflowDraftLibido", defaultValue: 0.0) var libido
    @State var medicationStatus = MedicationStatus.taken
    @State var safetyStatus = SafetyStatus.safe
    // Same DraftStore encryption applies to the free-text fields, which are
    // the most sensitive of the bunch (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuroflowDraftSideEffects", defaultValue: "") var sideEffects
    @EncryptedDraft("neuroflowDraftAutomaticThoughts", defaultValue: "") var automaticThoughts
    @EncryptedDraft("neuroflowDraftJournalEntry", defaultValue: "") var journalEntry
    @State var selectedCareFocus = CareFocus.bipolar
    @State var alcoholTrigger = false
    @State var poorSleepTrigger = false
    @State var stressTrigger = false
    @State var conflictTrigger = false
    @State var routineChangeTrigger = false
    @State var menstrualTrigger = false
    @State var customTriggerText = ""
    @State var customTriggers: [String] = []
    @State var selectedScale = ScaleKind.phq9
    @State var scaleAnswers: [ScaleKind: [Int]] = [:]
    @State var reportPreview = ""
    @State var reportPDFURL: URL?
    @State var reportCSVURL: URL?
    @State var backupURL: URL?
    @State var saveStatusMessage = ""
    @State var scaleStatusMessage = ""
    @State var reportStatusMessage = ""
    // P1-2 (UX): sistema central de toasts — substitui as 9 variáveis de
    // status espalhadas. Nível: .error (vermelho, persistente até dismiss),
    // .warning (laranja, 4 s), .success (verde, 2 s).
    @State var toastMessage: String = ""
    @State var toastLevel: ToastLevel = .success
    @State var toastTask: Task<Void, Never>? = nil
    @State var selectedPatientPage = PatientPage.diary
    // M2 (UX-P0): seções recolhíveis do diário — reduz carga cognitiva
    // para pacientes com pouca energia. Todas abertas por padrão.
    @State var diarySection1Expanded = true   // "Como você está?" — aberta por padrão (fluxo mínimo)
    @State var diarySection2Expanded = false  // "Segurança e medicação" — fechada; expande quando necessário
    @State var diarySection3Expanded = false  // "Texto livre e gatilhos" — fechada; expande quando necessário
    // Check-in progressivo: os 4 campos secundários (Energia, Irritabilidade,
    // Apetite, Libido) ficam ocultos até o paciente querer detalhar mais.
    @State var diarySection1DetailsExpanded = false
    // M5 (UX-P0): aba ativa no TabView do clínico
    @State var clinicianTab: ClinicianTab = .patients
    // Sprint A: confirmação antes de aplicar troca de perfil de acesso.
    // Toque acidental no Picker antes mudava a TabView raiz sem aviso.
    @State var roleChangePending: AccessRole?
    // Sprint A: debounce do botão Save. O dayKey @Attribute(.unique) do
    // commit M5 não tolera duas execuções concorrentes do mesmo dia.
    @State var isSavingCheckIn = false
    @State var loginEmail = ""
    @State var loginPassword = ""
    @State var fullName = ""
    @State var isCreatingAccount = false
    @State var isRequestingPasswordReset = false
    @State var patientLinkEmail = ""
    @State var clinicianPatients: [BackendUser] = []
    @State var clinicianPatientsLastLoaded: Date?
    @State var selectedRemotePatient: BackendUser?
    @State var clinicianPatientFilter: ClinicianPatientFilter = .all
    @State var sentInvitesFilter: SentInviteStatusFilter = .all
    @State var remotePatientSubTab: RemotePatientSubTab = .overview
    @State var isLoadingRemotePatientData = false
    @State var evolutionSearchQuery = ""
    @State var evolutionFilter: EvolutionFilter = .all
    @State var isShowingBodySignalsTechnicalDetails = false
    @State var remoteCheckIns: [BackendDailyCheckIn] = []
    @State var remoteAssessments: [BackendScaleAssessment] = []
    @State var remoteAlerts: [BackendClinicalAlert] = []
    @State var remoteReports: [BackendClinicalReport] = []
    @State var caregiverName = ""
    @State var caregiverRelationship = ""
    @State var remoteCaregivers: [BackendCaregiverContact] = []
    @State var clinicianPatientStatusMessage = ""
    @State var remotePatientStatusMessage = ""
    @State var isAuthenticating = false
    @State var loginStatusMessage = ""
    @State var isShowingSettings = false
    @State var isShowingScales = false
    @State var isImportingBackup = false
    @State var medicationPlans: [MedicationPlanEntry] = []
    @State var customSymptoms: [CustomSymptomEntry] = []
    @State var offlineSyncQueue: [OfflineSyncItem] = []
    // queue when connectivity is restored without requiring user interaction.
    @State var networkMonitor = NWPathMonitor()
    @State var networkMonitorQueue = DispatchQueue(label: "io.neuroflow.networkMonitor", qos: .background)
    @State var typingStartedAt: Date?
    @State var bodySignalTypingLatency = 0.0
    @State var bodySignalTypingSpeed = 0.0
    @State var bodySignalInteractionCount = 0
    @State var appSessionStartedAt = Date()
    // B2 — debounce token; cancels the previous pending call before scheduling a new one.
    @State var _typingDebounceTask: Task<Void, Never>?
    @KeychainStored(.authToken) var authToken
    @KeychainStored(.refreshToken) var refreshToken
    // Legacy @AppStorage values are auto-migrated on first launch by
    // KeychainStore.migrateLegacyTokenIfNeeded() (called in AppDelegate).
    @KeychainStored(.userEmail) var authenticatedEmail
    @KeychainStored(.userName) var authenticatedName
    @KeychainStored(.userRole) var authenticatedRole
    @KeychainStored(.userId) var _authenticatedUserIdStr
    var authenticatedUserId: Int {
        get { Int(_authenticatedUserIdStr) ?? 0 }
        nonmutating set { _authenticatedUserIdStr = "\(newValue)" }
    }
    @AppStorage("neuroflowMedicationReminderEnabled") var medicationReminderEnabled = false
    @AppStorage("neuroflowCheckInReminderEnabled") var checkInReminderEnabled = false
    @AppStorage("neuroflowMedicationReminderHour") var medicationReminderHour = 9
    @AppStorage("neuroflowCheckInReminderHour") var checkInReminderHour = 20
    // PHI: medication fields are encrypted at rest via AES-GCM (DraftStore).
    // Legacy @AppStorage values are auto-migrated on first read.
    @EncryptedDraft("neuroflowMedicationName", defaultValue: "") var medicationName
    @EncryptedDraft("neuroflowMedicationDose", defaultValue: "") var medicationDose
    @EncryptedDraft("neuroflowMedicationSchedule", defaultValue: "") var medicationSchedule
    @EncryptedDraft("neuroflowMedicationChangeNote", defaultValue: "") var medicationChangeNote
    @EncryptedDraft("neuroflowMedicationPrescription", defaultValue: "") var medicationPrescription
    @EncryptedDraft("neuroflowMedicationPlansData", defaultValue: "") var medicationPlansData
    @AppStorage("neuroflowCustomSymptomName") var customSymptomName = ""
    @AppStorage("neuroflowCustomSymptomValue") var customSymptomValue = 3.0
    @AppStorage("neuroflowCustomSymptomsData") var customSymptomsData = ""
    @EncryptedDraft("neuroflowSafetyContact", defaultValue: "") var safetyContact
    @EncryptedDraft("neuroflowSafetyWarningSigns", defaultValue: "") var safetyWarningSigns
    @EncryptedDraft("neuroflowSafetyStrategies", defaultValue: "") var safetyStrategies
    @AppStorage("neuroflowNextAppointmentAt") var nextAppointmentAt = Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970
    @AppStorage("neuroflowNextAppointmentNote") var nextAppointmentNote = ""
    @AppStorage("neuroflowAutoMonthlyReportEnabled") var autoMonthlyReportEnabled = false
    @AppStorage("neuroflowAutoBackupEnabled") var autoBackupEnabled = true
    @AppStorage("neuroflowBackupIntervalDays") var backupIntervalDays = 7
    @AppStorage("neuroflowLastAutomaticBackupAt") var lastAutomaticBackupAt = 0.0
    @AppStorage("neuroflowAutoCareTeamSendEnabled") var autoCareTeamSendEnabled = false
    @AppStorage("neuroflowCareTeamContact") var careTeamContact = ""
    @AppStorage("neuroflowCareTeamSendStatus") var careTeamSendStatus = "Envio automático inativo"
    @AppStorage("neuroflowShareWithCaregiver") var shareWithCaregiver = false
    @AppStorage("neuroflowHealthKitEnabled") var healthKitEnabled = false
    @AppStorage("neuroflowHealthKitStatus") var healthKitStatus = "Apple Health não conectado"
    @AppStorage("neuroflowHealthSteps") var healthSteps = 0
    @AppStorage("neuroflowHealthSleepHours") var healthSleepHours = 0.0
    @AppStorage("neuroflowHealthHeartRate") var healthHeartRate = 0.0
    @AppStorage("neuroflowHealthActiveEnergy") var healthActiveEnergy = 0.0
    @AppStorage("neuroflowRemotePushEnabled") var remotePushEnabled = false
    @AppStorage("neuroflowRemotePushStatus") var remotePushStatus = "Push remoto não configurado"
    @KeychainStored(.apnsDeviceToken) var apnsDeviceToken
    @AppStorage("neuroflowBackgroundBackupStatus") var backgroundBackupStatus = "Backup em segundo plano não agendado"
    // lastBackupJSON was removed (S15/C1): PHI must not live in UserDefaults.
    // The backup file is written directly to BackupStore.protectedFileURL.
    @AppStorage("neuroflowOfflineSyncQueueData") var offlineSyncQueueData = ""
    @AppStorage("neuroflowLastSyncStatus") var lastSyncStatus = "Salvo no aparelho"
    @AppStorage("neuroflowBiometricConsentAccepted") var biometricConsentAccepted = false
    @AppStorage("neuroflowPrivacyRetentionDays") var privacyRetentionDays = 365
    @State var privacyStatusMessage = ""
    @State var privacyExportURL: URL?
    @State var isConfirmingClinicalWipe = false
    @State var isConfirmingAccountDelete = false
    @State var isShowingAuditLogs = false
    @State var isShowingTermsOfUse = false
    @State var isShowingPrivacyPolicy = false
    @State var remoteAuditLogs: [BackendAuditLog] = []
    @State var caregiverEditTarget: BackendCaregiverContact?
    @State var caregiverStatusMessage = ""
    @State var caregiverEditName = ""
    @State var caregiverEditContact = ""
    @State var caregiverEditRelationship = ""
    @State var caregiverEditShareEnabled = true
    @State var isSavingCaregiverEdit = false
    @State var pendingClinicianInvites: [BackendClinicianInvite] = []
    @State var inviteStatusMessage = ""
    @State var clinicianSentInvites: [BackendSentInvite] = []
    @State var isLoadingClinicianSentInvites = false
    @State var clinicianSentInvitesFlash = ""
    @State var isShowingSessionExpiredAlert = false
    @State var isShowingPasswordResetConfirm = false
    @State var isShowingCrisisSheet = false
    @State var crisisSheetTab = 0
    @State var isShowingLoginSheet = false
    @State var isShowingPostSavePrompt = false
    @State var postSaveThought = ""
    @AppStorage("neuroflowOnboardingComplete") var hasCompletedOnboarding = false
    @AppStorage("neuroflowMoodCoachmarkSeen") var hasSeenMoodCoachmark = false
    @State var onboardingStep = 0
    /// Version string of the last legal document the user accepted.
    /// Empty = never accepted. Compared against LegalVersion.current to
    /// detect policy updates that require re-acceptance (LGPD Art. 7 I).
    @AppStorage("neuroflowLegalAcceptedVersion") var legalAcceptedVersion = ""
    /// True when the legal consent gate should be shown (first launch or
    /// after a policy update).
    var needsLegalAcceptance: Bool { legalAcceptedVersion != LegalVersion.current }
    /// Timestamp (timeIntervalSince1970) até quando o banner de convite fica
    /// escondido. Zero quando nunca foi adiado.
    @AppStorage("neuroflowInviteSnoozedUntil") var inviteSnoozedUntil = 0.0
    @State var passwordResetCode = ""
    @State var passwordResetNewPassword = ""
    @State var passwordResetStatusMessage = ""
    @State var isConfirmingPasswordReset = false
    @State var linkedClinicians: [BackendLinkedClinician] = []
    @State var linkedCliniciansStatusMessage = ""
    @State var clinicianToRevoke: BackendLinkedClinician?
    @Environment(\.scenePhase) var scenePhase
    @State var isPrivacyShielded = false

    #if canImport(HealthKit)
    let healthStore = HKHealthStore()
    #endif

    // Sprint E #4: leitura cache-first. Fallback (recomputa) só roda no primeiro
    // frame antes do `.task(id:)` no body popular o store. Resto é O(1).
    var sortedCheckIns: [DailyCheckIn] {
        patientStore.isReady ? patientStore.sortedCheckIns : checkIns.sorted { $0.date > $1.date }
    }

    var sortedAssessments: [ScaleAssessment] {
        patientStore.isReady ? patientStore.sortedAssessments : assessments.sorted { $0.date > $1.date }
    }

    var activeAlerts: [ClinicalAlert] { patientStore.activeAlerts }
    var latestReports: [ClinicalReport] { patientStore.latestReports }

    // Sprint 25: query normalizada para casamento "contém" insensível a caixa.
    var evolutionQueryNormalized: String {
        evolutionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    func evolutionMatches(_ haystacks: [String]) -> Bool {
        let query = evolutionQueryNormalized
        guard !query.isEmpty else { return true }
        return haystacks.contains { $0.localizedLowercase.contains(query) }
    }

    var filteredCheckIns: [DailyCheckIn] {
        sortedCheckIns.filter { checkIn in
            evolutionMatches([
                checkIn.journalEntry,
                checkIn.automaticThoughts,
                checkIn.sideEffects,
            ])
        }
    }

    var filteredAssessments: [ScaleAssessment] {
        sortedAssessments.filter { assessment in
            evolutionMatches([assessment.scaleName, assessment.interpretation])
        }
    }

    var filteredActiveAlerts: [ClinicalAlert] {
        activeAlerts.filter { alert in
            evolutionMatches([alert.title, alert.message])
        }
    }

    // Sprint E #4: lê do cache quando isReady. Cai no recompute só no primeiro
    // frame, antes do `.task(id:)` no body rodar `patientStore.recompute`.
    var summary: LongitudinalSummary {
        if let cached = patientStore.summary { return cached }
        return ClinicalAnalysis.summary(checkIns: sortedCheckIns, assessments: sortedAssessments)
    }

    /// Lightweight fingerprint for the fields that drive LongitudinalSummary.
    /// Changes to mood, anxiety, sleep, medication adherence, or any scale
    /// score invalidate the PatientStore cache and trigger a recompute.
    /// Free-text fields (journal, side-effects) are excluded because they
    /// don't affect the computed summary and omitting them keeps this cheap.
    // Sprint A (REG-3): cheap key — apenas contagens dos 4 arrays. O fingerprint
    // pesado (que itera mood/anxiety/sleep/...) só roda dentro de
    // `recomputeStoreFingerprintIfNeeded()` quando count muda. Antes do fix,
    // o `.task(id: storeFingerprint)` chamava o getter em cada body re-eval,
    // disparando um loop O(n) sobre todos os check-ins por render.
    var storeFingerprintCheap: String {
        // N-C3: include the number of acknowledged alerts so that ack-ing an
        // alert fires .task(id:) and patientStore.recompute() removes it from
        // activeAlerts. Without this, acknowledged alerts stay visible until
        // another count-changing event happens.
        let ackedCount = alerts.filter(\.acknowledged).count
        return "\(checkIns.count)-\(assessments.count)-\(alerts.count)-\(ackedCount)-\(reports.count)"
    }

    func computeFullStoreFingerprint() -> String {
        // Sub-expressões nomeadas: a versão original (commit 413f734) juntava
        // tudo em uma única expressão e o type-checker do Swift estourava o
        // limite ("unable to type-check in reasonable time").
        let checkInSignal = checkIns.reduce(into: 0) { acc, c in
            let mood = Int(c.mood * 10)
            let anxiety = Int(c.anxiety * 10)
            let sleep = Int(c.sleepHours * 10)
            let med: Int = c.medicationTaken ? 1 : 0
            let suicidal: Int = c.suicidalIdeation ? 100 : 0
            acc += mood + anxiety + sleep + med + suicidal
        }
        let assessmentSignal = assessments.reduce(0) { $0 + $1.score }
        let alertSignal = alerts.reduce(into: 0) { acc, a in
            acc += a.acknowledged ? 1 : 0
        }
        let reportSignal = reports.count
        return "\(checkIns.count)-\(assessments.count)-\(checkInSignal)-\(assessmentSignal)-\(alerts.count)-\(alertSignal)-\(reportSignal)"
    }

    var selectedScaleAnswers: [Int] {
        scaleAnswers[selectedScale] ?? Array(repeating: 0, count: selectedScale.questions.count)
    }

    var selectedScaleScore: Int {
        ClinicalAnalysis.score(for: selectedScale, answers: selectedScaleAnswers)
    }

    var selectedScaleInterpretation: String {
        ClinicalAnalysis.interpretation(for: selectedScale, score: selectedScaleScore)
    }

    var automaticCheckupResults: [AutomaticScaleResult] {
        ScaleKind.allCases.map { scale in
            let answers = automaticAnswers(for: scale)
            let score = ClinicalAnalysis.score(for: scale, answers: answers)
            return AutomaticScaleResult(
                scale: scale,
                answers: answers,
                score: score,
                interpretation: ClinicalAnalysis.interpretation(for: scale, score: score)
            )
        }
    }

    var neuroFlowRiskSignature: NeuroFlowRiskSignature {
        NeuroFlowRiskSignature.calculate(
            summary: summary,
            checkIns: sortedCheckIns,
            scaleResults: automaticCheckupResults,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggerLabels,
            textAssessment: currentTextAssessment,
            ppgStress: ppgManager.stress,
            ppgQuality: ppgManager.isHeartRatePhysiologicallyValid ? ppgManager.signalQuality : 0,
            voicePauseRatio: voiceManager.pauseRatio,
            typingSpeed: bodySignalTypingSpeed,
            careFocus: selectedCareFocus
        )
    }

    var nextAppointmentDateBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: nextAppointmentAt) },
            set: { nextAppointmentAt = $0.timeIntervalSince1970 }
        )
    }

    var currentTextAssessment: TextRiskAssessment {
        safetyStatus == .urgent
            ? TextRiskAssessment(level: .high, detectedTerms: ["triagem positiva"], explanation: "A triagem estruturada marcou ideação suicida.")
            : ClinicalAnalysis.textAssessment(for: "\(journalEntry) \(automaticThoughts)")
    }

    var activeRole: AccessRole {
        AccessRole(rawValue: patients.first?.activeRole ?? AccessRole.patient.rawValue) ?? .patient
    }

    var canViewClinicianData: Bool {
        activeRole == .clinician && patients.first?.shareWithClinician == true
    }

    var isLoggedIn: Bool {
        !authToken.isEmpty
    }

    var authButtonTitle: String {
        if isAuthenticating {
            return isCreatingAccount ? "Criando..." : "Entrando..."
        }

        if isLoggedIn {
            return "Sair da conta"
        }

        return isCreatingAccount ? "Criar conta" : "Entrar"
    }

    var isAuthButtonDisabled: Bool {
        isAuthenticating || (!isLoggedIn && (loginEmail.isEmpty || loginPassword.isEmpty || (isCreatingAccount && fullName.isEmpty)))
    }

    var isMedicationFullyTaken: Bool {
        medicationStatus == .taken
    }

    var hasCriticalSafetyRisk: Bool {
        safetyStatus == .urgent
    }

    var activeTriggerLabels: [String] {
        var labels: [String] = []
        if alcoholTrigger { labels.append("álcool") }
        if poorSleepTrigger { labels.append("privação de sono") }
        if stressTrigger { labels.append("estresse") }
        if conflictTrigger { labels.append("conflito") }
        if routineChangeTrigger { labels.append("mudança de rotina") }
        if menstrualTrigger { labels.append("ciclo menstrual") }
        labels.append(contentsOf: customTriggers)
        return labels
    }

    var journalEntryWithContext: String {
        var parts: [String] = []
        if !journalEntry.isEmpty {
            parts.append(journalEntry)
        }
        parts.append("Foco de acompanhamento: \(selectedCareFocus.rawValue).")
        if !activeTriggerLabels.isEmpty {
            parts.append("Gatilhos do dia: \(activeTriggerLabels.joined(separator: ", ")).")
        }
        if !medicationName.isEmpty || !medicationDose.isEmpty || !medicationSchedule.isEmpty {
            parts.append("Medicação cadastrada: \(medicationPlanSummary).")
        }
        if !medicationChangeNote.isEmpty {
            parts.append("Mudança de medicação/dose: \(medicationChangeNote).")
        }
        if !medicationPlans.isEmpty {
            let medicationList = medicationPlans.map { $0.summary }.joined(separator: "; ")
            parts.append("Lista de medicamentos: \(medicationList).")
        }
        if !customSymptomName.isEmpty {
            parts.append("Sintoma personalizado: \(customSymptomName) \(String(format: "%.0f", customSymptomValue))/5.")
        }
        if !customSymptoms.isEmpty {
            let symptomList = customSymptoms
                .map { "\($0.name) \(String(format: "%.0f", $0.value))/5" }
                .joined(separator: "; ")
            parts.append("Sintomas personalizados: \(symptomList).")
        }
        return parts.joined(separator: "\n")
    }

    var medicationPlanSummary: String {
        if !medicationPlans.isEmpty {
            return medicationPlans.map(\.summary).joined(separator: "; ")
        }
        return [
            medicationName.isEmpty ? nil : medicationName,
            medicationDose.isEmpty ? nil : medicationDose,
            medicationSchedule.isEmpty ? nil : medicationSchedule
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    var body: some View {
        rootWithLifecycle
            // Legal consent gate — shown before anything else on first launch
            // or after a policy update. interactiveDismissDisabled is set
            // inside LegalConsentView so the user cannot swipe it away.
            .fullScreenCover(isPresented: Binding(
                get: { needsLegalAcceptance },
                set: { _ in }
            )) {
                LegalConsentView {
                    legalAcceptedVersion = LegalVersion.current
                }
            }
            .fullScreenCover(isPresented: shouldShowOnboardingBinding) {
                onboardingFlow
            }
            // Sprint 23: haptic feedback nas ações que importam emocionalmente
            // — save bem-sucedido vibra suave, marcar Urgente alerta, abrir
            // SOS chama a atenção.
            .sensoryFeedback(.success, trigger: saveStatusMessage) { _, newValue in
                newValue.hasPrefix("Registro")
            }
            .sensoryFeedback(.warning, trigger: hasCriticalSafetyRisk) { _, newValue in
                newValue
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isShowingCrisisSheet) { _, newValue in
                newValue
            }
            .sensoryFeedback(.success, trigger: inviteStatusMessage) { _, newValue in
                newValue.contains("aceitou") || newValue.contains("agora acompanha")
            }
            .blur(radius: isPrivacyShielded ? 24 : 0)
            .overlay {
                if isPrivacyShielded {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.white)
                        Text("Tela bloqueada")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPrivacyShielded)
            // P1-2 (UX): toast central — cada variável de status dispara
            // showToast() ao mudar, sem alterar os sites de atribuição.
            .onChange(of: saveStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("erro")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: scaleStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: reportStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: loginStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("não foi possível") || msg.localizedCaseInsensitiveContains("expirada") || msg.localizedCaseInsensitiveContains("erro")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: clinicianPatientStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha") || msg.localizedCaseInsensitiveContains("entre como")
                showToast(msg, level: isErr ? .warning : .success)
            }
            .onChange(of: caregiverStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .onChange(of: linkedCliniciansStatusMessage) { _, msg in
                guard !msg.isEmpty else { return }
                let isErr = msg.localizedCaseInsensitiveContains("falha")
                showToast(msg, level: isErr ? .error : .success)
            }
            .overlay(alignment: .bottom) { toastOverlay }
    }

    @ViewBuilder
    var rootContent: some View {
        if activeRole == .clinician {
            clinicianRoot
        } else {
            patientRoot
        }
    }

    var rootWithSheets: some View {
        rootContent
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    settingsDashboard
                        .scrollContentBackground(.hidden)
                        .background(appBackground)
                        .navigationTitle("Configurações")
                        .toolbar {
                        // SOS continua acessível mesmo dentro de Settings.
                        // Tocar fecha Settings e abre a sheet de crise no
                        // próximo run-loop — evita stacking de sheets.
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingSettings = false
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    isShowingCrisisSheet = true
                                }
                            } label: {
                                Image(systemName: "cross.case.fill")
                            }
                            .tint(.red)
                            .accessibilityLabel("Apoio em crise")
                            .accessibilityHint("Fecha as configurações e abre os contatos de crise.")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") {
                                isShowingSettings = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingPasswordResetConfirm) {
                passwordResetConfirmSheet
            }
            .sheet(isPresented: $isShowingPostSavePrompt) {
                postSaveThoughtSheet
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingLoginSheet) {
                NavigationStack {
                    ScrollView {
                        loginSettingsCard
                            .padding(20)
                    }
                    .background(appBackground)
                    .navigationTitle("Entrar")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fechar") { isShowingLoginSheet = false }
                        }
                    }
                    // Após login bem-sucedido, fecha a sheet automaticamente.
                    .onChange(of: authToken) { _, newValue in
                        if !newValue.isEmpty {
                            isShowingLoginSheet = false
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingCrisisSheet) {
                // S8 (UX): folha de crise unifica leitura do plano e edição.
                // Antes o usuário precisava fechar o SOS, navegar para
                // Ferramentas e encontrar o editor — carga alta exatamente
                // quando a carga cognitiva precisa ser mínima.
                NavigationStack {
                    VStack(spacing: 0) {
                        Picker("", selection: $crisisSheetTab) {
                            Text("Agora").tag(0)
                            Text("Meu plano").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        ScrollView {
                            if crisisSheetTab == 0 {
                                CrisisSupportCard(
                                    safetyContact: safetyContact,
                                    warningSigns: safetyWarningSigns,
                                    strategies: safetyStrategies
                                )
                                .padding(20)
                            } else {
                                SafetyPlanEditorCard(
                                    safetyContact: $safetyContact,
                                    warningSigns: $safetyWarningSigns,
                                    strategies: $safetyStrategies,
                                    signature: neuroFlowRiskSignature,
                                    careFocus: selectedCareFocus
                                )
                                .padding(20)
                            }
                        }
                        .background(appBackground)
                    }
                    .background(appBackground)
                    .navigationTitle("Apoio em crise")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") { isShowingCrisisSheet = false }
                        }
                    }
                }
            }
            .sheet(item: $caregiverEditTarget) { caregiver in
                caregiverEditSheet(for: caregiver)
            }
            .sheet(isPresented: $isShowingScales) {
                NavigationStack {
                    ScrollView {
                        scalesDashboard
                            .padding(20)
                    }
                    .background(appBackground)
                    .navigationTitle("Check-up do bem-estar")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") {
                                isShowingScales = false
                            }
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isImportingBackup, allowedContentTypes: [.json]) { result in
                handleBackupImport(result)
            }
    }

    var rootWithLifecycle: some View {
        rootWithSheets
            // Sprint E #4 + Sprint A (REG-3): id é cheap key (4 contagens). O
            // recompute interno re-compara contra o fingerprint full antes de
            // re-sortar/re-summary. Trade-off: edit de check-in passado sem
            // mudar contagem (raro com SwiftData @Model que normalmente recria
            // arrays) tem latência de uma render até o próximo `count` mudar.
            // Antes (Sonnet I3): id era o fingerprint full → O(n) por re-render.
            .task(id: storeFingerprintCheap) {
                patientStore.recompute(checkIns: checkIns, assessments: assessments, alerts: alerts, reports: reports)
            }
            .onAppear {
                prepareInitialData()
                networkMonitor.pathUpdateHandler = { path in
                    guard path.status == .satisfied else { return }
                    Task { @MainActor in retryPendingSync() }
                }
                networkMonitor.start(queue: networkMonitorQueue)
                if !authToken.isEmpty {
                    Task {
                        await loadCaregivers()
                        await syncMyBackendAlerts()
                        await loadPendingInvites()
                        await loadLinkedClinicians()
                        await loadClinicianSentInvites()
                    }
                }
            }
            .onChange(of: selectedCareFocus) { _, newValue in
                selectedScale = newValue.preferredScale
                ensureAnswers(for: selectedScale)
            }
            .onChange(of: selectedPatientPage) { _, _ in
                bodySignalInteractionCount += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .neuroFlowSessionExpired)) { _ in
                // Backend rejected the refresh token. Surface a global alert
                // and wipe every cached remote artifact so the dashboard
                // never shows the previous patient's PHI to whoever logs in
                // next on the same device.
                loginStatusMessage = "Sessão expirada. Entre novamente."
                authenticatedEmail = ""
                authenticatedName = ""
                authenticatedRole = ""
                authenticatedUserId = 0
                pendingClinicianInvites = []
                clinicianSentInvites = []
                clinicianPatients = []
                selectedRemotePatient = nil
                remoteCheckIns = []
                remoteAssessments = []
                remoteAlerts = []
                remoteReports = []
                remoteCaregivers = []
                remoteAuditLogs = []
                linkedClinicians = []
                // Sprint A: drafts encriptados ainda guardavam mood/anxiety/
                // journal/safetyContact do usuário anterior. Limpa tudo.
                clearAllLocalPHIDrafts()
                isShowingSessionExpiredAlert = true
            }
            .alert("Sessão expirada", isPresented: $isShowingSessionExpiredAlert) {
                Button("Entrar novamente") {
                    // Sprint 22: abre direto a sheet de login dedicada em vez
                    // do Settings inteiro — paciente vai pro formulário em 1
                    // toque, sem ter que rolar nada.
                    isShowingLoginSheet = true
                }
                Button("Mais tarde", role: .cancel) {}
            } message: {
                Text("Sua sessão foi encerrada por inatividade ou por uma ação no servidor. Os dados locais estão preservados. Entre novamente para voltar a sincronizar com o backend.")
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Blur sensitive PHI whenever the app is not actively focused.
                // Protects the clinician dashboard and patient diary from
                // shoulder-surfing in the app switcher and on lock screen.
                isPrivacyShielded = newPhase != .active || Self.activeScreenIsCaptured
            }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                // Screen recording / mirroring engages the privacy shield
                // even while the user keeps the app in the foreground.
                // Closest iOS gets to a 'no screen capture' guarantee
                // without resorting to private APIs (F23).
                if Self.activeScreenIsCaptured {
                    isPrivacyShielded = true
                } else if scenePhase == .active {
                    isPrivacyShielded = false
                }
            }
    }

}
