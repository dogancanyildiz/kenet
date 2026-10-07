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
    static func launchApp(
        vaultURL: URL, quickEntryText: String? = smokeEventText, extraArguments: [String] = [],
        extraEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["JOURNAL_UITEST_VAULT"] = vaultURL.path
        if let quickEntryText {
            app.launchEnvironment["JOURNAL_UITEST_QUICK_ENTRY_TEXT"] = quickEntryText
        }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchArguments += extraArguments
        app.launchEnvironment.merge(extraEnvironment) { _, new in new }
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
                        button.tourTap()
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
        tab.tourTap()
        // iOS 26 tab bars sometimes swallow the first element tap; retry at the button's centre.
        if !waitUntilSelected(tab, timeout: 3) {
            dismissKeyboard(in: app)
            tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tourTap()
            _ = waitUntilSelected(tab, timeout: 5)
        }
        let marker = element(in: app, identifier: screen)
        if marker.waitForExistence(timeout: 15) { return }
        XCTAssertTrue(
            tab.isSelected,
            "Tab \(identifier) did not become selected (keyboard covers screen: \(keyboardCoversScreen(in: app)))")
        XCTAssertTrue(
            app.collectionViews.firstMatch.waitForExistence(timeout: 10)
                || app.tables.firstMatch.waitForExistence(timeout: 5)
                || app.scrollViews.firstMatch.waitForExistence(timeout: 5),
            "Screen \(screen) showed no content after switching tabs")
    }

    @MainActor
    static func waitUntilSelected(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return element.isSelected
    }

    /// The software keyboard covers the tab bar on CI simulators (no hardware keyboard).
    @MainActor
    static func dismissKeyboard(in app: XCUIApplication) {
        for _ in 0..<3 {
            guard keyboardCoversScreen(in: app) else { return }
            dismissKeyboardOnce(in: app)
        }
    }

    /// With a hardware keyboard attached (local simulators) the software keyboard exists off screen.
    @MainActor
    static func keyboardCoversScreen(in app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return false }
        return keyboard.frame.minY < app.frame.maxY
    }

    @MainActor
    private static func dismissKeyboardOnce(in app: XCUIApplication) {
        let hide = app.keyboards.buttons["Hide keyboard"]
        if hide.exists {
            hide.tourTap()
            if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) { return }
        }
        // iPhone keyboards have no hide key: the return key resigns focus (an empty quick entry
        // ignores the submit), then an interactive drag on the content as a last resort.
        let returnKey = app.keyboards.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label IN %@", "Return",
                ["Return", "return", "Done", "done", "Go", "Git", "Geç", "Bitti", "Gönder"])
        ).firstMatch
        if returnKey.exists, returnKey.isHittable {
            returnKey.tourTap()
            if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) { return }
        }
        let content = element(in: app, identifier: "screen.today")
        let start = (content.exists ? content : app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
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
