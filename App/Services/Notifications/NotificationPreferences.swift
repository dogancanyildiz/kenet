import Foundation

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
    var taskTime = NotificationTime(hour: 9)
    var goalTime = NotificationTime(hour: 20)
    var journalTime = NotificationTime(hour: 21)
    var isValid: Bool { taskTime.isValid && goalTime.isValid && journalTime.isValid }

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
}
