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
        // Typing without tapping proves that the composer already owns keyboard focus.
        app.typeText("quick entry link focus probe")
        XCTAssertEqual(field.value as? String, "quick entry link focus probe")
    }
}
