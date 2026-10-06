import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

/// Y2: GoalDayModel must be rebuilt when the day (or vault) identity changes.
@MainActor
struct GoalDayIdentityTests {
    @Test func goalDayModelDayMatchesConstructedDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let monday = CalendarDate("2026-09-21")!
        let tuesday = CalendarDate("2026-09-22")!
        let first = GoalDayModel(store: context.store, day: monday)
        await first.load()
        #expect(first.day == monday)
        let second = GoalDayModel(store: context.store, day: tuesday)
        await second.load()
        #expect(second.day == tuesday)
        #expect(first.day != second.day)
        // Writing through the new model targets the new day file.
        let water = try #require(second.goals.first { $0.key == "su" })
        #expect(await second.set(water, value: .number(1)))
        let tuesdayFile = context.root.appendingPathComponent("journal/2026-09-22.md")
        let text = String(decoding: try Data(contentsOf: tuesdayFile), as: UTF8.self)
        #expect(text.contains("su: 1"))
        let mondayFile = context.root.appendingPathComponent("journal/2026-09-21.md")
        if FileManager.default.fileExists(atPath: mondayFile.path) {
            let mondayText = String(decoding: try Data(contentsOf: mondayFile), as: UTF8.self)
            #expect(!mondayText.contains("su: 1"))
        }
    }

    @Test func dayViewRecreatesGoalStripIdentityPerDay() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Screens/Today/DayView.swift"),
            encoding: .utf8)
        #expect(
            source.contains(".id(date.description + (store.vaultURL?.path ?? \"\"))"),
            "GoalStripView must reset GoalDayModel when day or vault changes")
    }
}
