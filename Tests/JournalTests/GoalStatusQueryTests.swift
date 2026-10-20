import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// `IndexStore.computeGoalStatuses` matches the read model's old `goalStatuses` construction: every
/// log of the goal through the day asked for. The goal list and the day page read this query. The
/// goal definitions, reserved keys, goal logs and notification goals match the read model's old
/// fields (`LegacyGoalFields`) they replace.
@MainActor struct GoalStatusQueryTests {
    @Test func sampleAndSyntheticVaultsMatchGoalProgressFromContent() async throws {
        let sample = try TaskTestContext(sample: true)
        defer { sample.clean() }
        await sample.start()
        try await expectContent(sample)
        try await expectFields(sample)
        #expect(try await sample.store.goalDefinitions().map(\.key) == ["kitap", "spor", "su"])

        let synthetic = try TaskTestContext()
        defer { synthetic.clean() }
        try SyntheticVault.generate(at: synthetic.root, configuration: .compact)
        await synthetic.start()
        try await expectContent(synthetic)
        try await expectFields(synthetic)
        #expect(try await synthetic.store.goalDefinitions().count == 6)
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
        let legacy = try LegacyGoalFields(root: context.root, today: today)
        let rows = try await context.store.computeGoalStatuses(today: today)
        #expect(rows.map(\.definition) == legacy.goals)
        #expect(!rows.isEmpty)
        // Today, and day pages back to before the first log.
        var day: CalendarDate? = today
        while let current = day, current.ordinal > today.ordinal - 60 {
            let rows = try await context.store.computeGoalStatuses(today: current)
            let expected = legacy.goalStatuses(today: current)
            #expect(TodayPresentation.goalStatuses(rows) == expected, Comment(rawValue: current.description))
            for row in rows {
                let entries = legacy.allLogs[row.definition.key] ?? []
                #expect(row.score == GoalProgress.score(definition: row.definition, logs: entries, through: current))
            }
            day = current.addingDays(-7)
        }
    }

    /// The goal fields that left the read model against the queries that replace them, and the
    /// editing model's goals against the old `goals`.
    private func expectFields(_ context: TaskTestContext) async throws {
        let store = context.store
        let today = try #require(store.content.derivedForDay)
        let legacy = try LegacyGoalFields(root: context.root, today: today)
        let rows = try await store.computeGoalDefinitions()
        #expect(rows.map(\.definition) == legacy.goals)
        let ids = Set(legacy.goals.map(\.id))
        let placeFiles = rows.compactMap { row in row.placeFile.map { (row.definition.id, $0) } }
        #expect(Dictionary(uniqueKeysWithValues: placeFiles) == legacy.goalPlaceFiles.filter { ids.contains($0.key) })
        #expect(try await store.computeReservedGoalKeys() == legacy.reservedGoalKeys)
        let start = try #require(today.addingDays(-399))
        let end = try #require(today.addingDays(6))
        #expect(try await store.computeGoalLogs(from: start, through: end) == legacy.windowLogs)
        let model = GoalDayModel(store: store, day: today)
        await model.load()
        #expect(model.goals == legacy.goals)
        // The daily reminder of each planned day names the goals the old fields named.
        let week = try await store.computeNotificationGoals(from: today, through: end)
        #expect(week.definitions == legacy.goals.filter { $0.period == .day })
        for offset in 0..<7 {
            let day = try #require(today.addingDays(offset))
            func pending(_ goals: [GoalDefinition], _ logs: [String: [GoalLog]]) -> [String] {
                goals.filter {
                    $0.period == .day
                        && !GoalProgress.compute(definition: $0, logs: logs[$0.key] ?? [], today: day).progress
                            .isComplete
                }.map(\.id)
            }
            #expect(pending(week.definitions, week.logs) == pending(legacy.goals, legacy.goalLogs))
        }
    }
}
