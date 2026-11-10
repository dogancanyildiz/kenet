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
    /// Timed tasks for the hour grid: today's open ones (excludes carried-over / overdue) and the
    /// ones completed today, which stay on the grid drawn as done.
    let timedTasks: [(task: TaskRow, time: EventTime)]
    /// Grid tasks completed today (closed in the file, or being completed right now).
    let completedTaskIDs: Set<String>
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

    /// One block of the Today panel, in drawing order.
    enum PanelSection: Sendable, CaseIterable {
        case nextEvent, nextTask, goals, carriedOver, onThisDay, closeDay
    }

    /// Panel blocks for the layout. Folded under the grid, the day page above already draws the
    /// goal strip and the carried-over tasks, so those two are left out; the right panel keeps all.
    static func panelSections(isFolded: Bool) -> [PanelSection] {
        isFolded ? PanelSection.allCases.filter { $0 != .goals && $0 != .carriedOver } : PanelSection.allCases
    }

    /// The grid is the only place timed records appear: the day page's event list keeps the
    /// untimed events.
    var dayListEvents: [EventRow] { untimedEvents }

    /// One card on the hour grid. A task card carries its completion box; an event card has none.
    enum GridCard: Sendable {
        case event(EventRow)
        case task(TaskRow, time: EventTime, box: TaskBoxState)

        /// The completion box drawn at the card's leading edge; `nil` for events.
        var box: TaskBoxState? {
            if case .task(_, _, let box) = self { return box }
            return nil
        }
    }

    /// The grid's cards by hour: events first, then tasks, each in time order.
    var gridCardsByHour: [Int: [GridCard]] {
        var cards: [Int: [GridCard]] = [:]
        for event in timedEvents {
            guard let time = event.time else { continue }
            cards[time.hour, default: []].append(.event(event))
        }
        for item in timedTasks {
            cards[item.time.hour, default: []].append(
                .task(item.task, time: item.time, box: taskBox(for: item.task)))
        }
        return cards
    }

    /// The task's completion box, in the same state the day page's task row draws.
    func taskBox(for task: TaskRow) -> TaskBoxState {
        TaskBoxPresentation(row: task, isCompleted: completedTaskIDs.contains(task.id)).state
    }

    /// Today's timed tasks, drawn on the grid and so left out of the day page's task list.
    var gridTaskIDs: Set<String> { Set(timedTasks.map(\.task.id)) }

    /// The day page's task rows without the grid's timed tasks. Carried-over, closed and
    /// disclosure rows stay.
    func dayListTaskRows(_ rows: [TodayPresentation.Row]) -> [TodayPresentation.Row] {
        let hidden = gridTaskIDs
        guard !hidden.isEmpty else { return rows }
        return rows.filter { row in
            if case .task(let task) = row { return !hidden.contains(task.id) }
            return true
        }
    }

    /// The task section's counter without the grid's timed tasks.
    func dayListTaskCounter(_ presentation: TodayPresentation) -> String {
        let onGrid = gridTaskIDs.intersection(presentation.openTasks.map(\.id)).count
        return (presentation.remainingTaskCount - onGrid).formatted(.number.locale(presentation.locale))
    }

    init(
        events: [EventRow],
        openTasks: [TaskRow],
        carriedOver: [TaskRow],
        nowHour: Int,
        nowMinute: Int,
        completedTasks: [TaskRow] = [],
        day: CalendarDate? = nil,
        taskTime: (TaskRow) -> EventTime? = {
            DaySchedulePresentation.extractLeadingTime(from: $0.text.plainText)
        }
    ) {
        let carriedIDs = Set(carriedOver.map(\.id))
        // Completed today, on the day they belong to: due that day, or written in its file
        // (undated or due later) — the rule `TaskGroups` keeps for open rows. A carried-over task
        // completed today stays off the grid as it was before.
        let completedToday = completedTasks.filter { task in
            guard !carriedIDs.contains(task.id), task.rawStatus != "-" else { return false }
            guard let day else { return true }
            if task.due == day { return true }
            return task.createdDate == day && (task.due.map { $0 > day } ?? true)
        }
        let openIDs = Set(openTasks.map(\.id))
        let todayTasks =
            openTasks.filter { !carriedIDs.contains($0.id) }
            + completedToday.filter { !openIDs.contains($0.id) }
        let completedIDs = Set(completedToday.map(\.id))
        completedTaskIDs = completedIDs

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
        untimedTasks = todayTasks.filter { taskTime($0) == nil && !completedIDs.contains($0.id) }

        nextEvent =
            timedEventRows.first {
                Self.isAtOrAfter($0.1, hour: nowHour, minute: nowMinute)
            }?.0
        nextTimedTask = timedTaskRows.first { task in
            !task.0.isClosed && !completedIDs.contains(task.0.id)
                && Self.isAtOrAfter(task.1, hour: nowHour, minute: nowMinute)
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
