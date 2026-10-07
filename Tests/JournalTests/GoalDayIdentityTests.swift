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

    @Test func goalStripIdentityChangesWithDayAndVault() {
        let day = CalendarDate("2026-09-20")!
        let a = GoalStripIdentity.key(day: day, vaultPath: "/tmp/vault-a")
        let b = GoalStripIdentity.key(day: day, vaultPath: "/tmp/vault-b")
        let next = GoalStripIdentity.key(day: CalendarDate("2026-09-21")!, vaultPath: "/tmp/vault-a")
        #expect(a != b)
        #expect(a != next)
        #expect(a == day.description + "/tmp/vault-a")
        #expect(
            GoalStripIdentity.key(day: day, vaultPath: nil) == day.description,
            "nil vault path must not invent a suffix")
    }

    /// The pure key is tested above; this guards that `DayView` actually applies it. Without the
    /// identity the goal strip keeps yesterday's model after midnight and writes to the wrong day.
    @Test func dayViewAppliesGoalStripIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("App/Screens/Today/DayView.swift"), encoding: .utf8)
        #expect(source.contains(".id(GoalStripIdentity.key("))
    }
}
