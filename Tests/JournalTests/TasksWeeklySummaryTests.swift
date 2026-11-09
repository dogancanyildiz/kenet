import Testing
import VaultFormat

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

    @Test func emptyWeekHasZeroProgress() {
        let summary = TasksWeeklySummary.count(due: [], today: CalendarDate("2026-11-09")!)
        #expect(summary.fraction == 0)
    }
}
