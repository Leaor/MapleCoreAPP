import XCTest

/// Critical workflows, run against a fresh in-memory store (`-uitest`).
/// Sign-in uses the demo code; permission steps are skipped with "Not Now" so no system alerts appear.
final class CriticalFlowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    private func signIn(_ email: String, code: String = "123456") {
        let login = app.textFields["signin-login"]
        XCTAssertTrue(login.waitForExistence(timeout: 5), "sign-in field should appear after the splash")
        login.tap()
        login.typeText(email)
        app.buttons["signin-continue"].tap()
        let codeField = app.textFields["verify-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText(code)
    }

    private func skipPermissions() {
        let notNow = app.buttons["Not Now"]
        // Notifications, then (field only) location.
        for _ in 0..<2 where notNow.waitForExistence(timeout: 4) {
            notNow.tap()
        }
    }

    func testWrongCodeShowsErrorAndStaysOnVerify() {
        signIn("daniel@maplecorelawncare.com", code: "000000")
        let error = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "isn't right")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["verify-code"].exists)
    }

    func testAdminSignInAndTabNavigation() {
        signIn("michael@maplecorelawncare.com")
        let continueAdmin = app.buttons["Continue as Admin"]
        XCTAssertTrue(continueAdmin.waitForExistence(timeout: 8), "dual-role account chooses a role")
        continueAdmin.tap()
        skipPermissions()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for tab in ["Routes", "Properties", "Inbox", "More", "Today"] {
            tabBar.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 3), "\(tab) tab shows its title")
        }
    }

    func testPropertyDetailKeepsPlaceAcrossTabs() {
        signIn("michael@maplecorelawncare.com")
        app.buttons["Continue as Admin"].firstMatch.tap()
        skipPermissions()

        app.tabBars.buttons["Properties"].tap()
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Islington Medical Centre")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let address = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 Kipling Ave")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 3), "property profile is shown")

        app.tabBars.buttons["Inbox"].tap()
        app.tabBars.buttons["Properties"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 3), "returning to the tab keeps the pushed property")
        XCTAssertFalse(app.searchFields["Name, address or customer"].exists, "the root list is not showing")
    }

    func testFieldUserArrivesAndOpensVisit() {
        signIn("daniel@maplecorelawncare.com")
        skipPermissions()

        let arrived = app.buttons["I've Arrived"].firstMatch
        XCTAssertTrue(arrived.waitForExistence(timeout: 8), "field Today shows the next stop")
        arrived.tap()

        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Start Visit")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "visit cover opens on the Arrived step")
        start.tap()

        // Simulator: no camera, the shutter adds placeholder photos.
        let shutter = app.buttons["Take before photo"]
        if shutter.waitForExistence(timeout: 5) {
            for _ in 0..<3 where shutter.exists && shutter.isHittable {
                shutter.tap()
            }
        }
    }
}
