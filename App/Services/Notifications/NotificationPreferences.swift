import Foundation
import VaultFormat

struct NotificationTime: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int = 0
    var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }
}

/// Device preferences; authorization stays in system settings, and vault files stay untouched.
struct NotificationPreferences: Codable, Equatable, Sendable {
    var tasksEnabled = true
    var goalsEnabled = true
    var journalEnabled = true
    /// Optional meeting-cadence reminder. Off until the user turns it on; nothing is written to the vault.
    var peopleEnabled = false
    var taskTime = NotificationTime(hour: 9)
    var goalTime = NotificationTime(hour: 20)
    var journalTime = NotificationTime(hour: 21)
    var peopleTime = NotificationTime(hour: 10)
    /// When true, planned notifications omit task text, goal names and people names.
    var hideContent = false
    var isValid: Bool { taskTime.isValid && goalTime.isValid && journalTime.isValid && peopleTime.isValid }

    static let storageKey = "journal.notifications.v1"
    static func read(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
            let result = try? JSONDecoder().decode(Self.self, from: data), result.isValid
        else { return Self() }
        return result
    }
    func persist(in defaults: UserDefaults) {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    enum CodingKeys: String, CodingKey {
        case tasksEnabled, goalsEnabled, journalEnabled, peopleEnabled, taskTime, goalTime, journalTime, peopleTime,
            hideContent
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasksEnabled = try container.decodeIfPresent(Bool.self, forKey: .tasksEnabled) ?? true
        goalsEnabled = try container.decodeIfPresent(Bool.self, forKey: .goalsEnabled) ?? true
        journalEnabled = try container.decodeIfPresent(Bool.self, forKey: .journalEnabled) ?? true
        peopleEnabled = try container.decodeIfPresent(Bool.self, forKey: .peopleEnabled) ?? false
        taskTime = try container.decodeIfPresent(NotificationTime.self, forKey: .taskTime) ?? NotificationTime(hour: 9)
        goalTime = try container.decodeIfPresent(NotificationTime.self, forKey: .goalTime) ?? NotificationTime(hour: 20)
        journalTime =
            try container.decodeIfPresent(NotificationTime.self, forKey: .journalTime) ?? NotificationTime(hour: 21)
        peopleTime =
            try container.decodeIfPresent(NotificationTime.self, forKey: .peopleTime) ?? NotificationTime(hour: 10)
        hideContent = try container.decodeIfPresent(Bool.self, forKey: .hideContent) ?? false
    }
}

/// What a time field of the settings page shows and writes: one reminder time, as an instant of
/// the given day.
extension NotificationPreferences {
    func fieldDate(
        _ key: KeyPath<NotificationPreferences, NotificationTime>, on day: CalendarDate, timeZone: TimeZone
    ) -> Date {
        NotificationPlanner.fireDate(day, time: self[keyPath: key], timeZone: timeZone)
            ?? LocalDay.instant(for: day, timeZone: timeZone)
    }

    /// Only the hour and the minute of `date` are kept, and only this reminder changes.
    mutating func setTime(
        _ key: WritableKeyPath<NotificationPreferences, NotificationTime>, from date: Date, timeZone: TimeZone
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self[keyPath: key] = NotificationTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
