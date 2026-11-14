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
        // The list mounts only the rows near the screen, and `openUnlinkedMentions` stops at the
        // first button it meets: the row under it may not exist yet. Each button is brought into
        // reach on its own, the lower row first so the upper one stays on screen with it.
        reveal(second, in: app)
        reveal(first, in: app)
        UITestSupport.waitForExistence(first)
        UITestSupport.waitForExistence(second)
        first.tourTap()

        XCTAssertTrue(first.waitForNonExistence(timeout: 20))
        UITestSupport.waitForExistence(second)
        XCTAssertTrue(second.isEnabled)
        // It was written, not refused.
        XCTAssertFalse(UITestSupport.element(in: app, identifier: "entity.unlinkedMentions.notice").exists)
    }

    /// Scrolls in short, slow drags until `element` exists and can be touched in the middle band of
    /// the screen, clear of the pinned title above and of the quick entry capsule and tab bar below.
    /// The page moves towards its end while the element is not mounted, back towards its start once
    /// the end did not bring it, and by the element's own distance once its frame is known.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let band = (window.minY + window.height * 0.25)...(window.minY + window.height * 0.65)
        let anchor = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let step: CGFloat = 140
        var misses = 0
        for _ in 0..<40 {
            var distance: CGFloat
            if element.exists {
                let middle = element.frame.midY
                if band.contains(middle), element.isHittable { return }
                // Positive: the element is below the band and the page has to move up.
                distance = middle > band.upperBound ? middle - band.upperBound + 24 : middle - band.lowerBound - 24
                distance = max(-step, min(step, distance))
            } else {
                misses += 1
                distance = misses <= 14 ? step : -step
            }
            anchor.press(
                forDuration: 0.05, thenDragTo: anchor.withOffset(CGVector(dx: 0, dy: -distance)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
            _ = element.waitForExistence(timeout: 0.5)
        }
        XCTFail("\(element) could not be brought into reach")
    }

    @MainActor
    func testEntityPagePassesAccessibilityAudit() throws {
        let (app, _) = openUnlinkedMentions()

        try AccessibilityAuditPolicy.audit(app, screen: "unlinkedMentions")
    }
}
