import XCTest

/// Accessibility audits for the main phone screens opened from a fixture vault.
///
/// Every audit type runs (``AccessibilityAuditPolicy``); the few exempt elements are listed, with their
/// reasons, in ``AccessibilityAuditExemption``.
///
/// On iPad the same screens are audited in the split shell: `UITestSupport.openTab` selects the
/// tab's sidebar row there. The iPad runs on its side (the screen tour's layout, three columns);
/// `JOURNAL_UITEST_ORIENTATION=portrait` (through `TEST_RUNNER_`) audits it upright.
final class AccessibilityAuditUITests: XCTestCase {
    static let orientationKey = "JOURNAL_UITEST_ORIENTATION"
    private var vaultURL: URL!
    private var turned = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL {
            try? FileManager.default.removeItem(at: vaultURL)
        }
        // A simulator left on its side would turn the iPad snapshot run that follows it.
        if turned { MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait } }
    }

    /// Split shell (iPad): turns the device as requested, on its side by default.
    @MainActor
    private func turnSplitShell(_ app: XCUIApplication) {
        guard UITestSupport.isSplitShell(app) else { return }
        let requested = ProcessInfo.processInfo.environment[Self.orientationKey] ?? ""
        XCUIDevice.shared.orientation = requested == "portrait" ? .portrait : .landscapeLeft
        turned = true
    }

    @MainActor
    func testMainScreensPassAccessibilityAudit() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL)
        UITestSupport.activateSystemAlertMonitor(in: app)

        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"))
        turnSplitShell(app)
        try audit(app, screen: "today")

        UITestSupport.openTab(app, identifier: "tab.days", screen: "screen.days")
        try audit(app, screen: "days")

        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")
        try audit(app, screen: "tasks")

        UITestSupport.openTab(app, identifier: "tab.entities", screen: "screen.entities")
        try audit(app, screen: "entities")

        UITestSupport.openTab(app, identifier: "tab.today", screen: "screen.today")
        let settings = UITestSupport.element(in: app, identifier: "button.settings")
        UITestSupport.waitForExistence(settings)
        settings.tap()
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.settings"))
        try audit(app, screen: "settings")
    }

    /// A second -56 timeout skips the screen here (logged); every real finding still fails the test.
    @MainActor
    private func audit(_ app: XCUIApplication, screen: String) throws {
        try AccessibilityAuditPolicy.audit(app, screen: screen, secondTimeout: .skip)
    }
}
