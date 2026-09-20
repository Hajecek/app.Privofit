import XCTest

@MainActor final class PrivofitUITests: XCTestCase {
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--reset", "--no-biometry", "-AppleLanguages", "(cs)", "-AppleLocale", "cs_CZ"] + extra
        app.launch(); return app
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 { if element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
    private func finishOnboarding(_ app: XCUIApplication) {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); scrollTo(next, in: app); next.tap()
        scrollTo(app.buttons["onboarding.skip"], in: app); app.buttons["onboarding.skip"].tap()
        XCTAssertFalse(next.isEnabled) // Injected unavailable biometrics.
        app.buttons["onboarding.skip"].tap(); scrollTo(next, in: app); next.tap()
    }
    private func login(_ app: XCUIApplication) {
        let identifier = app.textFields["login.identifier"]
        scrollTo(identifier, in: app); identifier.tap(); identifier.typeText("alex")
        let password = app.secureTextFields.firstMatch
        password.tap(); password.typeText("demo-password")
        let submit = app.buttons["login.submit"]; scrollTo(submit, in: app);         submit.tap()
        XCTAssertTrue(app.buttons["door.launch"].waitForExistence(timeout: 8))
    }
    func testGuestOnboardingAndProtectedDoor() {
        let app = launch(); let guest = app.buttons["auth.guest"]
        scrollTo(guest, in: app); guest.tap(); finishOnboarding(app)
        XCTAssertTrue(app.buttons["door.launch"].waitForExistence(timeout: 5)); app.buttons["door.launch"].tap()
        XCTAssertTrue(app.staticTexts["Tenhle prostor je pro členy."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Dveře jsou otevřené."].exists)
    }
    func testLoginAndMockDoorSuccess() {
        let app = launch(); login(app)
        app.buttons["door.launch"].tap()
        let prepare = app.buttons["door.prepare"]; scrollTo(prepare, in: app); prepare.tap()
        app.buttons["Otevřít dveře"].tap()
        XCTAssertTrue(app.staticTexts["Dveře jsou otevřené."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["SIMULACE · žádné skutečné dveře"].exists)
    }
    func testDeniedDoor() {
        let app = launch(["--deny-door"]); login(app)
        app.buttons["door.launch"].tap()
        let prepare = app.buttons["door.prepare"]; scrollTo(prepare, in: app); prepare.tap(); app.buttons["Otevřít dveře"].tap()
        XCTAssertTrue(app.staticTexts["Vstup nebyl povolen."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dveře jsou otevřené."].exists)
    }
    func testDenyNotificationsDoesNotBlockOnboarding() {
        let app = launch()
        addUIInterruptionMonitor(withDescription: "Notifications permission") { alert in
            let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Nepovolovat", "Don’t Allow")).firstMatch
            if deny.exists { deny.tap(); return true }; return false
        }
        let guest = app.buttons["auth.guest"]; scrollTo(guest, in: app); guest.tap()
        app.buttons["onboarding.next"].tap(); app.buttons["onboarding.next"].tap(); app.tap()
        XCTAssertTrue(app.staticTexts["Biometrie není dostupná"].waitForExistence(timeout: 5))
        app.buttons["onboarding.skip"].tap(); app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["door.launch"].waitForExistence(timeout: 5))
    }
}
