import XCTest

/// iPhone task list: a touch anywhere on a row without links completes the task, not only a
/// touch on the box; the "›" at the row's end opens the detail instead (screens.md, Ayrıntı).
/// The vault is a temporary copy of the sample fixture.
final class TaskRowTapUITests: XCTestCase {
    private var vaultURL: URL!

    // Fixture tasks without links. Both are overdue, so they open the first group of "Yaklaşan",
    // clear of the tab bar that floats over the bottom of the list.
    private let textLineTask = "Eski doküman arşivini temizle"
    private let dateLineTask = "Haftalık sprint hedeflerini belirle"
    private let dateLineDue = "14 Eyl"

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
    func testTouchOnEmptyRowAreaCompletesTask() throws {
        // The list section is restored from the last run; pin it so the rows are on screen.
        // The app runs in Turkish whatever the test language is: the date label is found by its text.
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: nil,
            extraArguments: ["-tasks.view.mode", "list", "-tasks.view.list.section", "upcoming"]
                + ScreenTourDriver.turkish)
        // No warm-up touch on the screen: on Bugün it would land on a task row and complete it.
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")

        // On the words of the text line: the line runs up to the "›" (one line, cut at its end),
        // so the room right of the words is the "›" target, which opens the detail.
        let first = try taskText(textLineTask, in: app)
        let firstFrame = first.frame
        touch(x: firstFrame.midX, y: firstFrame.midY, in: app)
        // A completed task leaves "Yaklaşan".
        XCTAssertTrue(
            first.waitForNonExistence(timeout: 15),
            "touch on the task text did not complete the task")

        // Right of the date, on the line under the words.
        let second = try taskText(dateLineTask, in: app)
        let date = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", dateLineDue)).firstMatch
        UITestSupport.waitForExistence(date)
        let dateFrame = date.frame
        XCTAssertGreaterThan(dateFrame.minY, second.frame.midY, "the date is not under the task text")
        touch(x: emptyX(rightOf: dateFrame, in: app), y: dateFrame.midY, in: app)
        XCTAssertTrue(
            second.waitForNonExistence(timeout: 15),
            "touch right of the task date did not complete the task")
    }

    /// The row's menu starts with "Bitti" in every shell: in the split shell (iPad) a touch on
    /// the row selects it, so the box and the menu are the ways to complete it.
    @MainActor
    func testRowMenuCompletesTask() throws {
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: nil,
            extraArguments: ["-tasks.view.mode", "list", "-tasks.view.list.section", "upcoming"]
                + ScreenTourDriver.turkish)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        UITestSupport.openTab(app, identifier: "tab.tasks", screen: "screen.tasks")

        let row = try taskText(textLineTask, in: app)
        row.press(forDuration: 1.2)
        let done = app.buttons.matching(NSPredicate(format: "label == %@", "Bitti")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the row menu has no \"Bitti\"")
        done.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 15), "\"Bitti\" in the row menu did not complete the task")
    }

    @MainActor
    private func touch(x: CGFloat, y: CGFloat, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    /// The row's text element, brought into the upper part of the screen. The weekly summary
    /// and project cards sit above the sections (screens.md), so the list is scrolled up by a
    /// drag in the left page margin (clear of the rows) when the row starts lower.
    @MainActor
    private func taskText(_ text: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        UITestSupport.waitForExistence(element, timeout: 30)
        for _ in 0..<3 where element.frame.maxY > app.frame.height * 0.6 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        XCTAssertLessThanOrEqual(
            element.frame.maxY, app.frame.height * 0.6, "task row is too low to touch safely: \(text)")
        XCTAssertTrue(element.isHittable, "task row is off screen: \(text)")
        return element
    }

    /// A point inside the row and clear of the drawn content: halfway between the content's
    /// trailing edge and the "›" target at the row's end (44 pt inside the card's 16 pt padding
    /// and the 16 pt page margin). A touch a few points from the "›" still lands on it.
    @MainActor
    private func emptyX(rightOf frame: CGRect, in app: XCUIApplication) -> CGFloat {
        let chevronMinX = app.frame.maxX - 16 - 16 - 44
        let x = (frame.maxX + chevronMinX) / 2
        XCTAssertGreaterThan(
            chevronMinX - frame.maxX, 40, "no empty area right of the content (frame \(frame))")
        return x
    }
}
