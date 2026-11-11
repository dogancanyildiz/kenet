import XCTest

/// Today's goal card: a touch anywhere on the card but its plus opens the goal page; the value
/// line no longer opens a separate amount sheet (screens.md, Bugün, Hedefler). The vault is a
/// temporary copy of the sample fixture.
final class GoalCardTapUITests: XCTestCase {
    private var vaultURL: URL!
    /// Sample fixture: "Su", a number goal of 8 glasses.
    private let numberGoal = "Su"

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
    func testTouchOnValueLineOpensGoalPage() throws {
        let app = UITestSupport.launchApp(
            vaultURL: vaultURL, quickEntryText: nil, extraArguments: ScreenTourDriver.turkish)
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)

        // The card's open button: labelled with the goal's name alone.
        let card = app.buttons.matching(NSPredicate(format: "label == %@", numberGoal)).firstMatch
        UITestSupport.waitForExistence(card, timeout: 30)
        XCTAssertTrue(card.isHittable, "goal card is off screen")
        // Low on the card, where the value line ("0/8 bardak") sits.
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.85)).tap()

        let amountField = app.descendants(matching: .any)["field.goal.amount"]
        UITestSupport.waitForExistence(amountField, timeout: 15)
        XCTAssertTrue(
            app.staticTexts["Isı haritası"].waitForExistence(timeout: 10),
            "the touch did not open the goal page")
        XCTAssertFalse(app.buttons["Kaydet"].exists, "a separate amount sheet opened")
        XCTAssertTrue(app.buttons["Hedefe tamamla"].exists, "the page has no quick amount controls")
    }

    /// A past day's goal card opens the goal page on that day: "+1" adds to that day, not today,
    /// and a value typed and left by going back is written too (no Kaydet, no silent loss). The
    /// app works on its own copy of the vault, so the values are read back from the cards.
    @MainActor
    func testPastDayCardEditsThatDayAndBackWritesTypedValue() throws {
        let tour = ScreenTourDriver(
            directory: FileManager.default.temporaryDirectory, vaultURL: vaultURL, test: self, dumpsTree: false)
        let app = tour.app
        UITestSupport.waitForExistence(UITestSupport.element(in: app, identifier: "screen.today"), timeout: 30)
        try tour.home("tab.days", marker: "screen.days", title: "Günlük")
        // 27 September 2026 has no goal record in the sample vault.
        try tour.row("27 Eyl").tap()
        try tour.waitFor(ids: ["screen.day"])

        let card = app.buttons.matching(NSPredicate(format: "label == %@", numberGoal)).firstMatch
        for _ in 0..<4 where !(card.exists && card.isHittable) { tour.scrollPage() }
        XCTAssertTrue(card.isHittable, "the past day's goal card is off screen")
        card.tap()

        let editedDay = app.descendants(matching: .any)["goal.editedDay"]
        UITestSupport.waitForExistence(editedDay, timeout: 15)
        XCTAssertTrue(editedDay.label.contains("27 Eyl"), "the page edits \(editedDay.label), not 27 Eyl")

        // The day loads before it takes input: the quick step turns on then.
        let plusOne = app.buttons.matching(NSPredicate(format: "label == %@", "1 ekle")).firstMatch
        UITestSupport.waitForExistence(plusOne, timeout: 15)
        XCTAssertTrue(waitUntil { plusOne.isEnabled }, "the quick step stayed off")
        plusOne.tap()
        let field = app.descendants(matching: .any)["field.goal.amount"]
        XCTAssertTrue(waitUntil { (field.value as? String) == "1" }, "+1 did not add to 27 Eyl")

        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + "5")
        // Back without Enter or ✓: the page goes away and writes the typed value.
        app.buttons["button.back"].firstMatch.tap()
        try tour.waitFor(ids: ["screen.day"])
        XCTAssertTrue(
            waitUntil { (card.value as? String)?.contains("5/8") == true },
            "the typed value was lost on back: \(String(describing: card.value))")

        // Today kept its own value: "+1" on 27 Eyl did not reach it.
        try tour.home("tab.today", marker: "screen.today", title: nil)
        let todayCard = app.buttons.matching(NSPredicate(format: "label == %@", numberGoal)).firstMatch
        UITestSupport.waitForExistence(todayCard, timeout: 15)
        XCTAssertTrue(
            (todayCard.value as? String)?.hasPrefix("0/8") == true,
            "today changed: \(String(describing: todayCard.value))")
    }

    private func waitUntil(timeout: TimeInterval = 15, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return condition()
    }
}
