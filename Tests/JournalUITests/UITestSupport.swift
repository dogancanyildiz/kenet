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
    static func activateSystemAlertMonitor(in app: XCUIApplication) {
        // Interruption monitors need an interaction. Reselecting Today is harmless; tapping
        // the application's centre can complete a task in the fixture vault instead.
        let todayTab = tab(in: app, identifier: "tab.today")
        waitForExistence(todayTab)
        todayTab.tap()
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

    /// The split shell (iPad, regular × regular) has no tab bar: each tab's root is a sidebar row
    /// (`MacSidebarEntry.identifier`). People and places share one tab but are two rows.
    static let sidebarRows = [
        "tab.today": "sidebar.today", "tab.days": "sidebar.days", "tab.tasks": "sidebar.tasks",
        "tab.entities": "sidebar.people", "tab.goals": "sidebar.goals",
    ]

    /// The split shell's sidebar row for a tab identifier (`sidebar.<key>` stays as it is).
    static func sidebarIdentifier(forTab identifier: String) -> String {
        sidebarRows[identifier] ?? identifier
    }

    /// A sidebar row: the list cell around the row's identifier. The identifier reaches the
    /// row's icon and title as well, and the icon alone is not always hittable.
    @MainActor
    static func sidebarRow(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.cells.containing(.any, identifier: identifier).firstMatch
    }

    /// The split view's own button that brings a put-away sidebar back (system chrome:
    /// identifier first, then its label in either test language).
    @MainActor
    static func sidebarToggle(in app: XCUIApplication) -> XCUIElement {
        let labels = ["Kenar Çubuğunu Göster", "Kenar çubuğunu göster", "Show Sidebar", "Show sidebar"]
        return app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "ToggleSidebar", labels))
            .firstMatch
    }

    /// Brings the split shell's sidebar back when it is put away; false when there is no button.
    @MainActor
    @discardableResult
    static func revealSidebar(in app: XCUIApplication) -> Bool {
        let toggle = sidebarToggle(in: app)
        guard toggle.exists, toggle.isHittable else { return false }
        toggle.tourTap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
    }

    /// The split shell is showing: no tab bar, and the sidebar's Today row in the tree or the
    /// button that brings the sidebar back.
    @MainActor
    static func isSplitShell(_ app: XCUIApplication) -> Bool {
        guard !app.tabBars.firstMatch.exists else { return false }
        return element(in: app, identifier: "sidebar.today").exists || sidebarToggle(in: app).exists
    }

    /// Finds a tab by identifier, falling back to the tab bar's button at the known index. In
    /// the split shell the tab's sidebar row stands in for it.
    @MainActor
    static func tab(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let byId = app.tabBars.buttons.matching(identifier: identifier).firstMatch
        let row = sidebarRow(in: app, identifier: sidebarIdentifier(forTab: identifier))
        // Right after launch neither shell may be drawn yet: wait for one of them.
        let start = Date()
        repeat {
            if byId.exists { return byId }
            let hasTabBar = app.tabBars.firstMatch.exists
            if row.exists, !hasTabBar { return row }
            // A split shell with its sidebar put away (an upright iPad at launch).
            if !hasTabBar { revealSidebar(in: app) }
            if hasTabBar, Date().timeIntervalSince(start) > 3 { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date().timeIntervalSince(start) < 20
        let anyId = element(in: app, identifier: identifier)
        if anyId.waitForExistence(timeout: 2) { return anyId }
        let index = tabOrder.firstIndex(of: identifier) ?? 0
        return app.tabBars.firstMatch.buttons.element(boundBy: index)
    }

    /// Switches tabs (or sidebar rows) and waits for the screen marker; a selected tab whose
    /// content shows any list is accepted when the marker is not exposed by the simulator's
    /// accessibility tree. The split shell's list columns carry no screen marker of their own
    /// for Günlük and Kişiler; there the selected sidebar row and its content are measured.
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
        // A selected sidebar row needs no long wait for a marker its column may not have.
        let isSelectedRow = !app.tabBars.firstMatch.exists && tab.isSelected
        if marker.waitForExistence(timeout: isSelectedRow ? 3 : 15) { return }
        XCTAssertTrue(
            tab.isSelected,
            "Tab \(identifier) did not become selected "
                + "(keyboard covers screen: \(keyboardCoversScreen(in: app)))")
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
