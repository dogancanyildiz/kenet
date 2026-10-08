import XCTest

/// iPhone task list: a touch anywhere on a row without links completes the task, not only a
/// touch on the box or on the words. The vault is a temporary copy of the sample fixture.
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

        // Right of the words, on the text line.
        let first = try taskText(textLineTask, in: app)
        let firstFrame = first.frame
        touch(x: emptyX(rightOf: firstFrame, in: app), y: firstFrame.midY, in: app)
        // A completed task leaves "Yaklaşan".
        XCTAssertTrue(
            first.waitForNonExistence(timeout: 15),
            "touch right of the task text did not complete the task")

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

    @MainActor
    private func touch(x: CGFloat, y: CGFloat, in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
    }

    /// The row's text element, in the upper part of the first screen.
    @MainActor
    private func taskText(_ text: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        UITestSupport.waitForExistence(element, timeout: 30)
        XCTAssertLessThanOrEqual(
            element.frame.maxY, app.frame.height * 0.6, "task row is too low to touch safely: \(text)")
        XCTAssertTrue(element.isHittable, "task row is off screen: \(text)")
        return element
    }

    /// A point inside the row and clear of the drawn content: between the content's trailing
    /// edge and the page margin.
    @MainActor
    private func emptyX(rightOf frame: CGRect, in app: XCUIApplication) -> CGFloat {
        let x = app.frame.maxX - 28
        XCTAssertGreaterThan(x, frame.maxX + 20, "no empty area right of the content (frame \(frame))")
        return x
    }
}
