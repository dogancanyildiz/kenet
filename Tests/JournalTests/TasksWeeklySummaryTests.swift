import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@Suite struct TasksWeeklySummaryTests {
    @Test func countsOnlyDueDatesInCurrentWeekAndCompletedAmongThem() {
        let today = CalendarDate("2026-11-09")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        let summary = TasksWeeklySummary.count(due: [
            TaskWeeklyDue(date: CalendarDate("2026-11-09")!, isCompleted: true),
            TaskWeeklyDue(date: CalendarDate("2026-11-12")!, isCompleted: false),
            TaskWeeklyDue(date: CalendarDate("2026-11-16")!, isCompleted: true),
        ], today: today, calendar: calendar)
        #expect(summary == TasksWeeklySummary(completed: 1, total: 2))
    }

    @Test func completedCountByDoneDateAndOpenByDueDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        let open = [
            try row(status: " ", due: "2026-11-12"),  // due this week: counts
            try row(status: " ", due: "2026-11-02"),  // carried over from last week: out
            try row(status: " ", due: nil),  // undated: out
        ]
        let completed = [
            try row(status: "x", due: "2026-11-01", done: "2026-11-10"),  // done this week, due earlier
            try row(status: "x", due: "2026-11-11", done: "2026-11-06"),  // done last week: out
        ]
        let summary = TasksWeeklySummary.make(
            open: open, completed: completed, today: CalendarDate("2026-11-10")!, calendar: calendar)
        #expect(summary == TasksWeeklySummary(completed: 1, total: 2))
    }

    @Test func emptyWeekHasZeroProgress() {
        let summary = TasksWeeklySummary.count(due: [], today: CalendarDate("2026-11-09")!)
        #expect(summary.fraction == 0)
    }

    private func row(status: String, due: String?, done: String? = nil) throws -> TaskRow {
        var fields: [String: Any] = [
            "file": "journal/2026-11-01.md", "ordinal": 1, "kind": "task", "firstLine": 2,
            "lastLine": 2, "text": "Sample task", "section": "Tasks", "rawStatus": status,
            "ownsIdentifier": false,
        ]
        if let due { fields["dueDate"] = due }
        if let done { fields["doneDate"] = done }
        let block = try JSONDecoder().decode(
            IndexedBlock.self, from: JSONSerialization.data(withJSONObject: fields))
        return TaskRow(row: block, links: [])
    }
}
