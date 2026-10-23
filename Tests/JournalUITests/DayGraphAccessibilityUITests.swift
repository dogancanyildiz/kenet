import XCTest

/// Accessibility audit of a day's own graph, opened from the Graph icon on a past day's manşet
/// (the sample vault has no file for the real today).
final class DayGraphAccessibilityUITests: XCTestCase {
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
    func testDayGraphPassesAccessibilityAudit() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"))
        UITestSupport.openTab(app, identifier: "tab.days", screen: "screen.days")
        // A day row reads "<date with year>, <events>, …" in every language; the newest day comes first.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "2026, ")).firstMatch
        UITestSupport.waitForExistence(row)
        row.tourTap()
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.day"))
        let icon = UITestSupport.element(in: app, identifier: "button.dayGraph")
        UITestSupport.waitForExistence(icon)
        icon.tourTap()
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.dayGraph"))
        try AccessibilityAuditPolicy.audit(app, screen: "dayGraph")
    }
}
