import Foundation

/// What the app shares with its widget through the App Group (`AppIdentifiers.appGroup`).
/// `containerURL` is nil when the group is not available, as in an ad hoc signed Mac build or a
/// test: whatever uses the group is then off, silently. Tests give a temporary folder instead.
///
/// No key moved to the group yet: the vault bookmark and the app lock stay in
/// `UserDefaults.standard`, which only the app reads. Shared defaults
/// (`UserDefaults(suiteName:)`) come with the first key that needs them.
protocol AppGroupStore {
    var containerURL: URL? { get }
}

extension AppGroupStore {
    /// Where the app writes the widget snapshot; nil while the group is unavailable.
    var widgetSnapshotURL: URL? { containerURL.map(WidgetSnapshotFile.url(in:)) }
}

/// The real App Group container. On iOS the system answers nil without
/// the entitlement. On the Mac it answers a path even then, and touching it from a build without
/// the group asks the user for access: the Mac app does not use the group yet (its widgets are a
/// later wave), so nothing there creates this store.
struct SystemAppGroupStore: AppGroupStore {
    let identifier: String

    init(identifier: String = AppIdentifiers.appGroup) {
        self.identifier = identifier
    }

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
