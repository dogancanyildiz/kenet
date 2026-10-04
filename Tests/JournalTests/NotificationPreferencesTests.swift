import Foundation
import Testing

@testable import Journal

struct NotificationPreferencesTests {
    @Test func preferencesPersistPerDeviceAndInvalidStorageFallsBack() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        var settings = NotificationPreferences()
        settings.tasksEnabled = false
        settings.goalTime = NotificationTime(hour: 19, minute: 30)
        settings.persist(in: defaults.defaults)
        #expect(NotificationPreferences.read(from: defaults.defaults) == settings)
        settings.journalTime.hour = 24
        defaults.defaults.set(try JSONEncoder().encode(settings), forKey: NotificationPreferences.storageKey)
        #expect(NotificationPreferences.read(from: defaults.defaults) == NotificationPreferences())
        defaults.defaults.set(Data("invalid".utf8), forKey: NotificationPreferences.storageKey)
        #expect(NotificationPreferences.read(from: defaults.defaults) == NotificationPreferences())
    }
}
