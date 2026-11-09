import Foundation
import VaultFormat

struct TasksWeeklySummary: Equatable {
    let completed: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }

    /// screens.md "Haftalık özet kartı": the numerator is the tasks completed this week (by
    /// their done date); the denominator adds the open tasks due this week to them.
    /// `completed` is the list's recent completions (newest first, ``TasksModel/completedLimit``).
    static func make(
        open: [TaskRow], completed: [TaskRow], today: CalendarDate, calendar: Calendar = .current
    ) -> Self {
        let openDue = open.filter { !$0.isClosed }.compactMap { row in
            row.due.map { TaskWeeklyDue(date: $0, isCompleted: false) }
        }
        let done = completed.compactMap { row in
            row.done.map { TaskWeeklyDue(date: $0, isCompleted: true) }
        }
        return count(due: openDue + done, today: today, calendar: calendar)
    }

    static func count(
        due rows: [TaskWeeklyDue], today: CalendarDate, calendar: Calendar = .current
    ) -> Self {
        let start = LocalDay.instant(for: today)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -offset, to: start) ?? start
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let lower = LocalDay.today(at: weekStart)
        let upper = LocalDay.today(at: weekEnd)
        let dueThisWeek = rows.filter { lower <= $0.date && $0.date < upper }
        return Self(
            completed: dueThisWeek.filter(\.isCompleted).count,
            total: dueThisWeek.count)
    }
}

/// One task on the week: its due day while open, its done day once completed.
struct TaskWeeklyDue: Equatable {
    let date: CalendarDate
    let isCompleted: Bool
}
