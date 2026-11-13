import XCTest

/// A task added from Bugün's quick entry reaches Görevler: the künye count and the list follow
/// the write without a relaunch (iPhone tab shell and iPad split shell alike).
/// The vault is a temporary copy of the sample fixture.
final class TasksRefreshUITests: XCTestCase {
    private var vaultURL: URL!
    private let taskTitle = "Kurgusal Yenileme Görevi"

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
    func testQuickEntryTaskReachesTasksTab() throws {
        // The text arrives through the DEBUG launch environment; the app runs in Turkish so
        // "yarın" is read as a due date.
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: "yarın \(taskTitle)",
            extraArguments: ["-tasks.view.mode", "list", "-tasks.view.list.section", "upcoming"]
                + ScreenTourDriver.turkish)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)

        // Görevler is drawn once before the write, so it has a list to keep or replace.
        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")
        let before = try openCount(in: app)

        UITestSupport.openTab(app, identifier: "tab.today", screen: "screen.today")
        let field = UITestSupport.quickEntryField(in: app)
        UITestSupport.waitForExistence(field, timeout: 30)
        let taskMode = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "quickEntry.mode.task", "Görev"))
            .firstMatch
        UITestSupport.waitForExistence(taskMode)
        taskMode.tap()
        if !(field.value as? String ?? "").contains(taskTitle) {
            field.tap()
            app.typeText("yarın \(taskTitle)")
        }
        let send = UITestSupport.element(in: app, identifier: "button.quickEntrySend")
        UITestSupport.waitForExistence(send)
        // `for … where` queried all 40 times (25 s on a CI runner); this loop stops once enabled.
        let enabled = Date().addingTimeInterval(4)
        while !send.isEnabled, Date() < enabled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(send.isEnabled, "send stayed disabled")
        send.tap()
        // The field empties once the line is written (a task due tomorrow is not on Bugün's list).
        XCTAssertTrue(
            waitUntilCleared(field, seconds: 30), "the quick entry kept its text: the task was not written")

        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")
        let deadline = Date().addingTimeInterval(10)
        var after = try openCount(in: app)
        while after == before, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            after = try openCount(in: app)
        }
        XCTAssertEqual(after, before + 1, "Görevler kept its count from before the quick entry task")
    }

    /// Waits until the quick entry no longer holds the task's text.
    @MainActor
    private func waitUntilCleared(_ field: XCUIElement, seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while ((field.value as? String) ?? "").contains(taskTitle), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return !((field.value as? String) ?? "").contains(taskTitle)
    }

    /// The leading number of the künye: the manşet element reads "Görevler, 14 açık · 11 devreden".
    /// Found by its identifier, not by "açık": a task title can hold that word too.
    @MainActor
    private func openCount(in app: XCUIApplication) throws -> Int {
        let headline = UITestSupport.element(in: app, identifier: "tasks.headline")
        UITestSupport.waitForExistence(headline, timeout: 15)
        let label = headline.label
        let afterTitle = label.firstIndex(of: ",").map { label[$0...] } ?? label[...]
        let digits = afterTitle.drop { !$0.isNumber }.prefix { $0.isNumber }
        return try XCTUnwrap(Int(digits), "no count in the künye: \(label)")
    }
}
