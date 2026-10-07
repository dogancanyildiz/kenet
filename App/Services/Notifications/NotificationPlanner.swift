import Foundation
import GoalTracking
import VaultFormat

/// One local calendar week of one-shot requests, derived solely from immutable inputs.
enum NotificationPlanner {
    static func requests(
        snapshot: VaultReadModel, preferences: NotificationPreferences, now: Date,
        timeZone: TimeZone = .current
    ) -> [NotificationRequest] {
        let today = LocalDay.today(at: now, timeZone: timeZone)
        var result: [NotificationRequest] = []
        for offset in 0..<7 {
            guard let day = today.addingDays(offset) else { continue }
            if preferences.tasksEnabled, let date = fireDate(day, time: preferences.taskTime, timeZone: timeZone),
                date > now,
                let message = taskMessage(snapshot.tasks, on: day, hideContent: preferences.hideContent)
            {
                result.append(
                    NotificationRequest(
                        id: "task-\(day)", date: date, title: message.title, body: message.body, destination: .tasks))
            }
            if preferences.goalsEnabled, let date = fireDate(day, time: preferences.goalTime, timeZone: timeZone),
                date > now
            {
                let remaining = snapshot.goals.filter {
                    $0.period == .day
                        && !GoalProgress.compute(definition: $0, logs: snapshot.goalLogs[$0.key] ?? [], today: day)
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
            if preferences.journalEnabled, let date = fireDate(day, time: preferences.journalTime, timeZone: timeZone),
                date > now
            {
                let summary = snapshot.day(on: day)
                if summary.events.isEmpty && summary.journal.isEmpty {
                    result.append(
                        NotificationRequest(
                            id: "journal-\(day)", date: date, title: String(localized: "Gününden bir an"),
                            body: String(localized: "Bugünden bir an yazmak ister misin?"), destination: .journal))
                }
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    static func identifiers(on day: CalendarDate) -> [String] {
        (0..<7).compactMap { day.addingDays($0) }.flatMap { day in
            ["task-\(day)", "goals-\(day)", "journal-\(day)"]
        }
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
        _ tasks: [TaskRow], on day: CalendarDate, hideContent: Bool
    ) -> (title: String, body: String)? {
        let open = tasks.filter { !$0.isClosed }
        let due = open.filter { $0.due == day }.sorted { $0.id < $1.id }
        let overdue = open.filter { $0.due.map { $0 < day } ?? false }.count
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
