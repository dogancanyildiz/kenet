import Foundation
import VaultFormat
import VaultIndex

/// screens.md "Haftalık özet kartı": the numerator is the tasks completed this week (by their
/// done day); the denominator adds the open tasks due this week. The list's filters do not
/// apply, and nothing is capped (``IndexStore/computePeriodTaskCount(from:through:)``).
struct TasksWeeklySummary: Equatable {
    let completed: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    static let empty = TasksWeeklySummary(completed: 0, total: 0)

    init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    init(_ period: PeriodTaskCount) {
        self.init(completed: period.done, total: period.done + period.openDue)
    }

    /// The days of the week holding `day`, from the calendar's first weekday, both ends included.
    static func week(containing day: CalendarDate, calendar: Calendar) -> ClosedRange<CalendarDate> {
        let start = LocalDay.instant(for: day)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let first = day.addingDays(-offset) ?? day
        return first...(first.addingDays(6) ?? first)
    }
}
