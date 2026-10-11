import XCTest

/// Accessibility audit of the quick entry bar while recognized names stand as chips above it.
final class QuickEntryNameChipAccessibilityUITests: XCTestCase {
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
    func testNameChipsPassAccessibilityAuditAndATapUndoesOne() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: "Deniz ile Mert Aksu")
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"))
        // The spoken label is "Recognized: Deniz" in the test's language; the name is the user's text.
        let deniz = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ": Deniz")).firstMatch
        let mert = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ": Mert Aksu")).firstMatch
        UITestSupport.waitForExistence(deniz)
        UITestSupport.waitForExistence(mert)

        let deferred: XCUIAccessibilityAuditType = [.hitRegion, .contrast, .dynamicType, .textClipped]
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(deferred)) { issue in
            if issue.auditType == .elementDetection, issue.element == nil { return true }
            let element = issue.element?.description ?? "(no element)"
            print("A11Y issue (quick entry names): \(issue.auditType) — \(issue.compactDescription) — \(element)")
            return false
        }

        deniz.tourTap()
        XCTAssertTrue(deniz.waitForNonExistence(timeout: 10))
        XCTAssertTrue(mert.exists)
    }
}
