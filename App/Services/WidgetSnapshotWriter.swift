import CryptoKit
import Foundation
import GoalTracking
import VaultFormat
import VaultIndex
import WidgetKit

/// Asks WidgetKit to redraw a widget kind; a fake counts the calls in tests.
@MainActor protocol WidgetTimelineReloading {
    func reloadTimelines(ofKind kind: String)
}

struct SystemWidgetTimelines: WidgetTimelineReloading {
    func reloadTimelines(ofKind kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}

/// Keeps the widget snapshot (`WidgetSnapshot`) in the App Group in step with the vault
/// (docs/architecture.md "Widget'lar"). On every publish of the store it asks the index for the
/// goal statuses of today and tomorrow (`VaultIndex.goalStatuses`, the query the screens use),
/// writes the file atomically and reloads the widget. With the vault unavailable the file is
/// removed: the widget then shows "open Kenet". While the app is locked the file is left as it
/// is; only a lock the app engages while it runs removes it (`lockEngaged`), and a delayed one
/// leaves the moment it engages in the file (`lockDeferred`). The widget never opens the index;
/// nothing here is the source of truth.
///
/// In an iCloud vault the widget marks a goal itself (`WidgetGoalMarker`): it writes the day file
/// and shows the mark in the snapshot (`markedAt`). The index has not seen that write yet, so the
/// next write here first rescans the day files and only then queries: the widget's mark is never
/// replaced by the index's older answer.
@MainActor final class WidgetSnapshotWriter {
    private let store: IndexStore
    private let group: any AppGroupStore
    private let timelines: any WidgetTimelineReloading
    private let isLocked: () -> Bool
    /// When a delayed lock engages while the app is away (`AppLockService.locksAt`), nil otherwise.
    private let lockDeadline: () -> Date?
    private let now: () -> Date
    private var running: Task<Void, Never>?
    private var again = false
    /// The widget mark (`WidgetSnapshot.markedAt`) whose day files were rescanned already.
    private var reconciledMark: Date?

    init(
        store: IndexStore, group: any AppGroupStore, timelines: any WidgetTimelineReloading = SystemWidgetTimelines(),
        isLocked: @escaping () -> Bool, lockDeadline: @escaping () -> Date? = { nil },
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.group = group
        self.timelines = timelines
        self.isLocked = isLocked
        self.lockDeadline = lockDeadline
        self.now = now
    }

    /// Follows the store's publishes; the store's other listeners stay as they are.
    func attach() {
        store.onWidgetSnapshotChange = { [weak self] in self?.update() }
    }

    /// Brings the snapshot up to date. A call while an update runs runs it once more afterwards,
    /// so the last publish always wins.
    func update() {
        guard running == nil else {
            again = true
            return
        }
        running = Task { [weak self] in await self?.drain() }
    }

    /// Returns once no update runs.
    func settle() async {
        while let running { await running.value }
    }

    private func drain() async {
        repeat {
            again = false
            await write()
        } while again
        running = nil
    }

    /// The app engaged its lock while running (docs/architecture.md "Widget'lar"): the widget
    /// shows "open Kenet" until the unlock writes again. A lock found on arriving in the
    /// foreground, or one that ran out in the background, leaves the file alone.
    func lockEngaged() {
        guard let url = group.widgetSnapshotURL else { return }
        remove(url)
    }

    /// The app went to the background with a delayed lock: the file keeps its days and learns
    /// the moment the lock engages (`WidgetSnapshot.lockedAfter`). From then on the widget shows
    /// "open Kenet" and marks nothing, though no app runs to remove the file. Written at once,
    /// not after a query: the app may be suspended any moment now. The next write in the
    /// foreground, unlocked, leaves the moment out.
    func lockDeferred() {
        guard let url = group.widgetSnapshotURL, let deadline = lockDeadline(),
            var written = WidgetSnapshotFile.read(from: url), written.lockedAfter != deadline
        else { return }
        written.lockedAfter = deadline
        do { try WidgetSnapshotFile.write(written, to: url) } catch { return }
        timelines.reloadTimelines(ofKind: WidgetKinds.goalChain)
    }

    private func write() async {
        guard let url = group.widgetSnapshotURL else { return }
        // Locked: nothing is written or removed; the unlock writes once.
        if isLocked() { return }
        if store.isVaultInaccessible {
            remove(url)
            return
        }
        guard let root = store.vaultURL else { return }
        guard store.lastUpdated != nil else {
            // Not started yet, or a vault still opening: its first publish writes. Another
            // vault's snapshot goes now, in case this one never publishes.
            if let written = WidgetSnapshotFile.read(from: url), written.vaultID != Self.vaultID(for: root) {
                remove(url)
            }
            return
        }
        let vaultID = Self.vaultID(for: root)
        if let written = WidgetSnapshotFile.read(from: url), written.vaultID == vaultID,
            let markedAt = written.markedAt, markedAt != reconciledMark
        {
            // The widget wrote a day file since: the index learns it before it answers.
            reconciledMark = markedAt
            await store.refresh(directories: ["journal"])
            await store.waitWhileRefreshInFlight()
        }
        let today = LocalDay.today(at: now())
        guard let tomorrow = today.addingDays(1) else { return }
        let cloudPath = store.cloudRelativeVaultPath
        let snapshot: WidgetSnapshot
        do {
            let current = try await store.computeGoalStatuses(today: today)
            let next = try await store.computeGoalStatuses(today: tomorrow)
            snapshot = WidgetSnapshot(
                writtenAt: now(), vaultID: vaultID,
                days: [.init(date: today, rows: current), .init(date: tomorrow, rows: next)],
                vaultKind: WidgetSnapshot.VaultKind(rawValue: store.vaultKind.rawValue),
                cloudRelativePath: cloudPath,
                cloudVaultIdentity: cloudPath == nil ? nil : WidgetSnapshot.cloudVaultIdentity(at: root),
                lockedAfter: lockDeadline())
        } catch {
            // Another vault opened meanwhile (its publish updates again) or the read failed: the
            // file keeps the last answer.
            return
        }
        // The app may have locked, or lost the vault, while the queries ran.
        if isLocked() { return }
        if store.isVaultInaccessible {
            remove(url)
            return
        }
        if let written = WidgetSnapshotFile.read(from: url), written.hasSameContent(as: snapshot) {
            // The index agrees with the widget's mark: the mark goes, the widget has nothing new to draw.
            if written.markedAt != nil { try? WidgetSnapshotFile.write(snapshot, to: url) }
            return
        }
        do { try WidgetSnapshotFile.write(snapshot, to: url) } catch { return }
        timelines.reloadTimelines(ofKind: WidgetKinds.goalChain)
    }

    private func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
        timelines.reloadTimelines(ofKind: WidgetKinds.goalChain)
    }

    /// SHA-256 of the vault's resolved path: the vault part of `IntentGoal.id`.
    static func vaultID(for root: URL) -> String {
        let path = root.resolvingSymlinksInPath().standardizedFileURL.path
        return SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension WidgetSnapshot.Day {
    /// The daily yes/no and number goals of `rows` (statuses computed for `date`), open ones
    /// first. Weekly and yearly goals and milestones have no daily chain and stay out.
    init(date: CalendarDate, rows: [GoalStatusRow]) {
        self.init(date: "\(date)", goals: WidgetSnapshot.ordered(rows.compactMap(WidgetSnapshot.Goal.init(row:))))
    }
}

extension WidgetSnapshot.Goal {
    init?(row: GoalStatusRow) {
        let goal = row.definition
        guard goal.period == .day else { return nil }
        let kind: WidgetSnapshot.Kind
        switch goal.kind {
        case .boolean: kind = .boolean
        case .number: kind = .number
        case .milestone: return nil
        }
        self.init(
            key: goal.key, name: goal.name, kind: kind, target: goal.target, unit: goal.unit,
            value: row.status.progress.done, isPending: row.status.isPendingToday,
            streak: row.status.streak, chainDays: row.graceDaysAvailable)
    }
}

/// The app's side of a widget tap (`WidgetLink`): it opens Today and marks a yes/no goal for
/// today through the App Intent path (`IntentActions.markGoal`). A local or selected vault's
/// goals come this way; an iCloud vault's are marked in the widget (`WidgetGoalMarker`). A mark
/// asked while the app is locked waits for the unlock.
///
/// The link's source is not checked: the app registers no URL scheme, so only WidgetKit opens a
/// `kenet-widget` link here (`ReleaseConfigurationTests`). A registered scheme would let any app
/// mark goals; it then needs a source check first.
@MainActor final class WidgetLinkHandler {
    private let actions: IntentActions
    private let navigation: IntentNavigation
    /// The goal a tap asked to mark while the app was locked.
    private(set) var pendingMark: String?

    init(actions: IntentActions, navigation: IntentNavigation) {
        self.actions = actions
        self.navigation = navigation
    }

    /// False for a URL that is not a widget link; it is left to whoever else handles it.
    @discardableResult func open(_ url: URL) async -> Bool {
        guard let link = WidgetLink(url: url) else { return false }
        navigation.openToday()
        if case .markGoal(let id) = link { await mark(id) }
        return true
    }

    /// Marks the goal a locked tap asked for.
    func unlocked() async {
        guard let id = pendingMark else { return }
        pendingMark = nil
        await mark(id)
    }

    private func mark(_ id: String) async {
        do {
            _ = try await actions.markGoal(id: id)
        } catch IntentActionError.appLocked {
            pendingMark = id
        } catch {
            // The goal or the vault is gone since the widget drew: Today shows the day as it is.
        }
    }
}
