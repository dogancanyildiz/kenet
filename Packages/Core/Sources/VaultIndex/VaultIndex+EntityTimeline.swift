import Foundation
import GRDB
import VaultFormat

/// A day-file event or Journal paragraph with a resolved link to an entity: one row of its timeline.
public struct EntityTimelineEntry: Sendable, Equatable {
    public let date: CalendarDate
    public let block: IndexedBlock
    /// Every link of the block in source order, resolved or not, so its text can be drawn whole.
    public let links: [IndexedLink]

    public init(date: CalendarDate, block: IndexedBlock, links: [IndexedLink]) {
        self.date = date
        self.block = block
        self.links = links
    }
}

extension VaultIndex {
    /// Blocks counted as an encounter: events and Journal paragraphs of a day file. Tasks,
    /// headings, frontmatter and files outside `journal/<date>.md` never are.
    private static let encounterBlocks = """
        f.kind = 'day' AND f.date IS NOT NULL
          AND (b.kind = 'event' OR (b.kind = 'paragraph' AND b.section = 'Journal'))
        """

    /// The encounter blocks linking to `file`, newest date first and, within a date, by
    /// descending file and block order. A block linking twice is one entry.
    public func entityTimeline(for file: String) throws -> [EntityTimelineEntry] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT b.*, f.date AS day
                    FROM links l
                    JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    JOIN files f ON f.path = b.file
                    WHERE l.resolvedFile = ? AND \(Self.encounterBlocks)
                    ORDER BY f.date DESC, b.file DESC, b.ordinal DESC
                    """, arguments: [file])
            guard !rows.isEmpty else { return [] }
            let links = try IndexedLink.fetchAll(
                db,
                sql: """
                    SELECT * FROM links
                    WHERE block IS NOT NULL
                      AND file IN (SELECT DISTINCT file FROM links WHERE resolvedFile = ?)
                    ORDER BY file, ordinal
                    """, arguments: [file])
            let byBlock = Dictionary(grouping: links) { BlockKey(file: $0.file, ordinal: $0.block ?? -1) }
            return try rows.compactMap { row in
                guard let date = CalendarDate(row["day"] as String) else { return nil }
                let block = try IndexedBlock(row: row)
                return EntityTimelineEntry(
                    date: date, block: block,
                    links: byBlock[BlockKey(file: block.file, ordinal: block.ordinal)] ?? [])
            }
        }
    }

    /// Each linked file's latest encounter date on or before `day`; files without one are absent.
    /// Counts the same blocks as `entityTimeline(for:)`.
    public func lastEncounters(asOf day: CalendarDate) throws -> [String: CalendarDate] {
        try database.read { db in
            // Stored dates are written as `YYYY-MM-DD`, so text order is date order.
            let rows = try Row.fetchCursor(
                db,
                sql: """
                    SELECT l.resolvedFile, MAX(f.date)
                    FROM links l
                    JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    JOIN files f ON f.path = b.file
                    WHERE l.resolvedFile IS NOT NULL AND f.date <= ? AND \(Self.encounterBlocks)
                    GROUP BY l.resolvedFile
                    """, arguments: [day.description])
            var result: [String: CalendarDate] = [:]
            while let row = try rows.next() {
                guard let date = CalendarDate(row[1] as String) else { continue }
                result[row[0]] = date
            }
            return result
        }
    }
}

private struct BlockKey: Hashable {
    let file: String
    let ordinal: Int
}
