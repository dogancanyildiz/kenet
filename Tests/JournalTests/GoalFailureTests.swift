import Foundation
import GoalTracking
import SQLite3
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct GoalFailureTests {
    @Test func savedButUnindexedCreationCannotBeRepeated() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let connection = try rejectingIndex(context)
        defer { sqlite3_close(connection) }
        let model = GoalCreationModel(store: context.store)
        model.name = "Su İçme"
        #expect(await model.save())
        #expect(model.isSaved && model.errorText != nil && !model.canSave)
        let file = context.store.vaultURL!.appendingPathComponent("goals/Su İçme.md")
        let saved = try Data(contentsOf: file)
        #expect(await !model.save())
        #expect(try Data(contentsOf: file) == saved)
        #expect(sqlite3_exec(connection, "DROP TRIGGER reject_goals", nil, nil, nil) == SQLITE_OK)
        await context.store.refresh(rebuild: true)
        #expect(context.store.content.goals.first?.key == "su-icme")
    }

    @Test func savedButUnindexedAmountRemainsSavedWithVisibleError() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        let goal = try #require(model.goals.first { $0.key == "su" })
        let connection = try rejectingIndex(context)
        defer { sqlite3_close(connection) }
        let editor = GoalValueModel(dayModel: model, goal: goal)
        editor.amount = "8"
        #expect(await editor.save())
        #expect(editor.isSaved && model.errorText != nil)
        #expect(model.value(for: goal) == .number(8))
        #expect(await !editor.save())
        #expect(String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains("  su: 8\n"))
        #expect(sqlite3_exec(connection, "DROP TRIGGER reject_goals", nil, nil, nil) == SQLITE_OK)
        await context.store.refresh(rebuild: true)
        #expect(
            context.store.content.goalLogs["su"]?.contains { $0.day == context.today && $0.value == .number(8) } == true
        )
    }

    @Test func boundedSnapshotKeepsAllHistoryLongestStreak() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await context.store.createGoal(name: "Run", period: .day, kind: .boolean, target: 1, unit: nil)
        for day in ["2024-01-01", "2024-01-02"] {
            try await context.store.setGoal(on: CalendarDate(day)!, key: "run", value: .boolean(true))
        }
        #expect(context.store.content.goalLogs["run"]?.isEmpty == true)
        #expect(context.store.content.goalStatuses["run"]?.longestStreak == 2)
        let model = GoalDayModel(store: context.store, day: LocalDay.today())
        await model.load()
        #expect(model.logs["run"]?.count == 2)
        #expect(model.status(for: try #require(model.goals.first)).longestStreak == 2)
    }

    private func rejectingIndex(_ context: TaskTestContext) throws -> OpaquePointer {
        let database = try #require(
            FileManager.default.contentsOfDirectory(
                at: context.directory.appendingPathComponent("indexes"), includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "sqlite" })
        var connection: OpaquePointer?
        #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        #expect(
            sqlite3_exec(
                handle,
                "CREATE TRIGGER reject_goals BEFORE INSERT ON files BEGIN SELECT RAISE(ABORT, 'test failure'); END;",
                nil, nil, nil) == SQLITE_OK)
        return handle
    }
}
