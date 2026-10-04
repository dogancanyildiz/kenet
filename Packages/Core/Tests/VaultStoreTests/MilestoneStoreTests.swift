import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultStore

struct MilestoneStoreTests {
    @Test func creationCompletionRemovalAndRebuildPreserveBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let path = try await vault.store.creatingGoal(name: "Portfolio", period: .year, kind: .milestone, target: 1)
        let expected = try Data(
            contentsOf: Fixtures.root().appendingPathComponent("goals/creation/milestone-expected.md"))
        #expect(try vault.bytes(path) == expected)
        #expect(Data(RawDocument(bytes: expected).serialized()) == expected)
        #expect(try vault.index.goalDefinitions().first?.kind == .milestone)
        let day = CalendarDate("2026-10-04")!
        let source = try String(
            contentsOf: Fixtures.root().appendingPathComponent("goals/writes/milestone-input.md"), encoding: .utf8)
        let journal = "journal/2026-10-04.md"
        try vault.write(journal, source)
        _ = try await vault.store.settingGoalValue(on: day, key: "portfolio", value: .boolean(true))
        #expect(
            try vault.bytes(journal)
                == Data(
                    source.replacingOccurrences(of: "---\nUnchanged", with: "  portfolio: true\n---\nUnchanged").utf8))
        await #expect(throws: EditError.invalidValue) {
            try await vault.store.settingGoalValue(on: day.addingDays(1)!, key: "portfolio", value: .boolean(true))
        }
        _ = try await vault.store.settingGoalValue(on: day, key: "portfolio", value: nil)
        #expect(try vault.bytes(journal) == Data(source.utf8))
        try vault.check()
    }

    @Test func milestoneRejectsNonYearDefinition() async throws {
        #expect(GoalDefinition(id: "x", key: "x", name: "X", period: .day, kind: .milestone) == nil)
        let vault = try StoreVault()
        defer { vault.remove() }
        await #expect(throws: EditError.invalidValue) {
            try await vault.store.creatingGoal(name: "Invalid", period: .week, kind: .milestone, target: 1)
        }
    }
}
