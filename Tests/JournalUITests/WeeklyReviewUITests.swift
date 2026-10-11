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
        try audit(app)

        // Açık görevler, görüşmediklerin, hedefler, not: four more pages before the preview.
        let back = UITestSupport.element(in: app, identifier: "button.weeklyReview.back")
        for _ in 0..<4 {
            next.tap()
            UITestSupport.waitForExistence(back)
            try audit(app)
        }
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "field.weeklyReview.note"))

        next.tap()
        let write = UITestSupport.element(in: app, identifier: "button.weeklyReview.write")
        UITestSupport.waitForExistence(write)
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

    /// Same audit types as ``AccessibilityAuditUITests`` (its deferrals are listed there).
    @MainActor
    private func audit(_ app: XCUIApplication) throws {
        let deferred: XCUIAccessibilityAuditType = [.hitRegion, .contrast, .dynamicType, .textClipped]
        let types = XCUIAccessibilityAuditType.all.subtracting(deferred)
        let handler: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            let element = issue.element?.description ?? "(no element)"
            // Screenshot-based detection that names no element leaves nothing to fix.
            if issue.auditType == .elementDetection, issue.element == nil { return true }
            print("A11Y issue (weeklyReview): \(issue.auditType) — \(issue.compactDescription) — \(element)")
            return false
        }
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError where error.code == -56 {
            // "Audit failed to complete in time" on a busy simulator: once more.
            try app.performAccessibilityAudit(for: types, handler)
        }
    }
}
