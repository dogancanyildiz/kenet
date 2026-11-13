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
    var diaryEnabled = true
    /// Optional meeting-cadence reminder. Off until the user turns it on; nothing is written to the vault.
    var peopleEnabled = false
    var taskTime = NotificationTime(hour: 9)
    var goalTime = NotificationTime(hour: 20)
    var diaryTime = NotificationTime(hour: 21)
    var peopleTime = NotificationTime(hour: 10)
    /// When true, planned notifications omit task text, goal names and people names. On until the
    /// user turns content on; a stored choice is kept, and a record written before the field
    /// existed reads as hidden.
    var hideContent = true
    var isValid: Bool { taskTime.isValid && goalTime.isValid && diaryTime.isValid && peopleTime.isValid }

    static let storageKey = "kenet.notifications.v1"
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
        case tasksEnabled, goalsEnabled, diaryEnabled, peopleEnabled, taskTime, goalTime, diaryTime, peopleTime,
            hideContent
    }

    /// The diary reminder's field names in a record written before 2026-11-13; read when the
    /// current name is absent, never written (`LegacyDefaults`).
    private struct LegacyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static let diaryEnabled = Self(stringValue: LegacyDefaults.codeName + "Enabled")
        static let diaryTime = Self(stringValue: LegacyDefaults.codeName + "Time")
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasksEnabled = try container.decodeIfPresent(Bool.self, forKey: .tasksEnabled) ?? true
        goalsEnabled = try container.decodeIfPresent(Bool.self, forKey: .goalsEnabled) ?? true
        let legacy = try decoder.container(keyedBy: LegacyKey.self)
        diaryEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .diaryEnabled)
            ?? legacy.decodeIfPresent(Bool.self, forKey: .diaryEnabled) ?? true
        peopleEnabled = try container.decodeIfPresent(Bool.self, forKey: .peopleEnabled) ?? false
        taskTime = try container.decodeIfPresent(NotificationTime.self, forKey: .taskTime) ?? NotificationTime(hour: 9)
        goalTime = try container.decodeIfPresent(NotificationTime.self, forKey: .goalTime) ?? NotificationTime(hour: 20)
        diaryTime =
            try container.decodeIfPresent(NotificationTime.self, forKey: .diaryTime)
            ?? legacy.decodeIfPresent(NotificationTime.self, forKey: .diaryTime) ?? NotificationTime(hour: 21)
        peopleTime =
            try container.decodeIfPresent(NotificationTime.self, forKey: .peopleTime) ?? NotificationTime(hour: 10)
        hideContent = try container.decodeIfPresent(Bool.self, forKey: .hideContent) ?? true
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
