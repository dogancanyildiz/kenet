import Foundation
import GoalTracking
import VaultFormat

/// A snapshot for Today and historical day pages. Group order is owned by TaskGroups.
struct TodayPresentation: Sendable {
    enum Section: Sendable { case goals, tasks, events, calendar, journal }

    let headline: String
    let byline: String?
    let remainingTaskCount: Int
    let remainingGoalCount: Int
    let completedGoalCount: Int
    let goalCount: Int
    let eventCount: Int
    private let carriedOver: [TaskRow]
    let datedTasks: [TaskRow]
    let createdTasks: [TaskRow]
    private let completed: [TaskRow]
    let locale: Locale
    var isCarriedOverExpanded: Bool
    var isCompletedExpanded: Bool

    /// Supply closed source rows separately: Today's TaskGroups intentionally excludes them.
    /// completedTaskIDs also accepts DayTasksModel's temporarily retained pre-write rows.
    init(
        day: DaySummary, groups: TaskGroups, goals: [GoalDefinition], goalStatuses: [String: GoalStatus],
        today: CalendarDate, locale: Locale, calendar: Calendar,
        completedTasks: [TaskRow] = [], completedTaskIDs: Set<String> = [],
        isCarriedOverExpanded: Bool = false, isCompletedExpanded: Bool = false
    ) {
        self.locale = locale
        self.isCarriedOverExpanded = isCarriedOverExpanded
        self.isCompletedExpanded = isCompletedExpanded
        headline = Self.dateText(day.date, today: today, locale: locale, calendar: calendar, headline: true)
        let all = groups.overdue + groups.dated + groups.created
        let isDone: (TaskRow) -> Bool = {
            completedTaskIDs.contains($0.id) || $0.rawStatus == "x" || $0.rawStatus == "X"
        }
        let isOpen: (TaskRow) -> Bool = { !$0.isClosed && !isDone($0) }
        carriedOver = groups.overdue.filter(isOpen)
        datedTasks = groups.dated.filter(isOpen)
        createdTasks = groups.created.filter(isOpen)
        let groupedIDs = Set(all.map(\.id))
        var seen: Set<String> = []
        completed = (all + completedTasks).filter {
            isDone($0)
                && ($0.done == day.date || completedTaskIDs.contains($0.id)
                    || ($0.done == nil && groupedIDs.contains($0.id)))
                && seen.insert($0.id).inserted
        }
        remainingTaskCount = carriedOver.count + datedTasks.count + createdTasks.count
        let daily = goals.filter { $0.period == .day }
        goalCount = daily.count
        completedGoalCount = daily.filter { goalStatuses[$0.key]?.progress.isComplete == true }.count
        remainingGoalCount = goalCount - completedGoalCount
        eventCount = day.events.count
        byline = TodayCopy.byline(
            events: eventCount, tasks: remainingTaskCount, goals: remainingGoalCount, locale: locale)
    }

    var carriedOverTasks: [TaskRow] { isCarriedOverExpanded ? carriedOver : Array(carriedOver.prefix(3)) }
    var hiddenCarriedOverCount: Int { isCarriedOverExpanded ? 0 : max(0, carriedOver.count - 3) }
    var carriedOverDisclosure: String? {
        guard hiddenCarriedOverCount > 0 else { return nil }
        return TodayCopy.carriedOver(hiddenCarriedOverCount, locale: locale)
    }
    /// Visible task rows in display order; disclosure rows are exposed separately.
    var taskRows: [TaskRow] { carriedOverTasks + datedTasks + createdTasks + completedTaskRows }
    var completedTaskCount: Int { completed.count }
    var completedTaskRows: [TaskRow] { isCompletedExpanded || completed.count <= 1 ? completed : [] }
    var completedDisclosure: String? {
        guard !isCompletedExpanded, completed.count > 1 else { return nil }
        return TodayCopy.completed(completed.count, locale: locale)
    }

    func counter(for section: Section) -> String? {
        switch section {
        case .goals: "\(completedGoalCount)/\(goalCount)"
        case .tasks: remainingTaskCount.formatted(.number.locale(locale))
        case .events: eventCount.formatted(.number.locale(locale))
        case .calendar, .journal: nil
        }
    }

    static func carriedOverDate(
        _ date: CalendarDate, today: CalendarDate, locale: Locale, calendar: Calendar
    ) -> String {
        let text = dateText(date, today: today, locale: locale, calendar: calendar, headline: false)
        return String(localized: "\(text)'den", bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    private static func dateText(
        _ date: CalendarDate, today: CalendarDate, locale: Locale, calendar: Calendar, headline: Bool
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(
            (headline ? "dMMMMEEEE" : "dMMM") + (date.year == today.year ? "" : "y"))
        return formatter.string(from: LocalDay.instant(for: date, timeZone: calendar.timeZone))
    }
}

/// State and priority remain independent, including while the box is half filled.
struct TaskBoxPresentation: Sendable {
    let state: TaskBoxState
    let priority: TaskPriority?

    init(row: TaskRow, isCompleted: Bool = false) {
        state = isCompleted || row.isClosed ? .done : row.rawStatus == "/" ? .inProgress : .open
        priority = row.priority
    }

    var priorityMark: String {
        switch priority {
        case .medium: "!"
        case .high: "!!"
        default: ""
        }
    }

    func accessibilityValue(locale: Locale) -> String {
        VoiceOverCopy.taskBoxValue(state: state, priority: priority, locale: locale)
    }
}

enum TaskBoxState: Sendable { case open, inProgress, done }

/// Locale selects both catalog language and formatting; process language is irrelevant.
enum PresentationLocalization {
    static func bundle(_ locale: Locale) -> Bundle {
        let language = locale.language.languageCode?.identifier ?? "en"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

private enum TodayCopy {
    static func byline(events: Int, tasks: Int, goals: Int, locale: Locale) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        let eventText = String(localized: "\(events) olay", bundle: bundle, locale: locale)
        let taskText = String(localized: "\(tasks) görev", bundle: bundle, locale: locale)
        let goalText = String(localized: "\(goals) hedef", bundle: bundle, locale: locale)
        let remaining: String?
        if tasks > 0 && goals > 0 {
            remaining = String(localized: "\(taskText) ve \(goalText) kaldı", bundle: bundle, locale: locale)
        } else if tasks > 0 || goals > 0 {
            let text = tasks > 0 ? taskText : goalText
            remaining = String(localized: "\(text) kaldı", bundle: bundle, locale: locale)
        } else {
            remaining = nil
        }
        if events > 0, let remaining {
            return String(localized: "\(eventText) · \(remaining)", bundle: bundle, locale: locale)
        }
        return events > 0 ? eventText : remaining
    }

    static func carriedOver(_ count: Int, locale: Locale) -> String {
        String(localized: "\(count) devreden daha", bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    static func completed(_ count: Int, locale: Locale) -> String {
        String(localized: "\(count) görev tamamlandı", bundle: PresentationLocalization.bundle(locale), locale: locale)
    }
}
