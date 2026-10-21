import Foundation
import GRDB
import GoalTracking
import VaultFormat

/// One valid goal definition with the status and score `GoalProgress` computes from its logs.
public struct GoalStatusRow: Sendable, Equatable {
    public let definition: GoalDefinition
    public let status: GoalStatus
    /// `GoalProgress.score` through `today`. For an open daily goal this counts today; `status.score` does not.
    public let score: Int?
    public var graceDaysAvailable: Int { status.graceDaysAvailable }
    public var graceSpentDays: [CalendarDate] { status.graceSpentDays }

    public init(definition: GoalDefinition, status: GoalStatus, score: Int?) {
        self.definition = definition
        self.status = status
        self.score = score
    }
}

extension VaultIndex {
    /// Status and score for every valid goal definition on `today`.
    ///
    /// Every log through `today` counts: a chain or longest streak older than a year is not cut
    /// short (the goal list and detail have always shown the whole history). Later logs change
    /// nothing in `GoalProgress`, so they are not read. Logs are read with one query, in file
    /// order. A day with two rows keeps the later file: `GoalProgress` stores the last value for a day.
    public func goalStatuses(today: CalendarDate) throws -> [GoalStatusRow] {
        try goalStatusRows(today: today, key: nil)
    }

    /// The same computation for one goal key. Nil when that key has no valid definition.
    public func goalStatus(key: String, today: CalendarDate) throws -> GoalStatusRow? {
        try goalStatusRows(today: today, key: key).first
    }

    private func goalStatusRows(today: CalendarDate, key: String?) throws -> [GoalStatusRow] {
        try database.read { db in
            let definitions = try Self.goalDefinitionRows(db, key: key).map(\.definition)
            let grouped = try Self.goalLogs(db, through: today, key: key)
            return definitions.map { definition in
                let entries = grouped[definition.key] ?? []
                return GoalStatusRow(
                    definition: definition,
                    status: GoalProgress.compute(definition: definition, logs: entries, today: today),
                    score: GoalProgress.score(definition: definition, logs: entries, through: today))
            }
        }
    }

    /// Every log through `today` (of `key` only, when given) by goal key, in file order. Only the
    /// columns a log is made of are read, by position: decoding whole `IndexedGoalLog` records was
    /// most of the status query's time on a long history. A row is read as `GoalLog(indexed:)`
    /// reads it; one it rejects is skipped.
    static func goalLogs(_ db: Database, through today: CalendarDate, key: String?) throws -> [String: [GoalLog]] {
        let rows = try Row.fetchCursor(
            db,
            sql: """
                SELECT key, date, kind, value FROM goal_logs
                WHERE date<=? AND (? IS NULL OR key=?)
                ORDER BY file, key
                """,
            arguments: [today.description, key, key])
        return try groupedGoalLogs(rows)
    }
}
