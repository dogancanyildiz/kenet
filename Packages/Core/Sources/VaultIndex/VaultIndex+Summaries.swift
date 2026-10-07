import GRDB
import GoalTracking
import Summaries
import VaultFormat

extension VaultIndex {
    /// One consistent read. Day activity is bounded; historical goal logs and first mentions are retained.
    /// Pass the start of the previous comparison period as `from`.
    public func summaryInput(from: CalendarDate, to: CalendarDate) throws -> SummaryInput {
        guard from <= to else { return SummaryInput() }
        return try database.read { db in
            let dayRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.date, SUM(CASE WHEN b.kind='event' THEN 1 ELSE 0 END) AS events,
                        MAX(CASE WHEN b.section='Journal' AND b.kind IN ('paragraph','heading')
                            AND trim(b.text)<>'' THEN 1 ELSE 0 END) AS hasJournal
                    FROM files f LEFT JOIN blocks b ON b.file=f.path
                    WHERE f.kind='day' AND f.readable=1 AND f.date BETWEEN ? AND ?
                    GROUP BY f.date ORDER BY f.date
                    """, arguments: [from.description, to.description])
            let days = dayRows.compactMap { row -> SummaryInput.Day? in
                let source: String = row["date"]
                guard let date = CalendarDate(source) else { return nil }
                return .init(date: date, events: row["events"], hasJournal: (row["hasJournal"] as Int) != 0)
            }
            let entityRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.*, (SELECT MIN(f.date) FROM links l JOIN files f ON f.path=l.file
                        WHERE l.resolvedFile=e.file AND l.key IS NULL AND f.kind='day' AND f.date<=?) AS firstMention
                    FROM entities e WHERE e.kind IN ('person','place') ORDER BY e.file
                    """, arguments: [to.description])
            let entities = entityRows.compactMap { row -> SummaryInput.Entity? in
                guard let kind = SummaryInput.Entity.Kind(rawValue: row["kind"]) else { return nil }
                let qualifier: String? = row["qualifier"]
                let name: String = row["name"]
                let first: String? = row["firstMention"]
                return .init(
                    id: row["file"], name: name + (qualifier.map { " (" + $0 + ")" } ?? ""), kind: kind,
                    firstMention: first.flatMap(CalendarDate.init))
            }
            let linkRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.date, l.resolvedFile FROM links l JOIN files f ON f.path=l.file
                    JOIN entities e ON e.file=l.resolvedFile AND e.kind IN ('person','place')
                    WHERE f.kind='day' AND l.key IS NULL AND f.date BETWEEN ? AND ? ORDER BY f.date,l.file,l.ordinal
                    """, arguments: [from.description, to.description])
            let mentions = linkRows.compactMap { row -> SummaryInput.Mention? in
                let source: String = row["date"]
                guard let date = CalendarDate(source) else { return nil }
                return .init(day: date, entity: row["resolvedFile"])
            }
            let taskRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT b.*, CASE WHEN f.kind='day' THEN f.date ELSE NULL END AS created
                    FROM blocks b JOIN files f ON f.path=b.file WHERE b.kind='task' ORDER BY b.file,b.ordinal
                    """)
            let tasks = taskRows.map { row -> SummaryInput.Task in
                let created: String? = row["created"]
                let due: String? = row["dueDate"]
                let done: String? = row["doneDate"]
                let status: String? = row["status"]
                return .init(
                    created: created.flatMap(CalendarDate.init),
                    status: status.flatMap(TaskStatus.init(rawValue:)) ?? .unknown,
                    due: due.flatMap(CalendarDate.init), done: done.flatMap(CalendarDate.init))
            }
            let definitions = try IndexedEntity.fetchAll(
                db, sql: "SELECT * FROM entities WHERE kind='goal' ORDER BY file"
            ).compactMap { GoalDefinition(entity: $0) }
            let logs = try IndexedGoalLog.fetchAll(
                db, sql: "SELECT * FROM goal_logs WHERE date<=? ORDER BY date,file,key", arguments: [to.description])
            let grouped = Dictionary(grouping: logs, by: \.key)
            return SummaryInput(
                days: days, entities: entities, mentions: mentions, tasks: tasks,
                goals: definitions.map {
                    .init(definition: $0, logs: (grouped[$0.key] ?? []).compactMap(GoalLog.init(indexed:)))
                })
        }
    }
}
