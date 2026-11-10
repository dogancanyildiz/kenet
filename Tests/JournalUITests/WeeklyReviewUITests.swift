import XCTest

/// The weekly review opened from Günlük on a temporary copy of the sample vault: every step is
/// reachable by identifier and passes the accessibility audit. Nothing is written.
final class WeeklyReviewUITests: XCTestCase {
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
    func testEveryStepPassesAccessibilityAudit() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        UITestSupport.openTab(app, identifier: "tab.days", screen: "screen.days")
        let entry = UITestSupport.element(in: app, identifier: "button.weeklyReview")
        UITestSupport.waitForExistence(entry)
        entry.tap()

        let next = UITestSupport.element(in: app, identifier: "button.weeklyReview.next")
        UITestSupport.waitForExistence(next)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "tabs.weeklyReview.week"))
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "field.weeklyReview.note"))
        try audit(app)

        // Step 2: Açık görevler ve hedefler özeti before the preview.
        let back = UITestSupport.element(in: app, identifier: "button.weeklyReview.back")
        advance(app, with: next, until: back)
        try audit(app)

        let write = UITestSupport.element(in: app, identifier: "button.weeklyReview.write")
        advance(app, with: next, until: write)
        try audit(app)

        // No note was typed, so "Vazgeç" leaves at once and nothing has been written.
        UITestSupport.element(in: app, identifier: "button.weeklyReview.cancel").tap()
        XCTAssertTrue(write.waitForNonExistence(timeout: 15))
        let journal = try FileManager.default.contentsOfDirectory(
            atPath: vaultURL.appendingPathComponent("journal").path)
        let fixture = try FileManager.default.contentsOfDirectory(
            atPath: UITestSupport.repositoryRoot().appendingPathComponent("Fixtures/vaults/sample/journal").path)
        XCTAssertEqual(journal.sorted(), fixture.sorted())
    }

    /// Taps "İleri" (or "Atla") at the foot of the step until `shown` appears. The buttons sit
    /// under the step's cards: a tap right after XCTest scrolled them into view can land while the
    /// sheet's scroll view still moves, and only stops it (iOS 26.2, CI). So the page is first
    /// swiped until the button is hittable and left to settle; a missed tap is tried again.
    @MainActor
    private func advance(_ app: XCUIApplication, with next: XCUIElement, until shown: XCUIElement) {
        for _ in 0..<3 {
            for _ in 0..<4 where !next.isHittable {
                app.swipeUp()
            }
            // Let a swipe's deceleration end before the tap.
            _ = shown.waitForExistence(timeout: 1)
            if shown.exists { return }
            next.tap()
            if shown.waitForExistence(timeout: 5) { return }
        }
        UITestSupport.waitForExistence(shown)
    }

    /// The shared audit (``AccessibilityAuditPolicy``).
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        try AccessibilityAuditPolicy.audit(app, screen: "weeklyReview")
    }
}
