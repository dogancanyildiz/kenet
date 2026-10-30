import Foundation
import GRDB
import VaultFormat

/// Resolved links into entities of the requested kinds, for the relationship graph.
public struct GraphMentions: Sendable, Equatable {
    /// Links into each entity from one date's day files.
    public struct Day: Sendable, Equatable {
        public let date: CalendarDate
        /// Entity file to link count; entities without a link that day are absent.
        public let mentions: [String: Int]

        public init(date: CalendarDate, mentions: [String: Int]) {
            self.date = date
            self.mentions = mentions
        }
    }

    /// Entity file to its resolved incoming links from every file; unlinked entities are absent.
    public let totals: [String: Int]
    /// Dates with at least one counted link, oldest first.
    public let days: [Day]

    public init(totals: [String: Int], days: [Day]) {
        self.totals = totals
        self.days = days
    }
}

extension VaultIndex {
    /// Counts every link resolving to an entity of `kinds`, and per date those from day files.
    /// Links in headings and frontmatter count like any other.
    public func graphMentions(kinds: Set<String>) throws -> GraphMentions {
        guard !kinds.isEmpty else { return GraphMentions(totals: [:], days: []) }
        let rows = try graphRows(kinds: kinds, date: nil)
        var days: [CalendarDate: [String: Int]] = [:]
        for (text, mentions) in rows.mentionsByDate {
            guard let date = CalendarDate(text) else { continue }
            days[date, default: [:]].merge(mentions, uniquingKeysWith: +)
        }
        return GraphMentions(
            totals: rows.totals,
            days: days.map { GraphMentions.Day(date: $0.key, mentions: $0.value) }.sorted { $0.date < $1.date })
    }

    /// What both graph queries read, by the stored date text (parsed once per date by the caller).
    struct GraphRows {
        /// Entity file to its resolved incoming links from every file read.
        var totals: [String: Int] = [:]
        var mentionsByDate: [String: [String: Int]] = [:]
    }

    /// The one row walk of ``graphMentions(kinds:)`` and ``dayGraphMentions(on:kinds:)``: every
    /// resolved link into an entity of `kinds` (`date` nil), or only those from `date`'s day files.
    func graphRows(kinds: Set<String>, date: CalendarDate?) throws -> GraphRows {
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        let oneDay = date == nil ? "" : "AND f.kind = 'day' AND f.date = ?"
        var arguments = kinds.sorted()
        if let date { arguments.append(date.description) }
        var rows = GraphRows()
        try database.read { db in
            let cursor = try Row.fetchCursor(
                db,
                sql: """
                    SELECT l.resolvedFile, f.kind, f.date, COUNT(*)
                    FROM links l
                    JOIN entities e ON e.file = l.resolvedFile
                    LEFT JOIN files f ON f.path = l.file
                    WHERE e.kind IN (\(placeholders)) \(oneDay)
                    GROUP BY l.resolvedFile, l.file
                    """, arguments: StatementArguments(arguments))
            while let row = try cursor.next() {
                let target: String = row[0]
                let count: Int = row[3]
                rows.totals[target, default: 0] += count
                guard row[1] as String? == "day", let date = row[2] as String? else { continue }
                rows.mentionsByDate[date, default: [:]][target, default: 0] += count
            }
        }
        return rows
    }
}
