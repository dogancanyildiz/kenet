import XCTest

/// Accessibility audit of an entity page that lists unlinked mentions.
final class UnlinkedMentionsAccessibilityUITests: XCTestCase {
    private var vaultURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareFixtureVault(named: "unlinked-mentions")
    }

    override func tearDownWithError() throws {
        if let vaultURL {
            try? FileManager.default.removeItem(at: vaultURL)
        }
    }

    /// Opens Elif's page and scrolls until the first "Link" button is on screen.
    @MainActor
    private func openUnlinkedMentions() -> (app: XCUIApplication, link: XCUIElement) {
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
        return (app, link)
    }

    /// The button on a row links that row and no other. Each button's spoken label carries its own
    /// line (the user's text, the same in every language), which is how the rows are told apart.
    /// The app works on its own copy of the vault, so the file itself is out of this test's reach;
    /// the bytes are measured in `UnlinkedMentionsTests`.
    @MainActor
    func testLinkButtonLinksItsOwnRow() throws {
        let (app, _) = openUnlinkedMentions()
        func button(_ line: String) -> XCUIElement {
            app.buttons.matching(identifier: "button.unlinkedMention.link")
                .matching(NSPredicate(format: "label CONTAINS %@", line)).firstMatch
        }
        let first = button("Elif'le konuştum.")
        let second = button("Lale geldi.")
        UITestSupport.waitForExistence(first)
        UITestSupport.waitForExistence(second)
        first.tourTap()

        XCTAssertTrue(first.waitForNonExistence(timeout: 20))
        UITestSupport.waitForExistence(second)
        XCTAssertTrue(second.isEnabled)
        // It was written, not refused.
        XCTAssertFalse(UITestSupport.element(in: app, identifier: "entity.unlinkedMentions.notice").exists)
    }

    @MainActor
    func testEntityPagePassesAccessibilityAudit() throws {
        let (app, _) = openUnlinkedMentions()

        try AccessibilityAuditPolicy.audit(app, screen: "unlinkedMentions")
    }
}
