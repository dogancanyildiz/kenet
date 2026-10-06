import UIKit
import XCTest

/// Fixture-vault smoke path: open Today, add an event, visit main tabs and Settings.
final class SmokeUITests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL {
            try? FileManager.default.removeItem(at: vaultURL)
        }
    }

    @MainActor
    func testSmokeFlowAcrossMainScreens() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL)
        app.tap()

        let today = UITestSupport.element(in: app, identifier: "screen.today")
        UITestSupport.waitForExistence(today, timeout: 30)
        XCTAssertTrue(today.exists)

        let field = UITestSupport.quickEntryField(in: app)
        UITestSupport.waitForExistence(field, timeout: 30)
        // The text arrives through the DEBUG launch environment: the keyboard and the paste menu
        // behave differently across simulator versions. Typing is only a fallback.
        if !(field.value as? String ?? "").contains(UITestSupport.smokeEventText) {
            field.tap()
            app.typeText(UITestSupport.smokeEventText)
        }

        let send = UITestSupport.element(in: app, identifier: "button.quickEntrySend")
        UITestSupport.waitForExistence(send)
        // Poll until the SwiftUI binding enables send (canSubmit).
        var enabled = false
        for _ in 0..<40 {
            if send.isEnabled {
                enabled = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(enabled, "Send stayed disabled — quick-entry text likely not bound")
        send.tap()

        let event = app.descendants(matching: .any)
            .matching(identifier: "event.row")
            .matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@", UITestSupport.smokeEventText,
                    UITestSupport.smokeEventText)
            )
            .firstMatch
        UITestSupport.waitForExistence(event, timeout: 30)
        XCTAssertTrue(event.exists)

        UITestSupport.openTab(app, identifier: "tab.days", screen: "screen.days")
        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")
        UITestSupport.openTab(app, identifier: "tab.entities", screen: "screen.entities")
        UITestSupport.openTab(app, identifier: "tab.today", screen: "screen.today")

        let settings = UITestSupport.element(in: app, identifier: "button.settings")
        UITestSupport.waitForExistence(settings)
        settings.tap()
        let settingsScreen = UITestSupport.element(in: app, identifier: "screen.settings")
        UITestSupport.waitForExistence(settingsScreen)
        XCTAssertTrue(settingsScreen.exists)

        let close = UITestSupport.element(in: app, identifier: "button.settings.close")
        UITestSupport.waitForExistence(close)
        close.tap()
        UITestSupport.waitForExistence(today)
    }

}
