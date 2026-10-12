import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// `IndexStore.computeGoalStatuses` matches the read model's old `goalStatuses` construction: every
/// log of the goal through the day asked for. The goal list and the day page read this query.
@MainActor struct GoalStatusQueryTests {
    @Test func sampleAndSyntheticVaultsMatchGoalProgressFromContent() async throws {
        let sample = try TaskTestContext(sample: true)
        defer { sample.clean() }
        await sample.start()
        try await expectContent(sample)
        #expect(sample.store.content.goals.map(\.key) == ["kitap", "spor", "su"])

        let synthetic = try TaskTestContext()
        defer { synthetic.clean() }
        try SyntheticVault.generate(at: synthetic.root, configuration: .compact)
        await synthetic.start()
        try await expectContent(synthetic)
        #expect(synthetic.store.content.goals.count == 6)
    }

    @Test func aQueryThatOutlivesItsVaultIsNotAppliedToTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let today = try #require(store.content.derivedForDay)

        store.testingGoalStatusQueryDidFinish = {
            store.testingGoalStatusQueryDidFinish = nil
            await store.select(other)
        }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeGoalStatuses(today: today)
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        await store.select(context.root)
        #expect(try await store.computeGoalStatuses(today: today).map(\.definition.key) == ["kitap", "spor", "su"])
    }

    private func expectContent(_ context: TaskTestContext) async throws {
        let today = try #require(context.store.content.derivedForDay)
        let rows = try await context.store.computeGoalStatuses(today: today)
        #expect(rows.map(\.definition) == context.store.content.goals)
        #expect(!rows.isEmpty)
        // Today, and day pages back to before the first log.
        var day: CalendarDate? = today
        while let current = day, current.ordinal > today.ordinal - 60 {
            let rows = try await context.store.computeGoalStatuses(today: current)
            let expected = context.store.content.goalStatuses(today: current)
            #expect(TodayPresentation.goalStatuses(rows) == expected, Comment(rawValue: current.description))
            let logs = Dictionary(grouping: context.store.content.asSnapshot().goalLogs, by: \.key)
            for row in rows {
                let entries = (logs[row.definition.key] ?? []).compactMap(GoalLog.init(indexed:))
                #expect(row.score == GoalProgress.score(definition: row.definition, logs: entries, through: current))
            }
            day = current.addingDays(-7)
        }
    }
}
