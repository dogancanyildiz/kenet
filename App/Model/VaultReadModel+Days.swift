import Foundation
import VaultFormat
import VaultIndex

/// One day in the day list and the calendar: counts and the preview line, not the day's text.
/// Queried for the visible range (`IndexStore.computeDaySummaries(from:to:)`).
struct DayOverview: Identifiable, Sendable, Equatable {
    /// The day file's vault-relative path.
    let id: String
    let date: CalendarDate
    let eventCount: Int
    /// Paragraphs and headings of the `Journal` section.
    let journalCount: Int
    /// First line of the first Journal paragraph, as `DaySummary.preview` gives it.
    let preview: String?
    let hasGoalRecords: Bool

    init(
        id: String, date: CalendarDate, eventCount: Int, journalCount: Int, preview: String?,
        hasGoalRecords: Bool = false
    ) {
        self.id = id
        self.date = date
        self.eventCount = eventCount
        self.journalCount = journalCount
        self.preview = preview
        self.hasGoalRecords = hasGoalRecords
    }

    init(entry: DaySummaryEntry) {
        self.init(
            id: entry.file, date: entry.date, eventCount: entry.eventCount, journalCount: entry.journalCount,
            preview: entry.firstParagraph.flatMap { paragraph in
                // A block's text is its lines joined by "\n"; without links that is already its plain
                // text, and the Markdown parse a whole list of previews would repeat is skipped.
                let text =
                    entry.firstParagraphLinks.isEmpty
                    ? paragraph.text : LinkedText(row: paragraph, links: entry.firstParagraphLinks).plainText
                return text.components(separatedBy: "\n").first
            },
            hasGoalRecords: entry.hasGoalRecords)
    }
}

/// Reloads the day list when the range or the published index changes.
struct DayRangeRequest: Hashable {
    let from: CalendarDate?
    let to: CalendarDate?
    let updated: Date?
}

/// Reloads one day when its date or the published index changes.
struct DayRequest: Hashable {
    let path: String
    let updated: Date?

    init(date: CalendarDate, updated: Date?) {
        path = "journal/\(date).md"
        self.updated = updated
    }
}

extension DaySummary {
    /// A day file's events and Journal paragraphs and headings, in source order.
    init(path: String, date: CalendarDate, blocks: [IndexedBlock], links: [IndexedLink], hasGoalRecords: Bool) {
        let rows = blocks.sorted { $0.ordinal < $1.ordinal }
        let events = rows.filter { $0.kind == "event" }.map { row in
            EventRow(
                id: row.ordinal,
                time: row.time.flatMap {
                    RawDocument(bytes: Array("## Events\n- \($0) event".utf8)).bodyLines.events.first?.time
                },
                text: LinkedText(row: row, links: links),
                sourceLine: row.firstLine - 1, sourceEnd: row.lastLine,
                sourceText: row.text, sourceIdentifier: row.identifier)
        }
        let journal = rows.filter { $0.section == "Journal" && ["paragraph", "heading"].contains($0.kind) }
            .map { row in
                JournalRow(id: row.ordinal, headingLevel: row.headingLevel, text: LinkedText(row: row, links: links))
            }
        self.init(id: path, date: date, events: events, journal: journal, hasGoalRecords: hasGoalRecords)
    }

    /// The day page's content from `VaultIndex.day(on:)`; a date without a day file is empty.
    init(contents: IndexedFileContents?, date: CalendarDate) {
        guard let contents else {
            self.init(empty: date)
            return
        }
        self.init(
            path: contents.file.path, date: date, blocks: contents.blocks, links: contents.links,
            hasGoalRecords: !contents.goalLogs.isEmpty)
    }

    /// A date without a day file.
    init(empty date: CalendarDate) {
        self.init(id: "journal/\(date).md", date: date, events: [], journal: [])
    }
}
