import EntityRecognition
import GRDB
import VaultFormat

extension VaultIndex {
    /// Reads every requested entity with ordered aliases, and the link target that resolves to each file.
    public func knownEntities(kinds: Set<String> = ["person", "place"]) throws -> [KnownEntity] {
        let kinds = Set(kinds.filter { KnownEntity.Kind(rawValue: $0) != nil })
        guard !kinds.isEmpty else { return [] }
        return try database.read { db in
            var owners: [String: String] = [:]
            for path in try String.fetchAll(db, sql: "SELECT path FROM files ORDER BY path") {
                let stem = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
                let basename = String(stem.split(separator: "/").last ?? Substring(stem))
                if owners[comparisonKey(basename)] == nil { owners[comparisonKey(basename)] = path }
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.file, e.kind, e.name, e.qualifier, a.name AS alias
                    FROM entities e LEFT JOIN aliases a ON a.file=e.file
                    WHERE e.kind IN (\(kinds.sorted().map { _ in "?" }.joined(separator: ","))) ORDER BY e.file,a.ordinal
                    """, arguments: StatementArguments(kinds.sorted()))
            var result: [KnownEntity] = []
            var current: (file: String, kind: KnownEntity.Kind, name: String, qualifier: String?, aliases: [String])?
            func appendCurrent() {
                if let current {
                    let stem = KnownEntity.defaultLinkTarget(for: current.file)
                    let linkTarget: String
                    if owners[comparisonKey(stem)] == current.file {
                        linkTarget = stem
                    } else {
                        var path =
                            current.file.hasSuffix(".md") ? String(current.file.dropLast(3)) : current.file
                        if !path.contains("/") { path = "/" + path }
                        linkTarget = path
                    }
                    result.append(
                        KnownEntity(
                            file: current.file, kind: current.kind, name: current.name,
                            qualifier: current.qualifier, aliases: current.aliases, linkTarget: linkTarget))
                }
            }
            for row in rows {
                let file: String = row["file"]
                if current?.file != file {
                    appendCurrent()
                    let kind: String = row["kind"]
                    current = (
                        file, KnownEntity.Kind(rawValue: kind) ?? .custom(kind), row["name"], row["qualifier"], []
                    )
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
                    WHERE e.kind != 'goal' GROUP BY e.file ORDER BY e.file
                    """)
            let pairs = try Row.fetchAll(
                db,
                sql: """
                    WITH days AS (
                        SELECT DISTINCT f.date, l.resolvedFile AS entity
                        FROM links l JOIN files f ON f.path=l.file
                        JOIN entities e ON e.file=l.resolvedFile
                        WHERE f.kind='day' AND f.date IS NOT NULL AND e.kind != 'goal'
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
