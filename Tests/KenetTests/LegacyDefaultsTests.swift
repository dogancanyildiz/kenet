import Foundation
import Testing
import VaultFormat

@testable import Kenet

/// Values a build before 2026-11-13 stored under the old code name reach the new names once.
struct LegacyDefaultsTests {
    /// The old key of `new`: `kenet.x` was `<old code name>.x`.
    private func old(_ new: String) throws -> String {
        try #require(LegacyDefaults.renamedKeys.first { $0.new == new }?.old)
    }

    @Test func everyRenamedKeyKeepsItsSuffixUnderTheOldCodeName() {
        let pairs = LegacyDefaults.renamedKeys
        #expect(pairs.count == 5)
        for (old, new) in pairs {
            #expect(new.hasPrefix("kenet."))
            #expect(old == LegacyDefaults.codeName + "." + new.dropFirst("kenet.".count))
        }
        #expect(
            Set(pairs.map(\.new)) == [
                NotificationPreferences.storageKey, CadenceReminderHistory.storageKey, GeofenceService.modesKey,
                GeofenceService.handledKey, LocationService.preferenceKey,
            ])
    }

    @Test func oldValuesMoveOnceAndTheOldKeysGo() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let store = defaults.defaults
        store.set(false, forKey: try old(LocationService.preferenceKey))
        store.set(["a": "silent"], forKey: try old(GeofenceService.modesKey))
        store.set(Data("[]".utf8), forKey: try old(CadenceReminderHistory.storageKey))
        LegacyDefaults.migrate(store)
        #expect(store.object(forKey: LocationService.preferenceKey) as? Bool == false)
        #expect(store.dictionary(forKey: GeofenceService.modesKey) as? [String: String] == ["a": "silent"])
        #expect(store.data(forKey: CadenceReminderHistory.storageKey) == Data("[]".utf8))
        for (old, _) in LegacyDefaults.renamedKeys { #expect(store.object(forKey: old) == nil, "\(old)") }
        // A second launch finds nothing to move and changes nothing.
        store.set(true, forKey: LocationService.preferenceKey)
        LegacyDefaults.migrate(store)
        #expect(store.object(forKey: LocationService.preferenceKey) as? Bool == true)
    }

    /// A value already under the new key wins; the old one is removed anyway.
    @Test func aNewValueIsNeverOverwritten() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let store = defaults.defaults
        store.set(true, forKey: LocationService.preferenceKey)
        store.set(false, forKey: try old(LocationService.preferenceKey))
        LegacyDefaults.migrate(store)
        #expect(store.object(forKey: LocationService.preferenceKey) as? Bool == true)
        #expect(store.object(forKey: try old(LocationService.preferenceKey)) == nil)
    }

    /// The notification settings record of an older build names the diary reminder's fields by the
    /// old code name; they are read once and written under the new names.
    @Test func olderNotificationRecordKeepsTheDiaryReminder() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let store = defaults.defaults
        let record: [String: Any] = [
            "tasksEnabled": true, LegacyDefaults.codeName + "Enabled": false,
            LegacyDefaults.codeName + "Time": ["hour": 22, "minute": 45], "hideContent": false,
        ]
        store.set(
            try JSONSerialization.data(withJSONObject: record), forKey: try old(NotificationPreferences.storageKey))
        LegacyDefaults.migrate(store)
        let read = NotificationPreferences.read(from: store)
        #expect(!read.diaryEnabled)
        #expect(read.diaryTime == NotificationTime(hour: 22, minute: 45))
        #expect(!read.hideContent)
        read.persist(in: store)
        let data = try #require(store.data(forKey: NotificationPreferences.storageKey))
        let written = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(written["diaryEnabled"] as? Bool == false)
        #expect(written.keys.allSatisfy { !$0.hasPrefix(LegacyDefaults.codeName) })
    }

    /// A diary reminder an older build left pending or delivered opens the diary, so the next plan
    /// counts it as its own and removes it.
    @Test func olderDiaryReminderIdentifiersStillRoute() {
        #expect(NotificationDestination.from(identifier: LegacyDefaults.codeName + "-2026-10-03") == .diary)
        #expect(NotificationDestination.from(identifier: "diary-2026-10-03") == .diary)
        #expect(NotificationDestination.from(identifier: LegacyDefaults.codeName + "-x") == nil)
        #expect(GeofenceRegion.legacyPrefix != GeofenceRegion.prefix)
        #expect(!GeofenceRegion.prefix.hasPrefix(GeofenceRegion.legacyPrefix))
    }

    @Test func theOldIndexFolderIsRemovedButNotItsNeighbours() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let parent = support.appendingPathComponent(LegacyDefaults.codeName.capitalized)
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("Indexes/abc"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: parent.appendingPathComponent("Indexes/abc/index.sqlite"))
        try Data("başka".utf8).write(to: parent.appendingPathComponent("other.txt"))
        LegacyDefaults.removeOldIndexes(applicationSupport: support)
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("Indexes").path))
        #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("other.txt").path))
        try FileManager.default.removeItem(at: parent.appendingPathComponent("other.txt"))
        LegacyDefaults.removeOldIndexes(applicationSupport: support)
        #expect(!FileManager.default.fileExists(atPath: parent.path))
    }
}
