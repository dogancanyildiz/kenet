import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

/// The goal page's amount panel without the view (``GoalAmountEditor``): what a commit writes to
/// the day file, and what it leaves alone. Each test runs on a temporary copy of the sample vault.
@MainActor
struct GoalAmountEditorTests {
    private let turkish = Locale(identifier: "tr_TR")

    private func editor(
        _ context: TaskTestContext, day: CalendarDate, key: String = "su"
    ) async throws -> GoalAmountEditor {
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        let goal = try #require(model.goals.first { $0.key == key || $0.name == key })
        return GoalAmountEditor(dayModel: model, goal: goal, locale: turkish)
    }

    private func file(_ context: TaskTestContext, _ day: CalendarDate) -> URL {
        context.root.appendingPathComponent("journal/\(day).md")
    }

    // MARK: - Y1: a shown value is never written back

    @Test func unchangedValueIsNotWrittenOnBlurWhateverItsPrecision() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-21")!
        let setup = try await editor(context, day: day)
        #expect(await setup.dayModel.set(setup.goal, value: .number(1.23456789)))
        let before = try Data(contentsOf: file(context, day))
        #expect(String(decoding: before, as: UTF8.self).contains("  su: 1.23456789\n"))

        let shown = try await editor(context, day: day)
        // Shown in full, with the Turkish decimal mark: nothing rounded to six places.
        #expect(shown.text == "1,23456789")
        #expect(!shown.isDirty)
        // Focus taken and given back without typing: the commit has nothing to write.
        #expect(await shown.commit())
        #expect(try Data(contentsOf: file(context, day)) == before)
        // The same amount typed another way writes nothing either.
        shown.text = "1.23456789"
        #expect(await shown.commit())
        #expect(try Data(contentsOf: file(context, day)) == before)
    }

    // MARK: - Write path

    @Test func typedTurkishThousandsWriteTodayFile() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let editor = try await editor(context, day: context.today)
        editor.text = "7.500"
        #expect(await editor.commit())
        #expect(String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains("  su: 7500\n"))
        #expect(editor.text == "7500" && !editor.isDirty && editor.errorText == nil)
    }

    @Test func pastDayWritesThatDayOnly() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-17")!
        let before = String(decoding: try Data(contentsOf: file(context, day)), as: UTF8.self)
        let editor = try await editor(context, day: day)
        #expect(editor.dayValue == 7)
        #expect(await editor.add(2))
        #expect(
            String(decoding: try Data(contentsOf: file(context, day)), as: UTF8.self)
                == before.replacingOccurrences(of: "su: 7", with: "su: 9"))
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
    }

    @Test func quickStepTwiceAddsTwice() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let editor = try await editor(context, day: context.today)
        #expect(await editor.add(500))
        #expect(await editor.add(500))
        #expect(String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains("  su: 1000\n"))
    }

    @Test func removeDropsOnlyThatDaysGoalLine() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-21")!
        let before = String(decoding: try Data(contentsOf: file(context, day)), as: UTF8.self)
        let editor = try await editor(context, day: day)
        #expect(await editor.remove())
        #expect(
            String(decoding: try Data(contentsOf: file(context, day)), as: UTF8.self)
                == before.replacingOccurrences(of: "  su: 8\n", with: ""))
        #expect(!editor.hasRecord && editor.text == "0")
    }

    @Test func emptyTextGoesBackWithoutWriting() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-21")!
        let before = try Data(contentsOf: file(context, day))
        let editor = try await editor(context, day: day)
        editor.text = " "
        #expect(await editor.commit())
        #expect(editor.text == "8")
        editor.text = "0x10"
        #expect(editor.isInvalid)
        #expect(await !editor.commit())
        #expect(try Data(contentsOf: file(context, day)) == before)
    }

    @Test func closedVaultDoesNotWriteAndSaysSo() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        // Not started: no writer, so the vault takes no edit.
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        let goal = try #require(
            GoalDefinition(id: "goals/Su.md", key: "su", name: "Su", period: .day, kind: .number, target: 8))
        let editor = GoalAmountEditor(dayModel: model, goal: goal, locale: turkish)
        editor.transientWait = .milliseconds(200)
        #expect(editor.isLocked)
        editor.text = "5"
        #expect(await !editor.commit())
        #expect(editor.errorText != nil && editor.text == "5")
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
    }

    // MARK: - O3: a reload in flight does not drop the write

    @Test func commitDuringReloadWaitsAndWrites() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let editor = try await editor(context, day: context.today)
        let reload = Task { await editor.dayModel.load() }
        for _ in 0..<1000 where !editor.dayModel.isLoading { await Task.yield() }
        editor.text = "3"
        #expect(await editor.commit())
        await reload.value
        #expect(String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains("  su: 3\n"))
    }

    // MARK: - O5: completing a weekly goal on a past day counts the whole week

    @Test func completingAPastDayOfAWeekCountsLaterDays() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await context.store.createGoal(name: "Koşu", period: .week, kind: .number, target: 50, unit: "km")
        let monday = CalendarDate("2026-09-28")!
        let wednesday = CalendarDate("2026-09-30")!
        let setup = try await editor(context, day: wednesday, key: "Koşu")
        #expect(await setup.apply(20))
        let editor = try await editor(context, day: monday, key: "Koşu")
        #expect(await editor.apply(5))
        #expect(editor.periodTotal == 25)
        #expect(editor.completionValue == 30)
        #expect(await editor.completeTarget())
        #expect(String(decoding: try Data(contentsOf: file(context, monday)), as: UTF8.self).contains(": 30\n"))
        #expect(editor.periodTotal == 50)
        #expect(editor.completionValue == nil)
    }

    // MARK: - O6: reading what was typed

    @Test(arguments: [
        ("7.500", "tr_TR", 7500.0),
        ("1.234.567", "tr_TR", 1_234_567),
        ("2,5", "tr_TR", 2.5),
        ("2.5", "tr_TR", 2.5),
        ("1.234,5", "tr_TR", 1234.5),
        ("0.500", "tr_TR", 0.5),
        ("7,500", "en_US", 7500),
        ("2.5", "en_US", 2.5),
        ("2,5", "en_US", 2.5),
        ("1,234.5", "en_US", 1234.5),
        (" 8 ", "tr_TR", 8),
        (",5", "tr_TR", 0.5),
    ])
    func readsTypedAmounts(text: String, locale: String, expected: Double) {
        #expect(GoalValueModel.number(text, locale: Locale(identifier: locale)) == expected)
    }

    @Test(arguments: ["0x10", "-0", "-1", "1e3", "nan", "inf", "", ".", "1.2.3", "1,2.3,4", "7 500", "٣"])
    func refusesWhatIsNotAnAmount(text: String) {
        #expect(GoalValueModel.number(text, locale: turkish) == nil)
    }

    /// The forms' plain reader keeps one mark as the decimal mark; it now refuses hex and exponent.
    @Test func plainReaderKeepsItsRules() {
        #expect(GoalValueModel.number("7,5") == 7.5)
        #expect(GoalValueModel.number("1,500") == 1.5)
        #expect(GoalValueModel.number("0x10") == nil)
        #expect(GoalValueModel.number("1e3") == nil)
        #expect(GoalValueModel.number("1.234,5") == nil)
    }

    @Test func displayIsLosslessAndPlain() {
        #expect(GoalAmountEditor.display(7500, locale: turkish) == "7500")
        #expect(GoalAmountEditor.display(-0.0, locale: turkish) == "0")
        #expect(GoalAmountEditor.display(1.23456789, locale: turkish) == "1,23456789")
        #expect(GoalAmountEditor.display(2.5, locale: Locale(identifier: "en_US")) == "2.5")
        for value in [0.1 + 0.2, 1.23456789, 1234.5, 1e-7] {
            let shown = GoalAmountEditor.display(value, locale: turkish)
            #expect(GoalValueModel.number(shown, locale: turkish) == value, "\(shown)")
        }
    }
}
