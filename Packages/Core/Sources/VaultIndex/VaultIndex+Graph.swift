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

        /// Sorted, distinct entity sets sharing an event or task block, or one segment of a paragraph
        /// block (`ParagraphSegments`).
        public let groups: [[String]]

        public init(date: CalendarDate, mentions: [String: Int], groups: [[String]] = []) {
            self.date = date
            self.mentions = mentions
            self.groups = groups
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
    /// Block kinds whose links count as appearing together: an event or task with its continuation
    /// lines, or a paragraph segment. Headings and frontmatter (no block) only add mentions.
    static let graphGroupBlockKinds: Set<String> = ["event", "task", "paragraph"]
    /// Day-file paragraphs over more than one line, whose links are grouped per segment.
    static let graphSegmentedBlock = "f.kind = 'day' AND b.kind = 'paragraph' AND b.lastLine > b.firstLine"

    /// Counts every link resolving to an entity of `kinds`, and per date those from day files and the
    /// entity sets sharing one of the day's blocks. A multi-line paragraph block splits into its list
    /// items, quote runs and prose runs (`ParagraphSegments`); the schema keeps one block.
    public func graphMentions(kinds: Set<String>) throws -> GraphMentions {
        guard !kinds.isEmpty else { return GraphMentions(totals: [:], days: []) }
        let rows = try graphRows(kinds: kinds, date: nil)
        var days: [CalendarDate: [String: Int]] = [:]
        // Same-date files share one day, so their groups merge and identical groups count once.
        var groups: [CalendarDate: Set<[String]>] = [:]
        for (text, mentions) in rows.mentionsByDate {
            guard let date = CalendarDate(text) else { continue }
            days[date, default: [:]].merge(mentions, uniquingKeysWith: +)
            groups[date, default: []].formUnion(Self.graphGroups(rows.blocksByDate[text, default: [:]]))
        }
        return GraphMentions(
            totals: rows.totals,
            days: days.map {
                GraphMentions.Day(
                    date: $0.key, mentions: $0.value,
                    groups: groups[$0.key, default: []].sorted { $0.lexicographicallyPrecedes($1) })
            }.sorted { $0.date < $1.date })
    }

    /// One block, or one segment of a multi-line day paragraph, of one file.
    struct GraphBlockKey: Hashable {
        let file: String
        let ordinal: Int
        var segment = 0
    }

    /// What both graph queries read, by the stored date text (parsed once per date by the caller).
    struct GraphRows {
        /// Entity file to its resolved incoming links from every file read.
        var totals: [String: Int] = [:]
        var mentionsByDate: [String: [String: Int]] = [:]
        var blocksByDate: [String: [GraphBlockKey: Set<String>]] = [:]
    }

    /// The one row walk of ``graphMentions(kinds:)`` and ``dayGraphMentions(on:kinds:)``: every
    /// resolved link into an entity of `kinds` (`date` nil), or only those from `date`'s day files.
    /// Day-file links are grouped by block, multi-line paragraphs by segment (`ParagraphSegments`).
    func graphRows(kinds: Set<String>, date: CalendarDate?) throws -> GraphRows {
        let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
        let oneDay = date == nil ? "" : "AND f.kind = 'day' AND f.date = ?"
        var arguments = kinds.sorted()
        if let date { arguments.append(date.description) }
        var rows = GraphRows()
        // Segment ordinals per line of each multi-line paragraph, split once per block.
        var segments: [GraphBlockKey: [Int]] = [:]
        try database.read { db in
            let cursor = try Row.fetchCursor(
                db,
                sql: """
                    SELECT l.resolvedFile, f.kind, f.date, l.file, l.block, b.kind, COUNT(*),
                        CASE WHEN \(Self.graphSegmentedBlock) THEN l.line - b.firstLine END AS offset,
                        CASE WHEN \(Self.graphSegmentedBlock) THEN b.text END
                    FROM links l
                    JOIN entities e ON e.file = l.resolvedFile
                    LEFT JOIN files f ON f.path = l.file
                    LEFT JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    WHERE e.kind IN (\(placeholders)) \(oneDay)
                    GROUP BY l.resolvedFile, l.file, l.block, offset
                    """, arguments: StatementArguments(arguments))
            while let row = try cursor.next() {
                let target: String = row[0]
                let count: Int = row[6]
                rows.totals[target, default: 0] += count
                guard row[1] as String? == "day", let date = row[2] as String? else { continue }
                rows.mentionsByDate[date, default: [:]][target, default: 0] += count
                guard let ordinal = row[4] as Int?, let kind = row[5] as String?,
                    Self.graphGroupBlockKinds.contains(kind)
                else { continue }
                var key = GraphBlockKey(file: row[3], ordinal: ordinal)
                if let offset = row[7] as Int?, let text = row[8] as String? {
                    let lines = segments[key] ?? ParagraphSegments.indices(in: text)
                    segments[key] = lines
                    key.segment = lines.indices.contains(offset) ? lines[offset] : 0
                }
                rows.blocksByDate[date, default: [:]][key, default: []].insert(target)
            }
        }
        return rows
    }

    /// The sorted member sets of the blocks shared by at least two entities.
    static func graphGroups(_ blocks: [GraphBlockKey: Set<String>]) -> Set<[String]> {
        Set(blocks.values.filter { $0.count >= 2 }.map { $0.sorted() })
    }
}
