import Foundation
import GRDB
import VaultFormat

/// What a people/places list row shows, for every entity at once: the latest encounter, the
/// encounter days of a recent window (the row's 12-month bar) and the explicit relation count.
public struct EntityListActivity: Sendable, Equatable {
    /// Latest encounter on or before the window's end, from the whole history.
    public var lastEncounter: CalendarDate?
    /// Distinct encounter days inside the window, ascending.
    public var recentDays: [CalendarDate]
    /// Explicit relations touching the entity, outgoing plus incoming (`relations(of:)`).
    public var relationCount: Int

    public init(lastEncounter: CalendarDate? = nil, recentDays: [CalendarDate] = [], relationCount: Int = 0) {
        self.lastEncounter = lastEncounter
        self.recentDays = recentDays
        self.relationCount = relationCount
    }
}

extension VaultIndex {
    /// One read for the whole list instead of a timeline and a relations query per row.
    /// Encounters count the same blocks as `entityTimeline(for:)`; relations the same rows as
    /// `relations(of:)`. Entities with none of the three are absent.
    public func entityListActivity(from start: CalendarDate, through end: CalendarDate) throws
        -> [String: EntityListActivity]
    {
        var result: [String: EntityListActivity] = [:]
        for (file, date) in try lastEncounters(asOf: end) {
            result[file, default: EntityListActivity()].lastEncounter = date
        }
        try database.read { db in
            let rows = try Row.fetchCursor(
                db,
                sql: """
                    SELECT DISTINCT l.resolvedFile, f.date
                    FROM links l
                    JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    JOIN files f ON f.path = b.file
                    WHERE l.resolvedFile IS NOT NULL AND f.date >= ? AND f.date <= ?
                      AND \(Self.encounterBlocks)
                    ORDER BY l.resolvedFile, f.date
                    """, arguments: [start.description, end.description])
            while let row = try rows.next() {
                guard let date = CalendarDate(row[1] as String) else { continue }
                result[row[0], default: EntityListActivity()].recentDays.append(date)
            }
        }
        for relation in try relationRows() {
            result[relation.source, default: EntityListActivity()].relationCount += 1
            result[relation.target, default: EntityListActivity()].relationCount += 1
        }
        return result
    }
}
