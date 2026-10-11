import XCTest

/// Accessibility audit of an entity page that lists unlinked mentions.
final class UnlinkedMentionsAccessibilityUITests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        let fixture = UITestSupport.repositoryRoot().appendingPathComponent(
            "Fixtures/vaults/unlinked-mentions", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixture.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw XCTSkip("Unlinked-mentions fixture missing at \(fixture.path)")
        }
        vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "JournalUITest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: fixture, to: vaultURL)
    }

    override func tearDownWithError() throws {
        if let vaultURL {
            try? FileManager.default.removeItem(at: vaultURL)
        }
    }

    @MainActor
    func testEntityPagePassesAccessibilityAudit() throws {
        let app = UITestSupport.launchApp(vaultURL: vaultURL, quickEntryText: nil)
        UITestSupport.activateSystemAlertMonitor(in: app)
        UITestSupport.openTab(app, identifier: "tab.entities", screen: "screen.entities")

        let elif = app.staticTexts["Elif"].firstMatch
        if !elif.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        UITestSupport.waitForExistence(elif)
        elif.tourTap()

        let section = UITestSupport.element(in: app, identifier: "entity.unlinkedMentions")
        let link = UITestSupport.element(in: app, identifier: "button.unlinkedMention.link")
        for _ in 0..<12 where !link.exists {
            app.swipeUp()
            if link.waitForExistence(timeout: 1) { break }
        }
        UITestSupport.waitForExistence(section)
        UITestSupport.waitForExistence(link)

        let deferred: XCUIAccessibilityAuditType = [.hitRegion, .contrast, .dynamicType, .textClipped]
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting(deferred)) { issue in
            if issue.auditType == .elementDetection, issue.element == nil { return true }
            let element = issue.element?.description ?? "(no element)"
            print("A11Y issue (unlinked mentions): \(issue.auditType) — \(issue.compactDescription) — \(element)")
            return false
        }
    }
}
