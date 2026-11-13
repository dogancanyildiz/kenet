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
    /// Paragraphs and headings of the `Diary` section.
    let diaryCount: Int
    /// First line of the first Diary paragraph, as `DaySummary.preview` gives it.
    let preview: String?
    let hasGoalRecords: Bool
    let taskCount: Int
    let firstEventPreview: String?
    /// ``firstEventPreview`` with its links (nil when it has none or there is no event).
    let firstEventSpans: [DayPreviewSpan]?

    init(
        id: String, date: CalendarDate, eventCount: Int, diaryCount: Int, preview: String?,
        hasGoalRecords: Bool = false, taskCount: Int = 0, firstEventPreview: String? = nil,
        firstEventSpans: [DayPreviewSpan]? = nil
    ) {
        self.id = id
        self.date = date
        self.eventCount = eventCount
        self.diaryCount = diaryCount
        self.preview = preview
        self.hasGoalRecords = hasGoalRecords
        self.taskCount = taskCount
        self.firstEventPreview = firstEventPreview
        self.firstEventSpans = firstEventSpans
    }

    init(entry: DaySummaryEntry) {
        self.init(
            id: entry.file, date: entry.date, eventCount: entry.eventCount, diaryCount: entry.diaryCount,
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

    var hasActivity: Bool {
        eventCount > 0 || taskCount > 0 || diaryCount > 0 || hasGoalRecords
    }

    /// Linked spans of ``displayPreview`` when it is the first event's line and holds a link.
    var displayPreviewSpans: [DayPreviewSpan]? {
        guard let firstEventPreview, !firstEventPreview.isEmpty else { return nil }
        return firstEventSpans
    }

    var displayPreview: String? {
        if let firstEventPreview, !firstEventPreview.isEmpty {
            return firstEventPreview
        }
        return preview
    }

    /// The day list's rows (iPhone Günlük and the Mac column): each day with its task count and
    /// first event from the content fragments, days with nothing in them left out.
    static func listed(_ days: [DayOverview], fragments: [String: VaultFileFragment]) -> [DayOverview] {
        days.map { $0.enriched(with: fragments[$0.id]) }.filter(\.hasActivity)
    }

    func enriched(with fragment: VaultFileFragment?) -> DayOverview {
        guard let fragment else { return self }
        return DayOverview(
            id: id, date: date, eventCount: eventCount, diaryCount: diaryCount,
            preview: preview, hasGoalRecords: hasGoalRecords,
            taskCount: fragment.taskCount, firstEventPreview: fragment.firstEventPreview,
            firstEventSpans: fragment.firstEventSpans)
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
        path = VaultLayout.dayPath(date)
        self.updated = updated
    }
}

extension DaySummary {
    /// A day file's events and Diary paragraphs and headings, in source order.
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
        let diary = rows.filter { $0.section == "Diary" && ["paragraph", "heading"].contains($0.kind) }
            .map { row in
                DiaryRow(id: row.ordinal, headingLevel: row.headingLevel, text: LinkedText(row: row, links: links))
            }
        self.init(id: path, date: date, events: events, diary: diary, hasGoalRecords: hasGoalRecords)
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
        self.init(id: VaultLayout.dayPath(date), date: date, events: [], diary: [])
    }
}
