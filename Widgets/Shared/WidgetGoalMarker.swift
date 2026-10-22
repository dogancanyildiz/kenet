import Foundation
import GoalTracking
import VaultFormat
import VaultIndex
import VaultStore

/// Marks an open yes/no goal for today from the widget's own process, without opening the app
/// (docs/architecture.md "Widget'lar"). Only for an iCloud vault: the widget reaches it through
/// the iCloud container, as the app does. A local or selected vault is the app's alone; its taps
/// open the app (``WidgetLink``).
///
/// The day file is written by Core's writer (`VaultStore.settingGoalValue`) under
/// `NSFileCoordinator` (``SystemFileCoordination``): a write the app makes to the same day at the
/// same time waits for this one, or this one for it, and each changes only its own lines. The
/// writer needs an index; it gets a throwaway one in memory (``throwawayIndex(for:)``). The app's
/// index is not touched: the app rescans the day files the next time it writes the snapshot
/// (``WidgetSnapshot/markedAt``).
///
/// Then the snapshot shows the mark at once (``WidgetSnapshot/marking(key:on:at:)``) and the
/// caller reloads the widget. Built in the app as well, so the tests run it.
struct WidgetGoalMarker: Sendable {
    /// What a tap came to.
    enum Outcome: Equatable, Sendable {
        /// The day file has the mark and the snapshot shows it.
        case marked
        /// Nothing to do: no snapshot (vault unavailable, app locked), the app's delayed lock has
        /// run out (``WidgetSnapshot/lockedAfter``), another vault, or the goal is not an open
        /// yes/no goal of today in the snapshot.
        case nothingToMark
        /// Not an iCloud vault: only the app writes it.
        case needsApp
        /// The iCloud vault cannot be written from here now: no container (iCloud off, signed
        /// out), no vault in it or another one than the app's, the day still downloading, a
        /// read-only vault. Nothing changed.
        case unavailable
    }

    /// The App Group container that holds the snapshot.
    let groupContainer: URL
    /// The iCloud container, nil when iCloud is off or signed out. Tests give a folder.
    let ubiquityContainer: @Sendable () async -> URL?
    let now: @Sendable () -> Date
    var calendar: Calendar = WidgetDay.deviceCalendar

    /// One snapshot change at a time in this process: two taps in a row both stay.
    private static let snapshotLock = NSLock()

    func mark(goalID: String) async -> Outcome {
        let snapshotURL = WidgetSnapshotFile.url(in: groupContainer)
        guard let snapshot = WidgetSnapshotFile.read(from: snapshotURL),
            snapshot.format == WidgetSnapshot.currentFormat
        else { return .nothingToMark }
        let prefix = WidgetSnapshot.intentID(vaultID: snapshot.vaultID, key: "")
        guard goalID.hasPrefix(prefix), goalID.count > prefix.count else { return .nothingToMark }
        let key = String(goalID.dropFirst(prefix.count))
        guard snapshot.widgetCanMark, let relative = snapshot.cloudRelativePath else { return .needsApp }
        let time = now()
        // The app counts as locked from here on: the same rule as its own intents (decision
        // 2026-10-06), though the widget process cannot ask the app.
        guard !snapshot.isLocked(at: time) else { return .nothingToMark }
        let today = WidgetDay.string(for: time, calendar: calendar)
        guard snapshot.marking(key: key, on: today, at: time) != nil, let day = CalendarDate(today) else {
            return .nothingToMark
        }

        guard let container = await ubiquityContainer() else { return .unavailable }
        let root = container.appendingPathComponent(relative, isDirectory: true)
        // Only a vault: nothing is created in a folder that is not one (or not downloaded yet).
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".app/vault.json").path) else {
            return .unavailable
        }
        // Only the vault the app wrote the snapshot for: another one in the same place (another
        // account, a replaced folder) is left alone until the app has seen it.
        guard WidgetSnapshot.cloudVaultIdentity(at: root) == snapshot.cloudVaultIdentity else { return .unavailable }
        do {
            let store = VaultStore(
                vaultRoot: root, index: try Self.throwawayIndex(for: root),
                fileCoordination: SystemFileCoordination())
            try await store.settingGoalValue(on: day, key: key, value: .boolean(true))
        } catch {
            return .unavailable
        }

        // The snapshot may have changed while the file was written (the app, another tap): the
        // mark goes onto the current one, and only if it still shows this vault's open goal.
        Self.snapshotLock.withLock {
            guard let current = WidgetSnapshotFile.read(from: snapshotURL), current.vaultID == snapshot.vaultID,
                let marked = current.marking(key: key, on: today, at: time)
            else { return }
            try? WidgetSnapshotFile.write(marked, to: snapshotURL)
        }
        return .marked
    }

    /// The in-memory index Core's writer updates after the write. Core rebuilds an empty index
    /// from the whole vault before it updates one file: seconds and megabytes on a five-year
    /// vault, more than a widget has. So the index starts from a stand-in vault of one empty note
    /// and the vault's own entity types (`.app/types.json`, which Core compares): the update after
    /// the write then reads the day file alone. Should the stand-in fail, the empty index still
    /// writes correctly, only slower. Nothing reads this index afterwards.
    /// `readFile` is the index's file reader; tests count its reads.
    static func throwawayIndex(
        for root: URL, readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) throws -> VaultIndex {
        let index = try VaultIndex(readFile: readFile)
        let manager = FileManager.default
        let standIn = manager.temporaryDirectory.appendingPathComponent(
            "widget-index-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: standIn) }
        do {
            let app = standIn.appendingPathComponent(".app", isDirectory: true)
            try manager.createDirectory(at: app, withIntermediateDirectories: true)
            let types = root.appendingPathComponent(".app/types.json")
            if manager.fileExists(atPath: types.path) {
                try Data(contentsOf: types).write(to: app.appendingPathComponent("types.json"))
            }
            try Data().write(to: standIn.appendingPathComponent("stand-in.md"))
            try index.rebuild(vaultRoot: standIn)
        } catch {
            return try VaultIndex(readFile: readFile)
        }
        return index
    }
}
