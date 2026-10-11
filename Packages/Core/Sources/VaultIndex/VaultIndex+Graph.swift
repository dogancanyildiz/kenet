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
    public func graphMentions(kinds: Set<String>) throws -> GraphMentions {
        guard !kinds.isEmpty else { return GraphMentions(totals: [:], days: []) }
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        var totals: [String: Int] = [:]
        // Day mentions by the stored date text, parsed once per date rather than once per row.
        var byDate: [String: [String: Int]] = [:]
        try database.read { db in
            let rows = try Row.fetchCursor(
                db,
                sql: """
                    SELECT l.resolvedFile, f.kind, f.date, COUNT(*)
                    FROM links l
                    JOIN entities e ON e.file = l.resolvedFile
                    LEFT JOIN files f ON f.path = l.file
                    WHERE e.kind IN (\(placeholders))
                    GROUP BY l.resolvedFile, f.kind, f.date
                    """, arguments: StatementArguments(kinds.sorted()))
            while let row = try rows.next() {
                let target: String = row[0]
                let count: Int = row[3]
                totals[target, default: 0] += count
                guard row[1] as String? == "day", let date = row[2] as String? else { continue }
                byDate[date, default: [:]][target, default: 0] += count
            }
        }
        var days: [CalendarDate: [String: Int]] = [:]
        for (text, mentions) in byDate {
            guard let date = CalendarDate(text) else { continue }
            days[date, default: [:]].merge(mentions, uniquingKeysWith: +)
        }
        return GraphMentions(
            totals: totals,
            days: days.map { GraphMentions.Day(date: $0.key, mentions: $0.value) }.sorted { $0.date < $1.date })
    }
}
