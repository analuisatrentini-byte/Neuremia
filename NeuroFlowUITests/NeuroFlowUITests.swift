//
//  NeuroFlowUITests.swift
//  NeuroFlowUITests
//
//  Created by Ana Luisa Bittencourt on 14/05/26.
//

import XCTest

final class NeuroFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainClinicalFlowLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Diário"].exists)
        XCTAssertTrue(app.buttons["Salvar registro diário"].exists)
    }

    @MainActor
    func testSettingsTabShowsLoginAndPrivacyControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        app.buttons["Configurações"].tap()

        XCTAssertTrue(app.staticTexts["Configurações"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Entrar na conta"].exists)
        XCTAssertTrue(app.staticTexts["Versão do aplicativo"].exists)
        XCTAssertTrue(app.staticTexts["Dashboard médico"].exists)
    }

    @MainActor
    func testDiaryShowsMedicationSymptomsEducationAndSyncStatus() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Medicamentos"].exists)
        XCTAssertTrue(app.staticTexts["Sintomas personalizados"].exists)
        XCTAssertTrue(app.staticTexts["Aprender sobre meu cuidado"].exists)
        XCTAssertTrue(app.staticTexts["Dados protegidos"].exists)
    }

    @MainActor
    func testSettingsShowsBackupControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        app.buttons["Configurações"].tap()

        XCTAssertTrue(app.staticTexts["Backup dos dados"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Backup automático ao salvar diário"].exists)
        XCTAssertTrue(app.buttons["Gerar backup"].exists)
        XCTAssertTrue(app.buttons["Restaurar backup"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// E2E: ensures the privacy & data (LGPD) card added in Sprint 4 is
    /// reachable from the Settings sheet and that the destructive actions are
    /// initially disabled (no token).
    @MainActor
    func testPrivacyAndDataCardReachable() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        app.buttons["Configurações"].tap()
        XCTAssertTrue(app.staticTexts["Privacidade e dados (LGPD)"].waitForExistence(timeout: 3))

        let downloadButton = app.buttons["Baixar meus dados (JSON)"]
        let deleteOldButton = app.buttons["Apagar dados clínicos antigos"]
        let deleteAccountButton = app.buttons["Apagar minha conta"]

        XCTAssertTrue(downloadButton.exists)
        XCTAssertTrue(deleteOldButton.exists)
        XCTAssertTrue(deleteAccountButton.exists)
        // Without a logged-in account, destructive actions stay disabled so
        // an anonymous user can't accidentally request deletion.
        XCTAssertFalse(downloadButton.isEnabled)
        XCTAssertFalse(deleteOldButton.isEnabled)
        XCTAssertFalse(deleteAccountButton.isEnabled)
    }

    /// E2E golden path: accept consent -> save check-in -> see confirmation.
    /// Exercises the SwiftData write path that powers historical analysis.
    @MainActor
    func testGoldenPathSavesCheckIn() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))

        let consentToggle = app.switches["privacyConsentToggle"]
        XCTAssertTrue(consentToggle.waitForExistence(timeout: 3))
        if consentToggle.value as? String != "1" {
            consentToggle.tap()
        }

        let saveButton = app.buttons["saveCheckInButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.isEnabled, "Consent toggle should enable the save action.")

        saveButton.tap()
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Registro")).firstMatch.waitForExistence(timeout: 4),
            "Confirmation label should appear after saving the daily check-in."
        )
    }
}
