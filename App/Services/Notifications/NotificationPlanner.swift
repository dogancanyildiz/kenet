import Foundation
import GoalTracking
import VaultFormat
import VaultIndex

/// Requests for the seven-day window, plus the people each `people-` request counts.
struct NotificationSchedule: Equatable, Sendable {
    var requests: [NotificationRequest]
    var assignments: [CadenceReminderAssignment]
}

/// What the planner reads from the index for the days it plans
/// (`IndexStore.computeNotificationDays(from:through:)`): the open tasks a morning counts and
/// names, and the days already written.
struct NotificationVaultDays: Sendable {
    /// Open tasks per due day, every due day through the last planned one.
    var openTaskCounts: [CalendarDate: Int] = [:]
    /// Open tasks due on a planned day: the ones a morning names.
    var dueTasks: [TaskRow] = []
    /// Planned days whose day file has events or Journal paragraphs and headings.
    var writtenDays: Set<CalendarDate> = []
}

/// One local calendar week of one-shot requests, derived solely from immutable inputs.
enum NotificationPlanner {
    static func requests(
        goals: NotificationGoals?, days: NotificationVaultDays?,
        preferences: NotificationPreferences, now: Date, timeZone: TimeZone = .current,
        people: [CadenceReminderPerson] = [], lastNotified: [String: CalendarDate] = [:]
    ) -> [NotificationRequest] {
        schedule(
            goals: goals, days: days, preferences: preferences, now: now, timeZone: timeZone, people: people,
            lastNotified: lastNotified
        ).requests
    }

    /// `lastNotified` holds only days whose reminder has already fired. `days` and `goals` cover
    /// today and the six days after it; nil `days` (the index could not be read) plans no task or
    /// journal reminder, nil `goals` no goal reminder.
    static func schedule(
        goals: NotificationGoals?, days: NotificationVaultDays?,
        preferences: NotificationPreferences, now: Date, timeZone: TimeZone = .current,
        people: [CadenceReminderPerson] = [], lastNotified: [String: CalendarDate] = [:]
    ) -> NotificationSchedule {
        let today = LocalDay.today(at: now, timeZone: timeZone)
        var futureDays: [(day: CalendarDate, date: Date)] = []
        var result: [NotificationRequest] = []
        for offset in 0..<7 {
            guard let day = today.addingDays(offset) else { continue }
            if preferences.tasksEnabled, let days,
                let date = fireDate(day, time: preferences.taskTime, timeZone: timeZone),
                date > now,
                let message = taskMessage(days, on: day, hideContent: preferences.hideContent)
            {
                result.append(
                    NotificationRequest(
                        id: "task-\(day)", date: date, title: message.title, body: message.body, destination: .tasks))
            }
            if preferences.goalsEnabled, let goals,
                let date = fireDate(day, time: preferences.goalTime, timeZone: timeZone), date > now
            {
                let remaining = goals.definitions.filter {
                    $0.period == .day
                        && !GoalProgress.compute(definition: $0, logs: goals.logs[$0.key] ?? [], today: day)
                            .progress.isComplete
                }.sorted { $0.id < $1.id }.map(\.name)
                if !remaining.isEmpty {
                    let body =
                        preferences.hideContent
                        ? String(localized: "Bugün bekleyen hedefler var")
                        : String(localized: "Bugün bekleyen hedefler: \(remaining.joined(separator: ", "))")
                    result.append(
                        NotificationRequest(
                            id: "goals-\(day)", date: date, title: String(localized: "Günlük hedefler"),
                            body: body, destination: .goals))
                }
            }
            if preferences.journalEnabled, let days,
                let date = fireDate(day, time: preferences.journalTime, timeZone: timeZone), date > now
            {
                if !days.writtenDays.contains(day) {
                    result.append(
                        NotificationRequest(
                            id: "journal-\(day)", date: date, title: String(localized: "Gününden bir an"),
                            body: String(localized: "Bugünden bir an yazmak ister misin?"), destination: .journal))
                }
            }
            if preferences.peopleEnabled, let date = fireDate(day, time: preferences.peopleTime, timeZone: timeZone),
                date > now
            {
                futureDays.append((day, date))
            }
        }
        var assignments: [CadenceReminderAssignment] = []
        if preferences.peopleEnabled {
            let planned = CadenceReminderPlan.plan(
                people: people, days: futureDays.map(\.day), lastNotified: lastNotified)
            for item in futureDays {
                guard let due = planned[item.day], !due.isEmpty else { continue }
                let message = CadenceReminderPlan.message(people: due, hideContent: preferences.hideContent)
                result.append(
                    NotificationRequest(
                        id: "people-\(item.day)", date: item.date, title: message.title, body: message.body,
                        destination: .people))
                assignments.append(
                    CadenceReminderAssignment(day: item.day, date: item.date, personIDs: due.map(\.id)))
            }
        }
        return NotificationSchedule(
            requests: result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date },
            assignments: assignments)
    }

    /// Task, goal and journal ids. People ids stay separate so this list keeps its previous length.
    static func identifiers(on day: CalendarDate) -> [String] {
        (0..<7).compactMap { day.addingDays($0) }.flatMap { day in
            ["task-\(day)", "goals-\(day)", "journal-\(day)"]
        }
    }

    static func peopleIdentifiers(on day: CalendarDate) -> [String] {
        (0..<7).compactMap { day.addingDays($0) }.map { "people-\($0)" }
    }

    static func fireDate(_ day: CalendarDate, time: NotificationTime, timeZone: TimeZone) -> Date? {
        guard time.isValid else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let date = calendar.date(
                bySettingHour: time.hour, minute: time.minute, second: 0,
                of: LocalDay.instant(for: day, timeZone: timeZone)),
            LocalDay.today(at: date, timeZone: timeZone) == day
        else { return nil }
        return date
    }

    private static func taskMessage(
        _ days: NotificationVaultDays, on day: CalendarDate, hideContent: Bool
    ) -> (title: String, body: String)? {
        let due = days.dueTasks.filter { $0.due == day }.sorted { $0.id < $1.id }
        let overdue = days.openTaskCounts.reduce(0) { $1.key < day ? $0 + $1.value : $0 }
        guard !due.isEmpty || overdue > 0 else { return nil }
        let title: String
        if due.isEmpty {
            title = String(localized: "Bugünkü görevler")
        } else if hideContent || due.count > 1 {
            title = String(localized: "\(due.count) görev bugün")
        } else {
            title = due[0].text.plainText
        }
        let body = overdue > 0 ? String(localized: "Önceki günlerden \(overdue) açık görev.") : ""
        return (title, body)
    }
}
