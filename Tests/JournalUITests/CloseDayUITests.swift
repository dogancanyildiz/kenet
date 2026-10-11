import XCTest

/// "Günü kapat" opened from Today on a temporary copy of the sample vault: both steps are
/// reachable by identifier and pass the accessibility audit. Nothing is applied.
final class CloseDayUITests: XCTestCase {
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
    func testBothStepsPassAccessibilityAudit() throws {
        // The sample vault's open tasks are all behind the wall clock, so the entry row is offered.
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        let entry = UITestSupport.element(in: app, identifier: "button.closeDay")
        UITestSupport.waitForExistence(entry)
        entry.tap()

        let apply = UITestSupport.element(in: app, identifier: "button.closeDay.apply")
        UITestSupport.waitForExistence(apply)
        // No choice yet: the only write action is not available.
        XCTAssertFalse(apply.isEnabled)
        try audit(app)

        UITestSupport.element(in: app, identifier: "button.closeDay.next").tap()
        let back = UITestSupport.element(in: app, identifier: "button.closeDay.back")
        UITestSupport.waitForExistence(back)
        try audit(app)

        UITestSupport.element(in: app, identifier: "button.closeDay.next").tap()
        let write = UITestSupport.element(in: app, identifier: "button.closeDay.write")
        UITestSupport.waitForExistence(write)
        XCTAssertFalse(write.isEnabled)
        try audit(app)

        UITestSupport.element(in: app, identifier: "button.closeDay.close").tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 15))
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
            print("A11Y issue (closeDay): \(issue.auditType) — \(issue.compactDescription) — \(element)")
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
