import Foundation
import XCTest

enum UITestSupport {
    static let smokeEventText = "smoke event from ui test 42"

    /// Copies `Fixtures/vaults/sample` into a unique temporary directory for one launch.
    static func prepareSampleVault() throws -> URL {
        let fixture = repositoryRoot().appendingPathComponent("Fixtures/vaults/sample", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fixture.path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            throw XCTSkip("Sample fixture vault missing at \(fixture.path)")
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalUITest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: fixture, to: destination)
        return destination
    }

    static func repositoryRoot(filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }

    @MainActor
    static func launchApp(vaultURL: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UITEST_VAULT"] = vaultURL.path
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    /// Dismisses first-run system permission sheets without relying on localized chrome.
    static func installSystemAlertMonitor(on test: XCTestCase) {
        test.addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            let labels = [
                "Allow", "Allow While Using App", "Allow Once", "OK", "Continue",
                "Don’t Allow", "Don't Allow", "Not Now", "Later",
                "İzin Ver", "Uygulamayı Kullanırken İzin Ver", "Bir Kez İzin Ver", "Tamam",
                "İzin Verme", "Şimdi Değil",
            ]
            // The monitor runs on the main thread; the CI SDK marks XCUIElement as main-actor only.
            return MainActor.assumeIsolated {
                for label in labels {
                    let button = alert.buttons[label]
                    if button.exists {
                        button.tap()
                        return true
                    }
                }
                return false
            }
        }
    }

    @MainActor
    static func waitForExistence(_ element: XCUIElement, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
    }

    @MainActor
    static func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Tab order in `PhoneNavigation`; older simulators do not expose `Tab` identifiers.
    static let tabOrder = ["tab.today", "tab.days", "tab.tasks", "tab.entities", "tab.goals"]

    /// Finds a tab by identifier, falling back to the tab bar's button at the known index.
    @MainActor
    static func tab(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let byId = app.tabBars.buttons.matching(identifier: identifier).firstMatch
        if byId.waitForExistence(timeout: 3) { return byId }
        let anyId = element(in: app, identifier: identifier)
        if anyId.waitForExistence(timeout: 2) { return anyId }
        let index = tabOrder.firstIndex(of: identifier) ?? 0
        return app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    /// Switches tabs and waits for the screen marker; a selected tab whose content shows any
    /// list is accepted when the marker is not exposed by the simulator's accessibility tree.
    @MainActor
    static func openTab(_ app: XCUIApplication, identifier: String, screen: String) {
        dismissKeyboard(in: app)
        let tab = tab(in: app, identifier: identifier)
        waitForExistence(tab)
        tab.tap()
        let marker = element(in: app, identifier: screen)
        if marker.waitForExistence(timeout: 15) { return }
        XCTAssertTrue(tab.isSelected, "Tab \(identifier) did not become selected")
        XCTAssertTrue(
            app.collectionViews.firstMatch.waitForExistence(timeout: 10)
                || app.tables.firstMatch.waitForExistence(timeout: 5)
                || app.scrollViews.firstMatch.waitForExistence(timeout: 5),
            "Screen \(screen) showed no content after switching tabs")
    }

    /// The software keyboard covers the tab bar on CI simulators (no hardware keyboard).
    @MainActor
    static func dismissKeyboard(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let hide = app.keyboards.buttons["Hide keyboard"]
        if hide.exists {
            hide.tap()
        } else {
            app.swipeDown()
        }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    @MainActor
    static func quickEntryField(in app: XCUIApplication) -> XCUIElement {
        let byId = app.textFields["field.quickEntry"]
        if byId.waitForExistence(timeout: 2) { return byId }
        let anyId = element(in: app, identifier: "field.quickEntry")
        if anyId.waitForExistence(timeout: 2) { return anyId }
        // Fallback: first text field inside the quick-entry bar.
        let bar = element(in: app, identifier: "bar.quickEntry")
        if bar.waitForExistence(timeout: 5) {
            let nested = bar.textFields.firstMatch
            if nested.waitForExistence(timeout: 2) { return nested }
        }
        return byId
    }
}
