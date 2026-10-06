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

    @MainActor
    static func waitForExistence(_ element: XCUIElement, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)")
    }

    @MainActor
    static func element(in app: XCUIApplication, identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
