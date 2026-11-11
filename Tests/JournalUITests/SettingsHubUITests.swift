import XCTest

/// Settings hub (iPhone and iPad): every section row opens its own page. The six rows once sat in
/// one list row, and a tap on any of them opened the last one (Tanılama).
final class SettingsHubUITests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
    }

    /// `SettingsSection` raw values, in the hub's order.
    private let sections = ["quickEntry", "privacy", "notifications", "calendarAndLocation", "vault", "diagnostics"]

    @MainActor
    func testEverySectionRowOpensItsOwnPage() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)

        let settings = UITestSupport.element(in: app, identifier: "button.settings")
        UITestSupport.waitForExistence(settings)
        settings.tap()
        let hub = UITestSupport.element(in: app, identifier: "screen.settings")
        UITestSupport.waitForExistence(hub)

        for section in sections {
            let row = UITestSupport.element(in: app, identifier: "settings.section.\(section)")
            UITestSupport.waitForExistence(row)
            for _ in 0..<4 where !row.isHittable {
                hub.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(row.isHittable, "row \(section) is not reachable")
            row.tap()

            let page = UITestSupport.element(in: app, identifier: "screen.settings.\(section)")
            XCTAssertTrue(page.waitForExistence(timeout: 10), "row \(section) did not open its page")
            goBack(in: app)
            XCTAssertTrue(page.waitForNonExistence(timeout: 10), "page \(section) did not close")
            UITestSupport.waitForExistence(hub)
        }
    }

    /// The page's back item: Kenet's own (`button.back`) where it draws one, else the bar's.
    @MainActor
    private func goBack(in app: XCUIApplication) {
        let inkBack = app.buttons.matching(identifier: "button.back").firstMatch
        if inkBack.exists && inkBack.isHittable {
            inkBack.tap()
            return
        }
        let barBack = app.navigationBars.buttons.firstMatch
        UITestSupport.waitForExistence(barBack)
        barBack.tap()
    }
}
