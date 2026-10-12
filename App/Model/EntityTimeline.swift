import Foundation
import VaultFormat
import VaultIndex

struct EntityTimelineDay: Identifiable, Sendable {
    let date: CalendarDate
    let rows: [EntityTimelineRow]
    var id: CalendarDate { date }
}

struct EntityTimelineRow: Identifiable, Sendable {
    let file: String
    let ordinal: Int
    let text: LinkedText
    var id: String { file + ":" + String(ordinal) }
}

/// Reloads an entity's timeline when its path or the published index changes.
struct EntityTimelineRequest: Hashable {
    let path: String
    let updated: Date?
}

/// Reloads last-encounter dates when the day or the published index changes.
struct LastEncountersRequest: Hashable {
    let asOf: CalendarDate
    let updated: Date?
}

enum EntityTimeline {
    /// Groups the query's entries into days, keeping its order: newest day first, rows by
    /// descending file and block.
    static func days(from entries: [EntityTimelineEntry]) -> [EntityTimelineDay] {
        var days: [EntityTimelineDay] = []
        var rows: [EntityTimelineRow] = []
        for (offset, entry) in entries.enumerated() {
            rows.append(
                EntityTimelineRow(
                    file: entry.block.file, ordinal: entry.block.ordinal,
                    text: LinkedText(row: entry.block, links: entry.links)))
            if offset == entries.count - 1 || entries[offset + 1].date != entry.date {
                days.append(EntityTimelineDay(date: entry.date, rows: rows))
                rows = []
            }
        }
        return days
    }
}
