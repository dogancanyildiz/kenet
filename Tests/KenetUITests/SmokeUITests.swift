import UIKit
import XCTest

/// Fixture-vault smoke path: open Today, add an event, visit main tabs and Settings.
final class SmokeUITests: XCTestCase {
    private var vaultURL: URL!
    /// Sits in the middle of Bugün, where a stray touch on the screen centre lands.
    private let fixtureTask = "Eski doküman arşivini temizle"

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
        // The task list section is restored from the last run; pin it so the check below can
        // find the fixture task.
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL,
            extraArguments: ["-tasks.view.mode", "list", "-tasks.view.list.section", "upcoming"])
        UITestSupport.activateSystemAlertMonitor(in: app)

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
        // The flow must not complete a fixture task on the way: a completed task leaves
        // "Yaklaşan". (The app works on its own copy of the vault, so the files the runner
        // prepared cannot show this.)
        let untouchedTask = app.staticTexts.matching(NSPredicate(format: "label == %@", fixtureTask)).firstMatch
        UITestSupport.waitForExistence(untouchedTask, timeout: 30)
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
