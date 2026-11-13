import Foundation

/// Names this device kept under the old code name before 2026-11-13: UserDefaults keys, the diary
/// reminder's identifier prefix, the geofence region prefix and the index folder. Launch moves each
/// stored value once to its new key and removes what only the old names held.
enum LegacyDefaults {
    /// The old code name the names were built from.
    static let codeName = "journal"

    /// Each old key and the key that replaced it: `<code name>.x` became `kenet.x`.
    static var renamedKeys: [(old: String, new: String)] {
        [
            NotificationPreferences.storageKey, CadenceReminderHistory.storageKey, GeofenceService.modesKey,
            GeofenceService.handledKey, LocationService.preferenceKey,
        ].map { new in (codeName + new.drop { $0 != "." }, new) }
    }

    /// Moves each old value to its new key. A value already under the new key wins; the old key is
    /// removed either way, so a second launch finds nothing to move.
    static func migrate(_ defaults: UserDefaults = .standard) {
        for (old, new) in renamedKeys {
            guard let value = defaults.object(forKey: old) else { continue }
            if defaults.object(forKey: new) == nil { defaults.set(value, forKey: new) }
            defaults.removeObject(forKey: old)
        }
    }

    /// Removes the index folder of older builds under Application Support. The index is rebuilt from
    /// the vault's files, so nothing is lost. Only `Indexes` is removed, and its parent only when empty.
    static func removeOldIndexes(applicationSupport: URL) {
        let parent = applicationSupport.appendingPathComponent(codeName.capitalized, isDirectory: true)
        try? FileManager.default.removeItem(at: parent.appendingPathComponent("Indexes", isDirectory: true))
        if (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}
