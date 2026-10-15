import GRDB
import Summaries
import VaultFormat

extension VaultIndex {
    /// The day rows of ``summaryInput(from:to:)`` alone, for views that need only day activity
    /// (the Özetler year map). Same query and same values as `summaryInput(from:to:).days`.
    public func summaryDays(from: CalendarDate, to: CalendarDate) throws -> [SummaryInput.Day] {
        guard from <= to else { return [] }
        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT f.date, SUM(CASE WHEN b.kind='event' THEN 1 ELSE 0 END) AS events,
                        MAX(CASE WHEN b.section='Journal' AND b.kind IN ('paragraph','heading')
                            AND trim(b.text)<>'' THEN 1 ELSE 0 END) AS hasJournal
                    FROM files f LEFT JOIN blocks b ON b.file=f.path
                    WHERE f.kind='day' AND f.readable=1 AND f.date BETWEEN ? AND ?
                    GROUP BY f.date ORDER BY f.date
                    """, arguments: [from.description, to.description]
            ).compactMap { row -> SummaryInput.Day? in
                let source: String = row["date"]
                guard let date = CalendarDate(source) else { return nil }
                return .init(date: date, events: row["events"], hasJournal: (row["hasJournal"] as Int) != 0)
            }
        }
    }
}
