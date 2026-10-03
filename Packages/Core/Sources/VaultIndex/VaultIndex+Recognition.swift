import EntityRecognition
import GRDB
import VaultFormat

extension VaultIndex {
    /// Reads every person and place with its ordered aliases in a single query.
    public func knownEntities() throws -> [KnownEntity] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.file, e.kind, e.name, e.qualifier, a.name AS alias
                    FROM entities e LEFT JOIN aliases a ON a.file=e.file
                    WHERE e.kind IN ('person','place') ORDER BY e.file,a.ordinal
                    """)
            var result: [KnownEntity] = []
            var current: (file: String, kind: KnownEntity.Kind, name: String, qualifier: String?, aliases: [String])?
            func appendCurrent() {
                if let current {
                    result.append(
                        KnownEntity(
                            file: current.file, kind: current.kind, name: current.name,
                            qualifier: current.qualifier, aliases: current.aliases))
                }
            }
            for row in rows {
                let file: String = row["file"]
                if current?.file != file {
                    appendCurrent()
                    let kind: String = row["kind"]
                    current = (file, KnownEntity.Kind(rawValue: kind)!, row["name"], row["qualifier"], [])
                }
                if let alias: String = row["alias"] { current?.aliases.append(alias) }
            }
            appendCurrent()
            return result
        }
    }

    /// Derives counts, last source journal date and distinct shared-day counts in one read transaction.
    public func entityUsage() throws -> [EntityUsage] {
        try database.read { db in
            let totals = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.file, COUNT(l.ordinal) AS total, MAX(f.date) AS lastDate
                    FROM entities e LEFT JOIN links l ON l.resolvedFile=e.file
                    LEFT JOIN files f ON f.path=l.file
                    WHERE e.kind IN ('person','place') GROUP BY e.file ORDER BY e.file
                    """)
            let pairs = try Row.fetchAll(
                db,
                sql: """
                    WITH days AS (
                        SELECT DISTINCT f.date, l.resolvedFile AS entity
                        FROM links l JOIN files f ON f.path=l.file
                        JOIN entities e ON e.file=l.resolvedFile
                        WHERE f.kind='day' AND f.date IS NOT NULL AND e.kind IN ('person','place')
                    )
                    SELECT a.entity AS first, b.entity AS second, COUNT(*) AS count
                    FROM days a JOIN days b ON a.date=b.date AND a.entity<b.entity
                    GROUP BY a.entity,b.entity
                    """)
            var together: [String: [String: Int]] = [:]
            for pair in pairs {
                let first: String = pair["first"]
                let second: String = pair["second"]
                let count: Int = pair["count"]
                together[first, default: [:]][second] = count
                together[second, default: [:]][first] = count
            }
            return totals.map { row in
                let file: String = row["file"]
                let date: String? = row["lastDate"]
                return EntityUsage(
                    file: file, totalCount: row["total"], lastDate: date.flatMap { CalendarDate($0) },
                    cooccurrences: together[file] ?? [:])
            }
        }
    }
}
