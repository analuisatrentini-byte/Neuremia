//
//  NeuroFlowApp.swift
//  NeuroFlow
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import SwiftUI
import SwiftData

@main
struct NeuroFlowApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PatientProfile.self,
            DailyCheckIn.self,
            ScaleAssessment.self,
            ClinicalAlert.self,
            ClinicalReport.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
