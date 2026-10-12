import Foundation
import GRDB
import VaultFormat

/// One day file as the day list and the calendar read it: counts and the preview paragraph, not
/// the day's text.
public struct DaySummaryEntry: Sendable, Equatable {
    public let file: String
    public let date: CalendarDate
    /// Event blocks of the file.
    public let eventCount: Int
    /// Paragraphs and headings of the `Journal` section.
    public let journalCount: Int
    /// The first `Journal` paragraph, the day's preview.
    public let firstParagraph: IndexedBlock?
    /// Every link of `firstParagraph` in source order, resolved or not, so its text can be drawn whole.
    public let firstParagraphLinks: [IndexedLink]
    /// Whether the file records a goal value.
    public let hasGoalRecords: Bool

    public init(
        file: String, date: CalendarDate, eventCount: Int, journalCount: Int, firstParagraph: IndexedBlock?,
        firstParagraphLinks: [IndexedLink], hasGoalRecords: Bool
    ) {
        self.file = file
        self.date = date
        self.eventCount = eventCount
        self.journalCount = journalCount
        self.firstParagraph = firstParagraph
        self.firstParagraphLinks = firstParagraphLinks
        self.hasGoalRecords = hasGoalRecords
    }
}

extension VaultIndex {
    /// Day files dated `from` through `to`, both included and either end open when `nil`, newest
    /// first. A day file is `journal/<date>.md` with valid UTF-8; every other file is absent.
    public func daySummaries(from: CalendarDate? = nil, to: CalendarDate? = nil) throws -> [DaySummaryEntry] {
        // Stored dates are written as `YYYY-MM-DD`, so text order is date order.
        var range = "f.kind = 'day' AND f.date IS NOT NULL"
        var bounds: [String] = []
        if let from {
            range += " AND f.date >= ?"
            bounds.append(from.description)
        }
        if let to {
            range += " AND f.date <= ?"
            bounds.append(to.description)
        }
        let firsts = """
            WITH firsts AS (
                SELECT b.file, MIN(b.ordinal) AS ordinal
                FROM blocks b JOIN files f ON f.path = b.file
                WHERE \(range) AND b.section = 'Journal' AND b.kind = 'paragraph'
                GROUP BY b.file)
            """
        return try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT f.path, f.date,
                        COUNT(CASE WHEN b.kind = 'event' THEN 1 END) AS events,
                        COUNT(CASE WHEN b.section = 'Journal' AND b.kind IN ('paragraph', 'heading') THEN 1 END)
                            AS journal,
                        EXISTS (SELECT 1 FROM goal_logs g WHERE g.file = f.path) AS goals
                    FROM files f LEFT JOIN blocks b ON b.file = f.path
                    WHERE \(range)
                    GROUP BY f.path
                    ORDER BY f.date DESC, f.path
                    """, arguments: StatementArguments(bounds))
            guard !rows.isEmpty else { return [] }
            let paragraphs = try IndexedBlock.fetchAll(
                db,
                sql: "\(firsts) SELECT b.* FROM firsts x JOIN blocks b ON b.file = x.file AND b.ordinal = x.ordinal",
                arguments: StatementArguments(bounds))
            let links = try IndexedLink.fetchAll(
                db,
                sql: """
                    \(firsts) SELECT l.* FROM firsts x JOIN links l ON l.file = x.file AND l.block = x.ordinal
                    ORDER BY l.file, l.ordinal
                    """, arguments: StatementArguments(bounds))
            let paragraphByFile = Dictionary(paragraphs.map { ($0.file, $0) }, uniquingKeysWith: { first, _ in first })
            let linksByFile = Dictionary(grouping: links, by: \.file)
            return rows.compactMap { row in
                let file: String = row["path"]
                guard let date = CalendarDate(row["date"] as String) else { return nil }
                return DaySummaryEntry(
                    file: file, date: date, eventCount: row["events"], journalCount: row["journal"],
                    firstParagraph: paragraphByFile[file], firstParagraphLinks: linksByFile[file] ?? [],
                    hasGoalRecords: row["goals"])
            }
        }
    }

    /// Every row of the day file of `date`, or `nil` when the vault has none. The index gives a day
    /// file only to `journal/<date>.md` with valid UTF-8 (`IndexBuilder`), so this is that path's
    /// `contents(ofFile:)`.
    public func day(on date: CalendarDate) throws -> IndexedFileContents? {
        guard let contents = try contents(ofFile: "journal/\(date).md"), contents.file.kind == "day" else {
            return nil
        }
        return contents
    }
}
