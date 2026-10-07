import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor
struct GoalEditingTests {
    let day = CalendarDate("2026-09-27")!

    @Test func sampleStripShowsDailyValuesSeparatelyFromWeeklySuccess() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        #expect(model.goals.map(\.name) == ["Kitap", "Spor", "Su"])
        for goal in model.goals { #expect(model.value(for: goal) == nil && !model.isComplete(for: goal)) }
        let sport = try #require(model.goals.first { $0.key == "spor" })
        #expect(model.status(for: sport).progress == GoalAmount(done: 3, target: 3))
        #expect(model.status(for: sport).streak == 2)
        #expect(model.status(for: sport).longestStreak == 2)
        let previous = GoalDayModel(store: context.store, day: CalendarDate("2026-09-25")!)
        await previous.load()
        let thursday = GoalDayModel(store: context.store, day: CalendarDate("2026-09-24")!)
        await thursday.load()
        #expect(thursday.status(for: sport).progress == GoalAmount(done: 2, target: 3))
        #expect(previous.value(for: sport) == .boolean(true))
        #expect(previous.isComplete(for: sport))
        #expect(previous.value(for: try #require(model.goals.first { $0.key == "kitap" })) == .number(25))
        #expect(previous.value(for: try #require(model.goals.first { $0.key == "su" })) == .number(10))
    }

    @Test func toggleWritesOnlyGoalEntryAndRemovesInsteadOfFalse() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("journal/\(day).md")
        let before = try Data(contentsOf: file)
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        let sport = try #require(model.goals.first { $0.key == "spor" })
        #expect(await model.toggle(sport))
        let expected = String(decoding: before, as: UTF8.self).replacingOccurrences(
            of: "date: 2026-09-27\n", with: "date: 2026-09-27\ngoals:\n  spor: true\n")
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
        #expect(context.store.content.goalLogs["spor"]?.last { $0.day == day }?.value == .boolean(true))
        #expect(context.store.content.day(on: day).hasGoalRecords)
        #expect(model.isComplete(for: sport))
        #expect(await model.toggle(sport))
        let removed = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!context.store.content.day(on: day).hasGoalRecords)
        #expect(!removed.contains("spor:"))
        #expect(!removed.contains("false"))
        #expect(
            removed
                == String(decoding: before, as: UTF8.self).replacingOccurrences(
                    of: "date: 2026-09-27\n", with: "date: 2026-09-27\ngoals:\n"))
    }

    @Test func numericEditorStepsValidatesWritesAndRemoves() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        let editor = GoalValueModel(dayModel: model, goal: water)
        editor.step(-1)
        #expect(editor.value == 0)
        editor.amount = "7,5"
        editor.step(1)
        #expect(editor.value == 8.5)
        #expect(await editor.save())
        #expect(model.value(for: water) == .number(8.5))
        #expect(model.isComplete(for: water))
        #expect(await !editor.save())
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/\(day).md"))
        #expect(String(decoding: bytes, as: UTF8.self).contains("  su: 8.5\n"))
        let invalid = GoalValueModel(dayModel: model, goal: water)
        for text in ["-1", "nan", "inf", "", "2x"] {
            invalid.amount = text
            #expect(!invalid.canSave)
        }
        #expect(await invalid.save(remove: true))
        #expect(model.value(for: water) == nil)
        #expect(context.store.content.goalLogs["su"]?.allSatisfy { $0.day != day } == true)
    }

    @Test func historicalCorrectionPreservesNeighbourValuesCommentsAndBody() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let date = CalendarDate("2026-09-17")!
        let file = context.root.appendingPathComponent("journal/\(date).md")
        let before = try Data(contentsOf: file)
        let model = GoalDayModel(store: context.store, day: date)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        #expect(await model.set(water, value: .number(8)))
        #expect(
            try Data(contentsOf: file)
                == Data(String(decoding: before, as: UTF8.self).replacingOccurrences(of: "su: 7", with: "su: 8").utf8))
        #expect(model.status(for: water).progress.isComplete)
    }

    @Test func yearlyBookCardUsesYearTotalAndHistoryHeatmap() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try await context.store.setField(at: "goals/Kitap.md", key: "period", value: .text("year"))
        try await context.store.setField(at: "goals/Kitap.md", key: "target", value: .number("365"))
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        let book = try #require(model.goals.first { $0.key == "kitap" })
        let status = model.status(for: book)
        #expect(status.yearDone == 320)
        #expect(status.yearProgress == GoalAmount(done: 320, target: 365))
        #expect(status.progress == status.yearProgress)
        let marks = GoalProgress.heatmap(
            definition: book, logs: model.logs[book.key] ?? [], from: day.addingDays(-83)!, to: day)
        #expect(marks.count == 84)
        #expect(marks[day] == GoalDayMark.none)
        #expect(marks[CalendarDate("2026-09-26")!] == .partial)
    }

    @Test func oldRecordsRemainEditableOutsideSnapshotWindow() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let old = CalendarDate("2024-01-01")!
        try await context.store.setGoal(on: old, key: "su", value: .number(7))
        #expect(context.store.content.goalLogs["su"]?.allSatisfy { $0.day != old } == true)
        let model = GoalDayModel(store: context.store, day: old)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        #expect(model.value(for: water) == .number(7))
        #expect(await model.set(water, value: .number(8)))
        #expect(
            String(
                decoding: try Data(contentsOf: context.root.appendingPathComponent("journal/2024-01-01.md")),
                as: UTF8.self
            ).contains("  su: 8\n"))
    }

    @Test func externalRefreshUpdatesDefinitionsAndValues() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: day)
        await model.load()
        let source = "---\ntype: journal\ndate: 2026-09-27\ngoals:\n  su: 3\n---\n"
        try Data(source.utf8).write(to: context.root.appendingPathComponent("journal/\(day).md"))
        await context.store.refresh()
        await model.load()
        #expect(model.value(for: try #require(model.goals.first { $0.key == "su" })) == .number(3))
        #expect(context.store.content.goalLogs["su"]?.last { $0.day == day }?.value == .number(3))
    }
}
