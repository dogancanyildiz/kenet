import Foundation
import GRDB
import VaultFormat

extension VaultIndex {
    /// One day's graph: the links from `date`'s day files into entities of `kinds`, and the entity
    /// sets sharing one of that day's blocks. The rules are ``graphMentions(kinds:)``'s, restricted to
    /// one date (``graphGroupBlockKinds``); only that date's files are read. A day without such a
    /// link has no mentions and no groups.
    public func dayGraphMentions(on date: CalendarDate, kinds: Set<String>) throws -> GraphMentions.Day {
        guard !kinds.isEmpty else { return GraphMentions.Day(date: date, mentions: [:]) }
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        struct BlockKey: Hashable {
            let file: String
            let ordinal: Int
        }
        var mentions: [String: Int] = [:]
        var blocks: [BlockKey: Set<String>] = [:]
        try database.read { db in
            let rows = try Row.fetchCursor(
                db,
                sql: """
                    SELECT l.resolvedFile, l.file, l.block, b.kind, COUNT(*)
                    FROM files f
                    JOIN links l ON l.file = f.path
                    JOIN entities e ON e.file = l.resolvedFile
                    LEFT JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    WHERE f.kind = 'day' AND f.date = ? AND e.kind IN (\(placeholders))
                    GROUP BY l.resolvedFile, l.file, l.block
                    """, arguments: StatementArguments([date.description] + kinds.sorted()))
            while let row = try rows.next() {
                let target: String = row[0]
                mentions[target, default: 0] += row[4] as Int
                guard let ordinal = row[2] as Int?, let kind = row[3] as String?,
                    Self.graphGroupBlockKinds.contains(kind)
                else { continue }
                blocks[BlockKey(file: row[1], ordinal: ordinal), default: []].insert(target)
            }
        }
        // Same-date files share the day, so identical groups from them count once.
        let groups = Set(blocks.values.filter { $0.count >= 2 }.map { $0.sorted() })
        return GraphMentions.Day(
            date: date, mentions: mentions, groups: groups.sorted { $0.lexicographicallyPrecedes($1) })
    }
}
