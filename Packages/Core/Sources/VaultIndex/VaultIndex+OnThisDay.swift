import GRDB
import Summaries
import VaultFormat

extension VaultIndex {
    /// One consistent read of every readable day file sharing `day`'s month and day, in any year.
    /// Frontmatter links are excluded, as in ``summaryInput(from:to:)``.
    public func onThisDayInput(for day: CalendarDate) throws -> OnThisDayInput {
        let monthDay = String(day.description.suffix(5))
        return try database.read { db in
            let days = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT f.date FROM files f
                    WHERE f.kind='day' AND f.readable=1 AND substr(f.date,6)=? ORDER BY f.date
                    """, arguments: [monthDay]
            ).compactMap { CalendarDate($0) }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.date, e.file, e.name, e.kind FROM links l JOIN files f ON f.path=l.file
                    JOIN entities e ON e.file=l.resolvedFile AND e.kind IN ('person','place')
                    WHERE f.kind='day' AND f.readable=1 AND l.key IS NULL AND substr(f.date,6)=?
                    ORDER BY f.date,l.file,l.ordinal
                    """, arguments: [monthDay])
            let mentions = rows.compactMap { row -> OnThisDayInput.Mention? in
                let source: String = row["date"]
                guard let date = CalendarDate(source), let kind = OnThisDayInput.Mention.Kind(rawValue: row["kind"])
                else { return nil }
                return .init(day: date, entity: row["file"], name: row["name"], kind: kind)
            }
            return OnThisDayInput(days: days, mentions: mentions)
        }
    }
}
