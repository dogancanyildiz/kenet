import XCTest

/// Takvime etkinlik ekleme, ayrıntı ve silme, EventKit yerine bellekteki takvimle
/// (`JOURNAL_UITEST_CALENDAR=memory`). Kasa örnek kasanın geçici kopyasıdır.
final class CalendarEventUITests: XCTestCase {
    private var vaultURL: URL!
    private let title = "Kurgusal ders 7"

    override func setUpWithError() throws {
        continueAfterFailure = false
        UITestSupport.installSystemAlertMonitor(on: self)
        vaultURL = try UITestSupport.prepareSampleVault()
    }

    override func tearDownWithError() throws {
        if let vaultURL { try? FileManager.default.removeItem(at: vaultURL) }
    }

    @MainActor
    func testAddOpenAndDeleteEvent() throws {
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: nil, extraArguments: ScreenTourDriver.turkish,
            extraEnvironment: ["JOURNAL_UITEST_CALENDAR": "memory"])
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        // Adding and deleting an event writes to the calendar only: the vault the app works on
        // (its own copy) stays byte for byte.
        let appVault = try UITestSupport.waitForAppVault(for: vaultURL)
        let vaultBefore = try UITestSupport.fileContents(of: appVault)
        XCTAssertEqual(
            vaultBefore, try UITestSupport.fileContents(of: vaultURL), "the app's copy is not the prepared vault")

        // An empty day offers one way to add: the card's row (the header "+" comes with events).
        XCTAssertFalse(app.buttons["button.calendar.add"].exists, "an empty day shows two add buttons")
        let add = app.buttons["button.calendar.addEmpty"]
        scrollUntilHittable(add, in: app)
        add.tap()

        let field = app.textFields["field.calendarEvent.title"]
        UITestSupport.waitForExistence(field)
        field.tap()
        field.typeText(title)
        let save = app.buttons["button.calendarEvent.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), "the form did not close after saving")

        let row = app.descendants(matching: .any).matching(identifier: "row.calendarEvent").firstMatch
        UITestSupport.waitForExistence(row)
        XCTAssertTrue(row.label.contains(title), "the new event's row reads \(row.label)")
        scrollUntilHittable(row, in: app)
        row.tap()

        let delete = app.buttons["button.calendarEvent.delete"]
        UITestSupport.waitForExistence(delete)
        // "Vazgeç" in the edit form goes back to the detail, not out of the sheet.
        app.buttons["button.calendarEvent.edit"].tap()
        let cancel = app.buttons["button.calendarEvent.cancel"]
        UITestSupport.waitForExistence(cancel)
        cancel.tap()
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Vazgeç left the event's detail")
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Etkinliği sil"))
            .allElementsBoundByIndex.last { $0.isHittable && $0.identifier != "button.calendarEvent.delete" }
        try XCTUnwrap(confirm, "no delete confirmation").tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10), "the deleted event is still on Today")
        XCTAssertEqual(try UITestSupport.fileContents(of: appVault), vaultBefore, "a calendar write changed the vault")
    }

    @MainActor
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        UITestSupport.waitForExistence(element)
        // The quick entry capsule and the tab bar float over the bottom of the page: bring the
        // element into the upper half before touching it.
        let limit = app.windows.firstMatch.frame.height * 0.55
        var tries = 0
        while (!element.isHittable || element.frame.maxY > limit) && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "\(element) is not reachable")
    }
}
