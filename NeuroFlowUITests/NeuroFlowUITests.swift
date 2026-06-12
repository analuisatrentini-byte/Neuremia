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
        XCTAssertTrue(app.staticTexts["Registro diário"].exists)
        XCTAssertTrue(app.switches["Aceito registrar dados clínicos neste dispositivo"].exists)
        XCTAssertTrue(app.buttons["Salvar registro diário"].exists)
    }

    @MainActor
    func testSecurityTabShowsPrivacyControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["NeuroFlow"].waitForExistence(timeout: 5))
        app.buttons["Segurança"].tap()

        XCTAssertTrue(app.staticTexts["Segurança e governança"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Perfil de acesso"].exists)
        XCTAssertTrue(app.staticTexts["Dashboard médico"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
