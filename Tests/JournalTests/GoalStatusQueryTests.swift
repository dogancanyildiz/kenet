import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// `IndexStore.computeGoalStatuses` matches `GoalProgress` over the read model's goal logs.
/// Screens keep reading `content` until a later slice binds them.
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
        for row in rows {
            let logs = context.store.content.goalLogs[row.definition.key] ?? []
            #expect(row.status == GoalProgress.compute(definition: row.definition, logs: logs, today: today))
            #expect(row.score == GoalProgress.score(definition: row.definition, logs: logs, through: today))
        }
    }
}
