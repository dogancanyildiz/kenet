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
}
