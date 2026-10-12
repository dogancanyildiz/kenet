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

    public init(definition: GoalDefinition, status: GoalStatus, score: Int?) {
        self.definition = definition
        self.status = status
        self.score = score
    }
}

extension VaultIndex {
    /// Inclusive days before `today` in the log window. With `today` that is 400 days, matching the
    /// app's goal-log list (`today.addingDays(-399)`).
    private static let goalStatusLookbackDays = 399
    /// Inclusive days after `today`. Status math ignores them; they keep the fetched set aligned
    /// with the app's goal-log list, which also keeps six days ahead.
    private static let goalStatusLookaheadDays = 6

    /// Status and score for every valid goal definition on `today`.
    ///
    /// Logs in the window are read with one query, in file order. A day with two rows keeps the
    /// later file: `GoalProgress` stores the last value for a day.
    public func goalStatuses(today: CalendarDate) throws -> [GoalStatusRow] {
        try goalStatusRows(today: today, key: nil)
    }

    /// The same computation for one goal key. Nil when that key has no valid definition.
    public func goalStatus(key: String, today: CalendarDate) throws -> GoalStatusRow? {
        try goalStatusRows(today: today, key: key).first
    }

    private func goalStatusRows(today: CalendarDate, key: String?) throws -> [GoalStatusRow] {
        let start = today.addingDays(-Self.goalStatusLookbackDays) ?? today
        let end = today.addingDays(Self.goalStatusLookaheadDays) ?? today
        return try database.read { db in
            let entitySQL =
                key == nil
                ? "SELECT * FROM entities WHERE kind='goal' ORDER BY file"
                : "SELECT * FROM entities WHERE kind='goal' AND goalKey=? ORDER BY file"
            let arguments = StatementArguments(key.map { [$0] } ?? [])
            let entities = try IndexedEntity.fetchAll(db, sql: entitySQL, arguments: arguments)
            let links = try IndexedLink.fetchAll(
                db,
                sql: """
                    SELECT l.* FROM links l
                    JOIN entities e ON e.file=l.file AND e.kind='goal'
                    WHERE l.key='place' ORDER BY l.file, l.ordinal
                    """)
            let places = Dictionary(grouping: links, by: \.file)
            var definitions = entities.compactMap {
                GoalDefinition(entity: $0, place: places[$0.file]?.first?.target)
            }
            definitions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let logs = try IndexedGoalLog.fetchAll(
                db,
                sql: """
                    SELECT * FROM goal_logs
                    WHERE date>=? AND date<=? AND (? IS NULL OR key=?)
                    ORDER BY file, key
                    """,
                arguments: [start.description, end.description, key, key])
            let grouped = Dictionary(grouping: logs, by: \.key).mapValues { $0.compactMap(GoalLog.init(indexed:)) }
            return definitions.map { definition in
                let entries = grouped[definition.key] ?? []
                return GoalStatusRow(
                    definition: definition,
                    status: GoalProgress.compute(definition: definition, logs: entries, today: today),
                    score: GoalProgress.score(definition: definition, logs: entries, through: today))
            }
        }
    }
}
