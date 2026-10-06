import Foundation
import GoalTracking
import VaultFormat

/// A snapshot for Today and historical day pages. Group order is owned by TaskGroups.
///
/// Pass `@Environment(\.locale)` from the view; do not hand-build a `Locale` for presentation.
struct TodayPresentation: Sendable {
    enum Section: Sendable { case goals, tasks, events, calendar, journal }

    let headline: String
    let byline: String?
    let remainingTaskCount: Int
    let remainingGoalCount: Int
    let completedGoalCount: Int
    let goalCount: Int
    /// Daily goals only (`period == .day`). Counter, byline, and this ID list share one set;
    /// the view should draw the same IDs so a fraction like `1/3` matches visible goal rows.
    let countedGoalIDs: [String]
    let eventCount: Int
    private let carriedOver: [TaskRow]
    let datedTasks: [TaskRow]
    let createdTasks: [TaskRow]
    private let cancelled: [TaskRow]
    private let completed: [TaskRow]
    let locale: Locale
    var isCarriedOverExpanded: Bool
    var isCompletedExpanded: Bool

    /// Supply closed source rows separately: Today's TaskGroups intentionally excludes them.
    /// completedTaskIDs also accepts DayTasksModel's temporarily retained pre-write rows.
    /// `goalStatusesDay` must be the day the statuses were computed for; on mismatch, goals are omitted.
    init(
        day: DaySummary, groups: TaskGroups, goals: [GoalDefinition], goalStatuses: [String: GoalStatus],
        goalStatusesDay: CalendarDate, today: CalendarDate, locale: Locale, calendar: Calendar,
        completedTasks: [TaskRow] = [], completedTaskIDs: Set<String> = [],
        isCarriedOverExpanded: Bool = false, isCompletedExpanded: Bool = false
    ) {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        self.locale = resolved
        self.isCarriedOverExpanded = isCarriedOverExpanded
        self.isCompletedExpanded = isCompletedExpanded
        headline = Self.dateText(day.date, today: today, locale: resolved, calendar: calendar, headline: true)
        let all = groups.overdue + groups.dated + groups.created
        let isDone: (TaskRow) -> Bool = {
            completedTaskIDs.contains($0.id) || $0.rawStatus == "x" || $0.rawStatus == "X"
        }
        let isCancelled: (TaskRow) -> Bool = { $0.rawStatus == "-" }
        let isOpen: (TaskRow) -> Bool = { !isCancelled($0) && !isDone($0) && !$0.isClosed }
        carriedOver = groups.overdue.filter(isOpen)
        datedTasks = groups.dated.filter(isOpen)
        createdTasks = groups.created.filter(isOpen)
        var seen: Set<String> = []
        var cancelledRows: [TaskRow] = []
        var completedRows: [TaskRow] = []
        // Rows from the groups are always represented. Separately supplied closed rows are a
        // superset (Today's groups drop closed rows): keep only what was completed on this day.
        let groupIDs = Set(all.map(\.id))
        let completedHere = completedTasks.filter {
            groupIDs.contains($0.id) || completedTaskIDs.contains($0.id)
                || (isDone($0) && $0.done == day.date)
        }
        for row in all + completedHere {
            guard seen.insert(row.id).inserted else { continue }
            if isCancelled(row) {
                cancelledRows.append(row)
            } else if isDone(row) {
                completedRows.append(row)
            }
        }
        cancelled = cancelledRows
        completed = completedRows
        remainingTaskCount = carriedOver.count + datedTasks.count + createdTasks.count
        if goalStatusesDay == day.date {
            let daily = goals.filter { $0.period == .day }
            countedGoalIDs = daily.map(\.id)
            goalCount = daily.count
            completedGoalCount = daily.filter { goalStatuses[$0.key]?.progress.isComplete == true }.count
            remainingGoalCount = goalCount - completedGoalCount
        } else {
            countedGoalIDs = []
            goalCount = 0
            completedGoalCount = 0
            remainingGoalCount = 0
        }
        eventCount = day.events.count
        byline = TodayCopy.byline(
            events: eventCount, tasks: remainingTaskCount, goals: remainingGoalCount, locale: resolved)
    }

    var carriedOverTasks: [TaskRow] { isCarriedOverExpanded ? carriedOver : Array(carriedOver.prefix(3)) }
    var hiddenCarriedOverCount: Int { isCarriedOverExpanded ? 0 : max(0, carriedOver.count - 3) }
    var carriedOverDisclosure: String? {
        guard hiddenCarriedOverCount > 0 else { return nil }
        return TodayCopy.carriedOver(hiddenCarriedOverCount, locale: locale)
    }
    /// Visible task rows in display order; disclosure rows are exposed separately.
    /// Past-day closed rows (cancelled, completed any day) follow open rows; folding applies only to `x`.
    var taskRows: [TaskRow] {
        carriedOverTasks + datedTasks + createdTasks + cancelled + completedTaskRows
    }
    /// Every task identity represented by this snapshot, including folded completed rows.
    var representedTaskIDs: Set<String> {
        Set(
            (carriedOver + datedTasks + createdTasks + cancelled + completed).map(\.id))
    }
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
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let text = dateText(date, today: today, locale: resolved, calendar: calendar, headline: false)
        if TurkishSuffix.isTurkish(resolved) {
            let ending =
                date.year == today.year
                ? TurkishSuffix.ablativeEnding(turkishMonthName(date.month))
                : TurkishSuffix.ablativeEnding(forNumber: date.year)
            return "\(text)'\(ending)"
        }
        return String(
            localized: "from \(text)", bundle: PresentationLocalization.bundle(resolved), locale: resolved)
    }

    private static let turkishMonthNames = [
        "", "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
        "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
    ]

    private static func turkishMonthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "" }
        return turkishMonthNames[month]
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
        let status: TaskStatus
        if isCompleted {
            status = .done
        } else {
            switch row.rawStatus {
            case "-": status = .cancelled
            case "x", "X": status = .done
            case "/": status = .inProgress
            default: status = .todo
            }
        }
        priority = row.priority
        state = TaskBoxState(status: status, priority: row.priority)
    }

    var priorityMark: String {
        // Independent of box fill: spoken/mark helpers still expose priority on closed rows.
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

/// The given locale selects both catalog language and formatting when its language is supported.
/// Prefer `@Environment(\.locale)` from the view; do not hand-build a `Locale` for presentation.
enum PresentationLocalization {
    /// A locale whose language the catalog supports is used as is (region formatting kept).
    /// Otherwise text and dates both fall back to the app's current localization.
    static func resolvedLocale(_ locale: Locale) -> Locale {
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        let supported = available.isEmpty ? ["tr", "en"] : available
        if let code = locale.language.languageCode?.identifier, supported.contains(code) { return locale }
        let chosen = Bundle.preferredLocalizations(from: supported).first ?? "en"
        return Locale(identifier: chosen)
    }

    static func bundle(_ locale: Locale) -> Bundle {
        let resolved = resolvedLocale(locale)
        let language = resolved.language.languageCode?.identifier ?? resolved.identifier
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
