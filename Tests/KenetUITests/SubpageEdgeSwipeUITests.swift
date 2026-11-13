import XCTest

/// iPhone tab shell: a subpage hides the system navigation bar and draws its own back item
/// (``InkPageHeader``, ``InkNavigationRow``). The edge swipe must still pop the page.
final class SubpageEdgeSwipeUITests: XCTestCase {
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
    func testEdgeSwipeReturnsFromSubpages() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        try XCTSkipIf(UITestSupport.isSplitShell(app), "Bölünmüş kabuk sistem çubuğunu korur.")

        // Manşet back item (Özetler, pushed from Günlük).
        UITestSupport.openTab(app, identifier: "tab.days", screen: "screen.days")
        let summaries = UITestSupport.element(in: app, identifier: "button.summaries")
        UITestSupport.waitForExistence(summaries)
        summaries.tap()
        assertEdgeSwipeReturns(in: app, to: "screen.days")

        // Navigation-row back chip (a past day, pushed from Günlük).
        let day = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Eyl", "Sep")
        ).firstMatch
        for _ in 0..<6 where !(day.exists && day.isHittable) {
            app.swipeUp()
        }
        UITestSupport.waitForExistence(day)
        day.tap()
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.day"))
        assertEdgeSwipeReturns(in: app, to: "screen.days")
    }

    @MainActor
    private func assertEdgeSwipeReturns(
        in app: XCUIApplication, to screen: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let back = app.buttons.matching(identifier: "button.back").firstMatch
        UITestSupport.waitForExistence(back)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        let gone = NSPredicate(format: "exists == false")
        let result = XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: back)], timeout: 5)
        XCTAssertEqual(result, .completed, "Kenardan kaydırma alt sayfadan dönmedi", file: file, line: line)
        XCTAssertTrue(UITestSupport.element(in: app, identifier: screen).exists, file: file, line: line)
    }
}
