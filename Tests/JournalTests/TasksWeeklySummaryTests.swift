import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@Suite struct TasksWeeklySummaryTests {
    private func calendar(_ locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    @Test func turkishWeekRunsMondayThroughSunday() {
        let week = TasksWeeklySummary.week(containing: CalendarDate("2026-11-12")!, calendar: calendar("tr_TR"))
        #expect(week == CalendarDate("2026-11-09")!...CalendarDate("2026-11-15")!)
        let sunday = TasksWeeklySummary.week(containing: CalendarDate("2026-11-15")!, calendar: calendar("tr_TR"))
        #expect(sunday == CalendarDate("2026-11-09")!...CalendarDate("2026-11-15")!)
    }

    @Test func usWeekRunsSundayThroughSaturday() {
        let week = TasksWeeklySummary.week(containing: CalendarDate("2026-11-12")!, calendar: calendar("en_US"))
        #expect(week == CalendarDate("2026-11-08")!...CalendarDate("2026-11-14")!)
    }

    @Test func doneTasksAreTheNumeratorAndJoinTheOpenOnesInTheDenominator() {
        let summary = TasksWeeklySummary(PeriodTaskCount(done: 3, openDue: 5))
        #expect(summary == TasksWeeklySummary(completed: 3, total: 8))
        #expect(summary.fraction == 3.0 / 8.0)
    }

    @Test func emptyWeekHasZeroProgress() {
        #expect(TasksWeeklySummary(PeriodTaskCount(done: 0, openDue: 0)).fraction == 0)
    }
}

/// The card counts the whole vault: a list filter does not narrow it.
@MainActor @Suite struct TasksWeeklySummaryListTests {
    @Test func listFiltersDoNotNarrowTheWeeklyCard() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-22")!
        let model = TasksModel(store: context.store, today: { day })
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        model.calendar = calendar
        await model.loadList()
        let all = try #require(model.list?.weekly)
        // Week of 2026-09-21: the sample's #project/tedarik task is due on the 22nd.
        #expect(all.total > 0)
        let period = try await context.store.computePeriodTaskCount(
            from: CalendarDate("2026-09-21")!, through: CalendarDate("2026-09-27")!)
        #expect(all == TasksWeeklySummary(period))

        model.projectFilter = "arsiv"
        await model.loadList()
        #expect(model.list?.weekly == all)
    }
}
