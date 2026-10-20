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

    /// The page's slot opens another day of the same vault with the previous model's goals and
    /// history, before its own load: the strip draws at once, with the new day's values and
    /// statuses. The new model takes no edit until it loaded. Another vault's model starts empty.
    @Test func anotherDayStartsFromThePreviousDaysGoalsAndHistory() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let monday = CalendarDate("2026-09-21")!
        let tuesday = CalendarDate("2026-09-22")!
        let slot = GoalDayModelSlot()
        let first = slot.model(store: context.store, day: monday)
        await first.load()
        try #require(first.goals.count == 3)

        let second = slot.model(store: context.store, day: tuesday)
        #expect(second !== first && second.day == tuesday)
        #expect(!second.hasLoaded && !second.isLoading, "no load has run for the new day")
        #expect(second.goals == first.goals)
        #expect(second.logs == first.logs)
        let water = try #require(second.goals.first { $0.key == "su" })
        // 22 September in the sample: su 9, kitap 35.
        #expect(second.value(for: water) == .number(9))
        #expect(
            second.status(for: water)
                == GoalProgress.compute(definition: water, logs: first.logs["su"] ?? [], today: tuesday))
        #expect(!second.canEdit)
        #expect(await !second.set(water, value: .number(1)))
        await second.load()
        #expect(second.canEdit && second.goals == first.goals)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        let third = slot.model(store: context.store, day: tuesday)
        #expect(third !== second)
        #expect(third.goals.isEmpty && third.logs.isEmpty, "another vault's model starts empty")
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
