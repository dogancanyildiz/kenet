import XCTest

@MainActor
final class QuickEntryLinkUITests: XCTestCase {
    func testWriteLinkFocusesTodayComposer() throws {
        let vault = try UITestSupport.prepareSampleVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let app = UITestSupport.launchApp(vaultURL: vault, quickEntryText: nil)
        defer { app.terminate() }
        UITestSupport.waitForExistence(UITestSupport.quickEntryField(in: app))
        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")
        app.open(URL(string: "kenet-widget://write")!)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let field = UITestSupport.quickEntryField(in: app)
        // The composer owns keyboard focus without a tap. Focus is read from the element rather
        // than proven with a long typed probe: the bar re-renders on every keystroke and a loaded
        // CI runner dropped characters of a sentence typed in one go.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let focus = expectation(for: focused, evaluatedWith: field)
        XCTAssertEqual(XCTWaiter().wait(for: [focus], timeout: 10), .completed)
        app.typeText("q")
        XCTAssertTrue(
            XCTWaiter().wait(
                for: [expectation(for: NSPredicate(format: "value == %@", "q"), evaluatedWith: field)], timeout: 10)
                == .completed)
    }
}
