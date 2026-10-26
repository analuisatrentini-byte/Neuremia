//
//  ContentView.swift
//  Neuremia
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import UniformTypeIdentifiers
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
    @Environment(\.openURL) var openURL
    @Query var patients: [PatientProfile]
    @Query var checkIns: [DailyCheckIn]
    @Query var assessments: [ScaleAssessment]
    @Query var alerts: [ClinicalAlert]
    @Query var reports: [ClinicalReport]
    @Query var recommendationLogs: [DailyRecommendationLog]
    @StateObject var ppgManager = PPGCameraManager()
    @StateObject var voiceManager = VoiceSignalManager()
    // Gamification manager - gamificado (estilo missões e streak) engagement system
    @State var gamificationManager = GamificationManager()
    // Sprint E #4: cache central para evitar re-sort + re-summary em cada body.
    // sortedCheckIns/sortedAssessments/summary leem do store quando isReady;
    // o `.task(id:)` no body raiz dispara recompute quando contagens mudam.
    @State var patientStore = PatientStore()

    // Drafts now go through DraftStore: AES-GCM ciphertext in UserDefaults,
    // with the symmetric key kept in the Keychain. Sprint 12 had them in
    // plaintext @AppStorage, which leaked PHI through iCloud Backup of the
    // standard plist (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuremiaDraftMood", defaultValue: 3.0) var mood
    @EncryptedDraft("neuremiaDraftAnxiety", defaultValue: 2.0) var anxiety
    @EncryptedDraft("neuremiaDraftEnergy", defaultValue: 3.0) var energy
    @EncryptedDraft("neuremiaDraftIrritability", defaultValue: 1.0) var irritability
    @EncryptedDraft("neuremiaDraftSleepHours", defaultValue: 7.0) var sleepHours
    @EncryptedDraft("neuremiaDraftAppetite", defaultValue: 3.0) var appetite
    // P2-7: default 0.0 = "Não se aplica" para evitar ruído com valor médio.
    @EncryptedDraft("neuremiaDraftLibido", defaultValue: 0.0) var libido
    @State var medicationStatus = MedicationStatus.taken
    @State var safetyStatus = SafetyStatus.safe
    // Same DraftStore encryption applies to the free-text fields, which are
    // the most sensitive of the bunch (Sprint 16 / F13' / S15).
    @EncryptedDraft("neuremiaDraftSideEffects", defaultValue: "") var sideEffects
    @EncryptedDraft("neuremiaDraftAutomaticThoughts", defaultValue: "") var automaticThoughts
    @EncryptedDraft("neuremiaDraftJournalEntry", defaultValue: "") var journalEntry
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
    // Diário progressivo estilo wizard (Sprint 27)
    @State var useProgressiveDiary = true
    @State var diaryCurrentStep: DiaryStep = .mood
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
    @State var remotePatientLoadID = UUID()
    @State var evolutionSearchQuery = ""
    @State var evolutionFilter: EvolutionFilter = .all
    @State var selectedExploreMode: ExploreMode = .now
    @State var isShowingBodySignalsTechnicalDetails = false
    @State var remoteCheckIns: [BackendDailyCheckIn] = []
    @State var remoteAssessments: [BackendScaleAssessment] = []
    @State var remoteAlerts: [BackendClinicalAlert] = []
    @State var remoteReports: [BackendClinicalReport] = []
    @State var remoteClinicalTasks: [BackendClinicalTask] = []
    @State var remotePatientClinicalTasks: [BackendClinicalTask] = []
    @State var remoteModelValidationReport: BackendModelValidationReport?
    @State var clinicalWorkflowStatusMessage = ""
    @State var caregiverName = ""
    @State var caregiverRelationship = ""
    @State var remoteCaregivers: [BackendCaregiverContact] = []
    @State var clinicianPatientStatusMessage = ""
    @State var remotePatientStatusMessage = ""
    @State var isAuthenticating = false
    @State var loginStatusMessage = ""
    @State var isShowingSettings = false
    @State var isShowingScales = false
    @State var isShowingBackup = false
    @State var isShowingExport = false
    @State var isImportingBackup = false
    @State var medicationPlans: [MedicationPlanEntry] = []
    @State var customSymptoms: [CustomSymptomEntry] = []
    @State var offlineSyncQueue: [OfflineSyncItem] = []
    @State var isRetryingPendingSync = false
    // queue when connectivity is restored without requiring user interaction.
    @State var networkMonitor = NWPathMonitor()
    @State var networkMonitorQueue = DispatchQueue(label: "io.neuremia.networkMonitor", qos: .background)
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
    @AppStorage("neuremiaMedicationReminderEnabled") var medicationReminderEnabled = false
    @AppStorage("neuremiaCheckInReminderEnabled") var checkInReminderEnabled = false
    @AppStorage("neuremiaDailyRetentionReminderEnabled") var dailyRetentionReminderEnabled = false
    @AppStorage("neuremiaMedicationReminderHour") var medicationReminderHour = 9
    @AppStorage("neuremiaCheckInReminderHour") var checkInReminderHour = 20
    @AppStorage("neuremiaDailyRetentionReminderHour") var dailyRetentionReminderHour = 19
    // PHI: medication fields are encrypted at rest via AES-GCM (DraftStore).
    // Legacy @AppStorage values are auto-migrated on first read.
    @EncryptedDraft("neuremiaMedicationName", defaultValue: "") var medicationName
    @EncryptedDraft("neuremiaMedicationDose", defaultValue: "") var medicationDose
    @EncryptedDraft("neuremiaMedicationSchedule", defaultValue: "") var medicationSchedule
    @EncryptedDraft("neuremiaMedicationChangeNote", defaultValue: "") var medicationChangeNote
    @EncryptedDraft("neuremiaMedicationPrescription", defaultValue: "") var medicationPrescription
    @EncryptedDraft("neuremiaMedicationPlansData", defaultValue: "") var medicationPlansData
    @AppStorage("neuremiaCustomSymptomName") var customSymptomName = ""
    @AppStorage("neuremiaCustomSymptomValue") var customSymptomValue = 3.0
    @AppStorage("neuremiaCustomSymptomsData") var customSymptomsData = ""
    @EncryptedDraft("neuremiaSafetyContact", defaultValue: "") var safetyContact
    @EncryptedDraft("neuremiaSafetyWarningSigns", defaultValue: "") var safetyWarningSigns
    @EncryptedDraft("neuremiaSafetyStrategies", defaultValue: "") var safetyStrategies
    @AppStorage("neuremiaNextAppointmentAt") var nextAppointmentAt = Date().addingTimeInterval(60 * 60 * 24 * 30).timeIntervalSince1970
    @AppStorage("neuremiaNextAppointmentNote") var nextAppointmentNote = ""
    @AppStorage("neuremiaAutoMonthlyReportEnabled") var autoMonthlyReportEnabled = false
    @AppStorage("neuremiaAutoBackupEnabled") var autoBackupEnabled = true
    @AppStorage("neuremiaBackupIntervalDays") var backupIntervalDays = 7
    @AppStorage("neuremiaLastAutomaticBackupAt") var lastAutomaticBackupAt = 0.0
    @AppStorage("neuremiaAutoCareTeamSendEnabled") var autoCareTeamSendEnabled = false
    @AppStorage("neuremiaCareTeamContact") var careTeamContact = ""
    @AppStorage("neuremiaCareTeamSendStatus") var careTeamSendStatus = "Envio automático inativo"
    @AppStorage("neuremiaShareWithCaregiver") var shareWithCaregiver = false
    @AppStorage("neuremiaHealthKitEnabled") var healthKitEnabled = false
    @AppStorage("neuremiaHealthKitStatus") var healthKitStatus = "Apple Health não conectado"
    @AppStorage("neuremiaHealthSteps") var healthSteps = 0
    @AppStorage("neuremiaHealthSleepHours") var healthSleepHours = 0.0
    @AppStorage("neuremiaHealthHeartRate") var healthHeartRate = 0.0
    @AppStorage("neuremiaHealthActiveEnergy") var healthActiveEnergy = 0.0
    @AppStorage("neuremiaHealthHRV") var healthHRV = 0.0
    @AppStorage("neuremiaLastHealthKitSyncAt") var lastHealthKitSyncAt = 0.0
    @AppStorage("neuremiaHealthKitPipelineData") var healthKitPipelineData = ""
    /// Serialized HealthKitReconciliationReport (multi-day diff between HK
    /// snapshots and diary check-ins). Rendered as an actionable checklist
    /// so users can see which days need attention instead of a free-form note.
    @AppStorage("neuremiaHealthKitReconciliationData") var healthKitReconciliationData = ""
    /// Serialized HealthKitAuthorizationSnapshot. Populated by the probe run
    /// after requestAuthorization succeeds — surfaces the types that came
    /// back empty (silent read denial) so we can prompt Settings › Health.
    @AppStorage("neuremiaHealthKitAuthData") var healthKitAuthData = ""
    @AppStorage("neuremiaHRVBaseline") var hrvBaseline = 0.0
    @AppStorage("neuremiaHRVBaselineSamples") var hrvBaselineSamples = 0
    @AppStorage("neuremiaHRVContextBaselinesData") var hrvContextBaselinesData = ""
    @AppStorage("neuremiaRemotePushEnabled") var remotePushEnabled = false
    @AppStorage("neuremiaRemotePushStatus") var remotePushStatus = "Push remoto não configurado"
    @KeychainStored(.apnsDeviceToken) var apnsDeviceToken
    @AppStorage("neuremiaBackgroundBackupStatus") var backgroundBackupStatus = "Backup em segundo plano não agendado"
    // lastBackupJSON was removed (S15/C1): PHI must not live in UserDefaults.
    // The backup file is written directly to BackupStore.protectedFileURL.
    @AppStorage("neuremiaOfflineSyncQueueData") var offlineSyncQueueData = ""
    @AppStorage("neuremiaLastSyncStatus") var lastSyncStatus = "Salvo no aparelho"
    @AppStorage("neuremiaBiometricConsentAccepted") var biometricConsentAccepted = false
    /// LGPD: timestamp (seconds since epoch) when biometric consent was granted. 0 = not yet granted.
    @AppStorage("neuremiaBiometricConsentGrantedAt") var biometricConsentGrantedAt: Double = 0
    @AppStorage("neuremiaPatientMoodModerateThreshold") var patientMoodModerateThreshold = 2.0
    @AppStorage("neuremiaPatientAnxietyModerateThreshold") var patientAnxietyModerateThreshold = 3.5
    @AppStorage("neuremiaPatientMinimumSleepThreshold") var patientMinimumSleepThreshold = 5.5
    @AppStorage("neuremiaCaregiverDigestConsent") var caregiverDigestConsent = false
    @AppStorage("neuremiaCaregiverSMSConsent") var caregiverSMSConsent = false
    @AppStorage("neuremiaCriticalPushConsent") var criticalPushConsent = false
    @AppStorage("neuremiaPrivacyRetentionDays") var privacyRetentionDays = 365
    @State var privacyStatusMessage = ""
    @State var privacyExportURL: URL?
    @State var isConfirmingClinicalWipe = false
    @State var isConfirmingAccountDelete = false
    @State var isShowingAuditLogs = false
    @State var activeLegalDocument: LegalDocument?
    @State var remoteAuditLogs: [BackendAuditLog] = []
    @State var caregiverEditTarget: BackendCaregiverContact?
    @State var caregiverToggleTarget: BackendCaregiverContact?
    @State var caregiverDeleteTarget: BackendCaregiverContact?
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
    @AppStorage("neuremiaOnboardingComplete") var hasCompletedOnboarding = false
    @AppStorage("neuremiaMoodCoachmarkSeen") var hasSeenMoodCoachmark = false
    @State var onboardingStep = 0
    /// Version string of the last legal document the user accepted.
    /// Empty = never accepted. Compared against LegalVersion.current to
    /// detect policy updates that require re-acceptance (LGPD Art. 7 I).
    @AppStorage("neuremiaLegalAcceptedVersion") var legalAcceptedVersion = ""
    /// True when the legal consent gate should be shown (first launch or
    /// after a policy update).
    var needsLegalAcceptance: Bool { legalAcceptedVersion != LegalVersion.current }
    /// Timestamp (timeIntervalSince1970) até quando o banner de convite fica
    /// escondido. Zero quando nunca foi adiado.
    @AppStorage("neuremiaInviteSnoozedUntil") var inviteSnoozedUntil = 0.0
    @State var passwordResetCode = ""
    @State var passwordResetNewPassword = ""
    @State var passwordResetStatusMessage = ""
    @State var isConfirmingPasswordReset = false
    @State var linkedClinicians: [BackendLinkedClinician] = []
    @State var linkedCliniciansStatusMessage = ""
    @State var clinicianToRevoke: BackendLinkedClinician?
    @Environment(\.scenePhase) var scenePhase
    // Temporary interruptions, including recording controls, must not hide the app.
    // Derive this from the scene so the shield cannot remain stuck after returning.
    private var isPrivacyShielded: Bool { scenePhase == .background }

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
        // Include last check-in timestamp so edits to the most recent entry
        // (same count, different values) still trigger .task(id:) re-fire.
        let lastCheckInKey = checkIns.last.map { "\($0.date.timeIntervalSinceReferenceDate)" } ?? ""
        return "\(checkIns.count)-\(assessments.count)-\(alerts.count)-\(ackedCount)-\(reports.count)-\(recommendationLogs.count)-\(lastCheckInKey)"
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
        ScaleKind.allCases.compactMap { automaticCheckupResult(for: $0) }
    }

    var neuremiaRiskSignature: NeuremiaRiskSignature {
        NeuremiaRiskSignature.calculate(
            summary: summary,
            checkIns: sortedCheckIns,
            scaleResults: automaticCheckupResults,
            mood: mood,
            anxiety: anxiety,
            sleepHours: sleepHours,
            medicationStatus: medicationStatus,
            activeTriggers: activeTriggerLabels,
            textAssessment: currentTextAssessment,
            ppgStress: ppgManager.isHeartRatePhysiologicallyValid ? ppgManager.stress : 0,
            ppgQuality: ppgManager.isHeartRatePhysiologicallyValid ? ppgManager.signalQuality : 0,
            voicePauseRatio: voiceManager.pauseRatio,
            typingSpeed: bodySignalTypingSpeed,
            careFocus: selectedCareFocus,
            moodModerateThreshold: patientMoodModerateThreshold,
            anxietyModerateThreshold: patientAnxietyModerateThreshold,
            minimumSleepThreshold: patientMinimumSleepThreshold
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

    var currentCrisisProtocol: ClinicalAlertProtocol {
        ClinicalAlertProtocol.local(
            kind: .psychiatricEmergency,
            escalationTarget: .clinicianCaregiverNow,
            criticalPushConsent: criticalPushConsent,
            caregiverSMSConsent: caregiverSMSConsent,
            caregiverDigestConsent: caregiverDigestConsent,
            enabledCaregiverCount: remoteCaregivers.filter(\.shareEnabled).count,
            safetyContactAvailable: !safetyContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var todayRecommendationLog: DailyRecommendationLog? {
        let todayKey = DailyCheckIn.dayKey(for: Date())
        return recommendationLogs.first { $0.dayKey == todayKey }
    }

    var healthKitPipelineStore: HealthKitPipelineStore {
        HealthKitPipelineStore.decode(from: healthKitPipelineData)
    }

    var adjustedDailyRecommendation: ClinicalDailyRecommendation {
        let base = summary.dailyRecommendation
        if base.targetSignal == ClinicalEpisodeKind.suicideRisk.rawValue {
            return base
        }

        if let causalRecommendation = personalizedCausalRecommendation {
            return adjustedRecommendationForRecentImpact(causalRecommendation)
        }

        return adjustedRecommendationForRecentImpact(base)
    }

    var currentRecommendationResponseProfile: RecommendationResponseProfile? {
        AdaptiveRecommendationEngine.profile(
            for: adjustedDailyRecommendation.targetSignal,
            logs: recommendationLogs
        )
    }

    var currentRetentionProfile: PersonalRetentionProfile {
        PersonalRetentionModelEngine.compute(
            checkIns: sortedCheckIns,
            recommendationLogs: recommendationLogs,
            temporalPrediction: summary.temporalPrediction,
            currentRecommendation: adjustedDailyRecommendation
        )
    }

    var personalizedCausalRecommendation: ClinicalDailyRecommendation? {
        let insights = CausalInsightsEngine.compute(from: sortedCheckIns)
        guard let insight = insights.first(where: isCausalInsightActionableToday) else {
            return nil
        }

        let delta = Int(abs(insight.deltaPercent).rounded())
        return ClinicalDailyRecommendation(
            id: "causal-\(insight.signalKey)",
            title: "Padrão pessoal",
            action: insight.recommendation,
            rationale: "\(insight.antecedent), \(insight.consequent) em média \(delta)% nos seus registros (n=\(insight.sampleSize), \(insight.confidence.label.lowercased())).",
            targetSignal: insight.signalKey,
            expectedWindow: "próximos 1-2 registros"
        )
    }

    func isCausalInsightActionableToday(_ insight: CausalInsight) -> Bool {
        let latestSaved = sortedCheckIns.first
        let journalContext = "\(journalEntryWithContext) \(automaticThoughts)"
        let hasExerciseSignal = containsAny(journalContext, terms: ["exercicio", "exercício", "caminhada", "atividade fisica", "atividade física", "treino leve"])
        let hasLateMeetingSignal = containsAny(journalContext, terms: ["reuniao tarde", "reunião tarde", "reuniao a noite", "reunião à noite", "call tarde", "call a noite", "plantao", "plantão"])

        switch insight.signalKey {
        case "sleep-debt-anxiety", "sleep-debt-mood":
            return sleepHours < 6 && (latestSaved?.sleepHours ?? 7) < 6
        case "short-sleep-energy":
            return sleepHours < 5
        case "missed-medication-mood", "missed-medication-anxiety":
            return !isMedicationFullyTaken
        case "two-day-medication-gap-anxiety":
            return !isMedicationFullyTaken && latestSaved?.medicationTaken == false
        case "high-anxiety-sleep":
            return anxiety >= 4
        case "high-irritability-mood":
            return irritability >= 4
        case "late-meeting-sleep-anxiety":
            return sleepHours < 6 && hasLateMeetingSignal
        case "light-exercise-mood":
            return hasExerciseSignal || insight.deltaPercent > 0
        default:
            return false
        }
    }

    func containsAny(_ text: String, terms: [String]) -> Bool {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return terms.contains { term in
            normalized.contains(term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
        }
    }

    func adjustedRecommendationForRecentImpact(_ base: ClinicalDailyRecommendation) -> ClinicalDailyRecommendation {
        guard let profile = AdaptiveRecommendationEngine.profile(for: base.targetSignal, logs: recommendationLogs) else {
            return base
        }

        if profile.isHarmful {
            return ClinicalDailyRecommendation(
                id: "\(base.id)-lighter",
                title: "\(base.title) ajustado",
                action: "Tente uma versão menor: \(base.action)",
                rationale: "Nas últimas \(profile.sampleCount) execuções medidas, essa linha teve impacto médio negativo (\(String(format: "%.1f", profile.averageNetImpact))). O app reduz a carga e continua medindo resposta.",
                targetSignal: base.targetSignal,
                expectedWindow: base.expectedWindow
            )
        }

        if profile.isNeutral {
            return ClinicalDailyRecommendation(
                id: "\(base.id)-specific",
                title: base.title,
                action: "\(base.action) Escolha um horário exato e registre se conseguiu.",
                rationale: "O efeito médio foi pequeno nas últimas \(profile.sampleCount) execuções medidas. Tornar a ação mais concreta ajuda a testar se a resposta melhora.",
                targetSignal: base.targetSignal,
                expectedWindow: base.expectedWindow
            )
        }

        if profile.isHelpful {
            return ClinicalDailyRecommendation(
                id: "\(base.id)-reinforced",
                title: base.title,
                action: base.action,
                rationale: "\(base.rationale) Para você, esta linha tem resposta positiva em \(Int((profile.responseRate * 100).rounded()))% das execuções medidas.",
                targetSignal: base.targetSignal,
                expectedWindow: base.expectedWindow
            )
        }

        return base
    }

    var activeRole: AccessRole {
        AccessRole(rawValue: patients.first?.activeRole ?? AccessRole.patient.rawValue) ?? .patient
    }

    var canViewClinicianData: Bool {
        DataResidencyPolicy.remoteSyncEnabled && activeRole == .clinician && patients.first?.shareWithClinician == true
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
            .tint(Color.neuroYellow)
            .preferredColorScheme(.dark)
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
            .onChange(of: gamificationManager.persistenceErrorMessage) { _, msg in
                guard !msg.isEmpty else { return }
                showToast(msg, level: .error)
                gamificationManager.clearPersistenceError()
            }
            .overlay(alignment: .bottom) { toastOverlay }
            .overlay {
                if let celebration = gamificationManager.pendingCelebration {
                    // Sprint 26: level-up ganha um overlay dedicado (rings
                    // expandindo + medalhão gigante). Outros tipos seguem
                    // no CelebrationOverlay padrão.
                    if case .levelUp(let newLevel) = celebration {
                        LevelUpCelebration(newLevel: newLevel) {
                            gamificationManager.dismissCelebration()
                        }
                    } else {
                        CelebrationOverlay(celebration: celebration) {
                            gamificationManager.dismissCelebration()
                        }
                    }
                }
            }
    }

    @ViewBuilder
    var rootContent: some View {
        if DataResidencyPolicy.remoteSyncEnabled && activeRole == .clinician {
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
                                    strategies: safetyStrategies,
                                    protocolSummary: currentCrisisProtocol
                                )
                                .padding(20)
                            } else {
                                SafetyPlanEditorCard(
                                    safetyContact: $safetyContact,
                                    warningSigns: $safetyWarningSigns,
                                    strategies: $safetyStrategies,
                                    signature: neuremiaRiskSignature,
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
                persistBaselineSelfSignalsIfNeeded()
                patientStore.recompute(checkIns: checkIns, assessments: assessments, alerts: alerts, reports: reports)
            }
            .onAppear {
                prepareInitialData()
                Task { @MainActor in retryPendingSync() }
                Task { await configureLocalReminders(showStatus: false) }
                Task { await syncContinuousHealthKitIfNeeded(force: false) }
                startNetworkMonitor()

                // Configure GamificationManager
                gamificationManager.configure(
                    modelContext: modelContext,
                    patient: patients.first,
                    checkIns: checkIns,
                    assessments: assessments,
                    missionLogs: patients.first?.missionLogs ?? []
                )

                if DataResidencyPolicy.remoteSyncEnabled && !authToken.isEmpty {
                    // Corrupted userId: token exists but stored id can't be parsed.
                    // Force logout to prevent a session where syncs silently fail.
                    if !_authenticatedUserIdStr.isEmpty, Int(_authenticatedUserIdStr) == nil {
                        loginStatusMessage = "Estado de sess\u{00e3}o inv\u{00e1}lido. Entre novamente."
                        authToken = ""
                        refreshToken = ""
                        authenticatedEmail = ""
                        authenticatedName = ""
                        authenticatedRole = ""
                        _authenticatedUserIdStr = ""
                        clearAllLocalPHIDrafts()
                        isShowingLoginSheet = true
                    } else {
                        Task {
                            await loadCaregivers()
                            await syncMyBackendAlerts()
                            await loadPendingInvites()
                            await loadLinkedClinicians()
                            await loadClinicianSentInvites()
                        }
                    }
                }
            }
            .onDisappear {
                // Sprint C: parar o networkMonitor para evitar memory leak
                networkMonitor.cancel()
            }
            .onChange(of: selectedCareFocus) { _, newValue in
                selectedScale = newValue.preferredScale
                ensureAnswers(for: selectedScale)
            }
            .onChange(of: selectedPatientPage) { _, _ in
                bodySignalInteractionCount += 1
            }
            .onChange(of: ppgManager.hrv) { _, newValue in
                updateHRVBaselineIfNeeded(newValue)
            }
            .onChange(of: healthHRV) { _, newValue in
                updateHealthHRVBaselineIfNeeded(newValue)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                Task { await syncContinuousHealthKitIfNeeded(force: false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .neuremiaSessionExpired)) { _ in
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
    }

}
