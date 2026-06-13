//
//  NeuroFlowApp.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData
import UIKit
import BackgroundTasks

/// Single source of truth for the on-device backup file path.
/// Both ContentView (writes) and NeuroFlowBackgroundTasks (reads) use this.
enum BackupStore {
    /// Protected file in Documents, excluded from iCloud Backup.
    static var protectedFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("neuroflow-backup.json")
    }
}

private enum NeuroFlowBackgroundTasks {
    static let backupRefreshIdentifier = "ALTB.NeuroFlow.backup-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backupRefreshIdentifier, using: nil) { task in
            handleBackupRefresh(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleBackupRefresh() {
        let intervalDays = max(1, UserDefaults.standard.integer(forKey: "neuroflowBackupIntervalDays"))
        let request = BGAppRefreshTaskRequest(identifier: backupRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalDays * 86_400))

        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set("Backup em segundo plano agendado.", forKey: "neuroflowBackgroundBackupStatus")
        } catch {
            UserDefaults.standard.set("Falha ao agendar backup em segundo plano: \(error.localizedDescription)", forKey: "neuroflowBackgroundBackupStatus")
        }
    }

    private static func handleBackupRefresh(task: BGAppRefreshTask) {
        scheduleBackupRefresh()

        task.expirationHandler = {
            UserDefaults.standard.set("Backup em segundo plano expirou antes de finalizar.", forKey: "neuroflowBackgroundBackupStatus")
        }

        // S15: The backup file is written directly by makeBackupExport with
        // .completeFileProtection and isExcludedFromBackup = true. The
        // background task only needs to verify the file exists and record the
        // timestamp — no PHI passes through UserDefaults.
        let fileURL = BackupStore.protectedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            UserDefaults.standard.set("Sem backup local para atualizar em segundo plano.", forKey: "neuroflowBackgroundBackupStatus")
            task.setTaskCompleted(success: true)
            return
        }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "neuroflowLastAutomaticBackupAt")
        UserDefaults.standard.set("Backup em segundo plano verificado.", forKey: "neuroflowBackgroundBackupStatus")
        task.setTaskCompleted(success: true)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Move any legacy plaintext credentials out of UserDefaults before any
        // view reads them.
        KeychainStore.migrateLegacyTokenIfNeeded()
        NeuroFlowBackgroundTasks.register()
        NeuroFlowBackgroundTasks.scheduleBackupRefresh()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        NeuroFlowBackgroundTasks.scheduleBackupRefresh()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        KeychainStore.set(token, for: .apnsDeviceToken)
        UserDefaults.standard.set("Token APNs recebido. Envie ao backend nas configurações.", forKey: "neuroflowRemotePushStatus")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set("Falha no APNs: \(error.localizedDescription)", forKey: "neuroflowRemotePushStatus")
    }
}

@main
struct NeuroFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Non-nil when the persistent store had to be rebuilt or replaced with an
    /// in-memory fallback. ContentView reads this once on appear and shows a
    /// banner so the user knows what happened.
    nonisolated(unsafe) static var storeRecoveryMessage: String?

    let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema(NeuroFlowSchemaV1.models, version: NeuroFlowSchemaV1.versionIdentifier)
        let persistentConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // 1st try — normal persistent open with migration plan.
        if let container = try? ModelContainer(for: schema, migrationPlan: NeuroFlowMigrationPlan.self, configurations: [persistentConfig]) {
            sharedModelContainer = container
            return
        }

        // 2nd try — delete the corrupt / schema-incompatible store and recreate.
        // This handles schema changes made without a formal MigrationPlan. Data
        // is lost, but the app stays usable and the user sees a clear message.
        let storeURL = persistentConfig.url
        let sidecarExtensions = ["", "-wal", "-shm"]
        for ext in sidecarExtensions {
            let sidecar = storeURL.deletingPathExtension()
                .appendingPathExtension(storeURL.pathExtension + ext)
            try? FileManager.default.removeItem(at: sidecar)
        }

        if let container = try? ModelContainer(for: schema, migrationPlan: NeuroFlowMigrationPlan.self, configurations: [persistentConfig]) {
            sharedModelContainer = container
            NeuroFlowApp.storeRecoveryMessage =
                "O banco de dados local foi recriado após um erro de compatibilidade. " +
                "Registros anteriores não puderam ser recuperados."
            return
        }

        // 3rd try — in-memory fallback. The app stays open so the user can
        // still access the crisis plan and SOS contacts.
        let inMemoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [inMemoryConfig])
        } catch {
            fatalError("In-memory ModelContainer failed unexpectedly: \(error)")
        }
        NeuroFlowApp.storeRecoveryMessage =
            "Não foi possível abrir o banco de dados local. O aplicativo está " +
            "funcionando sem persistência — dados deste uso não serão salvos. " +
            "Reinicie o app para tentar novamente."
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
