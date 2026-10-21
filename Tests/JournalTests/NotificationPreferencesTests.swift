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

    /// A device that never changed notification settings has no record: content is hidden.
    @Test func contentIsHiddenWithoutAStoredRecord() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        #expect(defaults.defaults.data(forKey: NotificationPreferences.storageKey) == nil)
        #expect(NotificationPreferences.read(from: defaults.defaults).hideContent)
        #expect(NotificationPreferences().hideContent)
    }

    /// A record written before the field existed carries no choice for it: content is hidden,
    /// and every other stored field is kept.
    @Test func missingHideContentDefaultsToHiddenWhilePreservingOtherFields() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let legacy: [String: Any] = [
            "tasksEnabled": false,
            "goalsEnabled": true,
            "journalEnabled": true,
            "taskTime": ["hour": 10, "minute": 15],
            "goalTime": ["hour": 20, "minute": 0],
            "journalTime": ["hour": 21, "minute": 0],
        ]
        defaults.defaults.set(
            try JSONSerialization.data(withJSONObject: legacy), forKey: NotificationPreferences.storageKey)
        let settings = NotificationPreferences.read(from: defaults.defaults)
        #expect(settings.hideContent)
        #expect(settings.tasksEnabled == false)
        #expect(settings.taskTime == NotificationTime(hour: 10, minute: 15))
        #expect(settings.peopleEnabled == false)
        #expect(settings.peopleTime == NotificationTime(hour: 10))
    }

    /// A stored choice is kept as it was written, whichever way it went.
    @Test func storedHideContentChoiceIsKept() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        for hidden in [false, true] {
            let stored: [String: Any] = [
                "tasksEnabled": true,
                "taskTime": ["hour": 9, "minute": 0],
                "goalTime": ["hour": 20, "minute": 0],
                "journalTime": ["hour": 21, "minute": 0],
                "hideContent": hidden,
            ]
            defaults.defaults.set(
                try JSONSerialization.data(withJSONObject: stored), forKey: NotificationPreferences.storageKey)
            #expect(NotificationPreferences.read(from: defaults.defaults).hideContent == hidden)
        }
        var shown = NotificationPreferences()
        shown.hideContent = false
        shown.persist(in: defaults.defaults)
        #expect(NotificationPreferences.read(from: defaults.defaults).hideContent == false)
    }
}
