import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@Suite struct TimelineWeekPlacementTests {
    private let week = (0..<7).map { CalendarDate("2026-11-09")!.addingDays($0)! }
    private let today = CalendarDate("2026-11-10")!

    private func row(_ line: Int, status: String = " ", start: String? = nil, due: String? = nil) throws -> TaskRow {
        var fields: [String: Any] = [
            "file": "journal/2026-11-09.md", "ordinal": line, "kind": "task", "firstLine": line,
            "lastLine": line, "text": "Task \(line)", "section": "Tasks", "rawStatus": status,
            "ownsIdentifier": false,
        ]
        if let start { fields["startDate"] = start }
        if let due { fields["dueDate"] = due }
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }

    @Test func multiDayTaskShowsOnEveryDayWithTheCardOnItsFirst() throws {
        let task = try row(1, start: "2026-11-10", due: "2026-11-12")
        let placements = TimelineWeekPlacement.make(rows: [task], week: week, today: today)
        #expect(placements[week[0]] == nil)
        #expect(placements[week[1]]?.map(\.isContinuation) == [false])
        #expect(placements[week[2]]?.map(\.isContinuation) == [true])
        #expect(placements[week[3]]?.map(\.isContinuation) == [true])
        #expect(placements[week[4]] == nil)
    }

    /// A task that began last week has its card on the week's first day.
    @Test func taskFromLastWeekStartsTheWeekWithItsCard() throws {
        let task = try row(1, start: "2026-11-05", due: "2026-11-10")
        let placements = TimelineWeekPlacement.make(rows: [task], week: week, today: today)
        #expect(placements[week[0]]?.map(\.isContinuation) == [false])
        #expect(placements[week[1]]?.map(\.isContinuation) == [true])
    }

    @Test func dueOnlyShowsOnceAndCancelledAndUndatedNever() throws {
        let due = try row(1, due: "2026-11-11")
        let cancelled = try row(2, status: "-", due: "2026-11-11")
        let undated = try row(3)
        let placements = TimelineWeekPlacement.make(rows: [due, cancelled, undated], week: week, today: today)
        #expect(placements.values.flatMap { $0 }.map(\.row.id) == [due.id])
        #expect(placements[week[2]]?.first?.isContinuation == false)
    }
}
