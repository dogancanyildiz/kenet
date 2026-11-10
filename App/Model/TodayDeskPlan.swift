import Foundation
import VaultFormat

/// Pure selection for the Mac Today desk right panel and hour grid (`docs/screens.md`, "Mac").
struct TodayDeskPlan: Sendable {
    /// Next timed event at or after `now`, if any.
    let nextEvent: EventRow?
    /// Next timed open task at or after `now`, if any (today's timed tasks only; not carried-over).
    let nextTimedTask: (task: TaskRow, time: EventTime)?
    /// At most two carried-over (overdue open) tasks for the panel rows.
    let carriedPreview: [TaskRow]
    /// Count behind the "N devreden daha" line; 0 hides it.
    let hiddenCarriedCount: Int
    /// Hour axis bounds: default 9…18, widened by timed records.
    let hourRange: ClosedRange<Int>
    /// Timed events for the hour grid, sorted by time then file order.
    let timedEvents: [EventRow]
    /// Timed open tasks for the hour grid (excludes carried-over / overdue).
    let timedTasks: [(task: TaskRow, time: EventTime)]
    /// Untimed events (shown under "Saatsiz").
    let untimedEvents: [EventRow]
    /// Untimed open tasks of today (excludes carried-over).
    let untimedTasks: [TaskRow]

    /// Right panel stays when the detail column is at least reading width + panel
    /// (`InkSpacing.macPageWidth` + ``ShellStyle/todayPanelWidth``). Narrower detail folds the
    /// panel sections under the hour grid.
    static let panelMinDetailWidth: CGFloat = InkSpacing.macPageWidth + ShellStyle.todayPanelWidth

    static func showsPanel(detailWidth: CGFloat) -> Bool {
        detailWidth >= panelMinDetailWidth
    }

    init(
        events: [EventRow],
        openTasks: [TaskRow],
        carriedOver: [TaskRow],
        nowHour: Int,
        nowMinute: Int,
        taskTime: (TaskRow) -> EventTime? = {
            DaySchedulePresentation.extractLeadingTime(from: $0.text.plainText)
        }
    ) {
        let carriedIDs = Set(carriedOver.map(\.id))
        let todayTasks = openTasks.filter { !carriedIDs.contains($0.id) }

        let timedEventRows = events.compactMap { event -> (EventRow, EventTime)? in
            guard let time = event.time else { return nil }
            return (event, time)
        }
        .sorted { lhs, rhs in
            if lhs.1.hour != rhs.1.hour { return lhs.1.hour < rhs.1.hour }
            if lhs.1.minute != rhs.1.minute { return lhs.1.minute < rhs.1.minute }
            return lhs.0.sourceLine < rhs.0.sourceLine
        }

        let timedTaskRows = todayTasks.compactMap { task -> (TaskRow, EventTime)? in
            guard let time = taskTime(task) else { return nil }
            return (task, time)
        }
        .sorted { lhs, rhs in
            if lhs.1.hour != rhs.1.hour { return lhs.1.hour < rhs.1.hour }
            if lhs.1.minute != rhs.1.minute { return lhs.1.minute < rhs.1.minute }
            return lhs.0.sourceLine < rhs.0.sourceLine
        }

        timedEvents = timedEventRows.map(\.0)
        timedTasks = timedTaskRows
        untimedEvents = events.filter { $0.time == nil }
        untimedTasks = todayTasks.filter { taskTime($0) == nil }

        nextEvent =
            timedEventRows.first {
                Self.isAtOrAfter($0.1, hour: nowHour, minute: nowMinute)
            }?.0
        nextTimedTask = timedTaskRows.first { task in
            !task.0.isClosed && Self.isAtOrAfter(task.1, hour: nowHour, minute: nowMinute)
        }

        carriedPreview = Array(carriedOver.prefix(2))
        hiddenCarriedCount = max(0, carriedOver.count - 2)

        let hours = timedEventRows.map(\.1.hour) + timedTaskRows.map(\.1.hour)
        hourRange = TimelineDayHours.range(forHours: hours)
    }

    private static func isAtOrAfter(_ time: EventTime, hour: Int, minute: Int) -> Bool {
        if time.hour != hour { return time.hour > hour }
        return time.minute >= minute
    }
}
