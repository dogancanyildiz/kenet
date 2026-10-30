import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

/// Counts WidgetKit reloads instead of asking the system.
@MainActor final class FakeWidgetTimelines: WidgetTimelineReloading {
    private(set) var reloads: [String] = []
    /// Existing publish-count assertions concern the chain widget, independently of other kinds.
    var goalChainReloads: [String] { reloads.filter { $0 == WidgetKinds.goalChain } }
    func reloadTimelines(ofKind kind: String) { reloads.append(kind) }
}

/// A temporary folder standing in for the App Group container; nil is an unavailable group.
struct FolderAppGroupStore: AppGroupStore {
    let containerURL: URL?
}

/// The widget snapshot (docs/architecture.md "Widget'lar"): the app writes it from the goal
/// status query on every publish, the widget only reads it. The vault is `GraceDayVault`:
/// on 20 September "Esneme" (yes/no) is open with a 64-day chain and 2 chain days, "Okuma"
/// (20 sayfa) is open too.
@MainActor @Suite("Widget snapshot")
struct WidgetSnapshotTests {
    /// Noon of `GraceDayVault.today` in the time zone `LocalDay` uses.
    nonisolated static let noon: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))!
    }()
    nonisolated static let tomorrow = GraceDayVault.today.addingDays(1)!

    final class Lock {
        var isLocked = false
        /// `AppLockService.locksAt`: when a delayed lock engages while the app is away.
        var locksAt: Date?
    }

    final class Clock {
        var now = WidgetSnapshotTests.noon
    }

    @MainActor struct Harness {
        let context: TaskTestContext
        let container: URL
        let timelines = FakeWidgetTimelines()
        let lock = Lock()
        let clock = Clock()
        let writer: WidgetSnapshotWriter

        init(group: Bool = true) throws {
            context = try TaskTestContext()
            try GraceDayVault.generate(at: context.root)
            container = context.directory.appendingPathComponent("group", isDirectory: true)
            let lock = lock
            let clock = clock
            writer = WidgetSnapshotWriter(
                store: context.store, group: FolderAppGroupStore(containerURL: group ? container : nil),
                timelines: timelines, isLocked: { lock.isLocked }, lockDeadline: { lock.locksAt },
                now: { clock.now })
            writer.attach()
        }

        var file: URL { WidgetSnapshotFile.url(in: container) }
        var snapshot: WidgetSnapshot? { WidgetSnapshotFile.read(from: file) }

        func start() async {
            await context.start()
            await writer.settle()
        }
    }

    private func statuses(_ logs: [GoalLog], on day: CalendarDate) -> GoalStatus {
        GoalProgress.compute(definition: GraceDayVault.stretching, logs: logs, today: day)
    }

    @Test func publishWritesTodayAndTomorrowFromTheGoalQuery() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()

        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.format == WidgetSnapshot.currentFormat)
        #expect(snapshot.writtenAt == Self.noon)
        #expect(snapshot.days.map(\.date) == ["2026-09-20", "2026-09-21"])
        #expect(harness.timelines.goalChainReloads == [WidgetKinds.goalChain])

        // Today: both open, by name; the chain and its chain days are the vault's.
        let today = snapshot.days[0].goals
        #expect(today.map(\.key) == ["esneme", "okuma"])
        #expect(today.allSatisfy { $0.isPending })
        #expect(today[0].kind == .boolean)
        #expect(today[0].streak == GraceDayVault.streak)
        #expect(today[0].chainDays == GraceDayVault.balance)
        #expect(today[0].value == 0)
        #expect(today[1].kind == .number)
        #expect(today[1].target == 20)
        #expect(today[1].unit == "sayfa")
        #expect(today[1].chainDays == 0)

        // Tomorrow, with today left open: today is a miss, as Core counts it from tomorrow.
        let expected = statuses(GraceDayVault.stretchingLogs, on: Self.tomorrow)
        let next = try #require(snapshot.days[1].goals.first { $0.key == "esneme" })
        #expect(next.isPending)
        #expect(next.value == 0)
        #expect(next.streak == expected.streak)
        #expect(next.chainDays == expected.graceDaysAvailable)
    }

    /// The link a widget row opens names the goal as the App Intents do (`IntentGoal.id`).
    @Test func vaultIdentityIsTheIntentGoalIdentity() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        let snapshot = try #require(harness.snapshot)
        let root = try #require(harness.context.store.vaultURL)
        let intentID = IntentGoal(definition: GraceDayVault.stretching, root: root).id
        let goal = try #require(snapshot.days[0].goals.first { $0.key == "esneme" })
        #expect(WidgetSnapshot.intentID(vaultID: snapshot.vaultID, key: goal.key) == intentID)
        #expect(WidgetSnapshot.link(for: goal, vaultID: snapshot.vaultID) == .markGoal(id: intentID))
    }

    @Test func markingRewritesWithOpenGoalsFirst() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()

        try await harness.context.store.setGoal(on: GraceDayVault.today, key: "esneme", value: .boolean(true))
        await harness.writer.settle()

        let snapshot = try #require(harness.snapshot)
        let today = snapshot.days[0].goals
        #expect(today.map(\.key) == ["okuma", "esneme"])
        #expect(today.map(\.isPending) == [true, false])
        #expect(today[1].value == 1)
        #expect(today[1].streak == GraceDayVault.streak + 1)
        let logs = GraceDayVault.stretchingLogs + [GoalLog(day: GraceDayVault.today, value: .boolean(true))]
        let next = try #require(snapshot.days[1].goals.first { $0.key == "esneme" })
        #expect(next.isPending)
        #expect(next.streak == statuses(logs, on: Self.tomorrow).streak)
        #expect(next.chainDays == GraceDayVault.balance)
        #expect(harness.timelines.goalChainReloads == [WidgetKinds.goalChain, WidgetKinds.goalChain])
    }

    /// A publish that changes no goal leaves the file and the widget alone.
    @Test func aPublishWithoutGoalChangesWritesNothing() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        let before = try Data(contentsOf: harness.file)

        #expect(await harness.context.store.addEvent(on: GraceDayVault.today, text: "Yürüyüş", time: nil))
        await harness.writer.settle()

        #expect(try Data(contentsOf: harness.file) == before)
        #expect(harness.timelines.goalChainReloads.count == 1)
    }

    @Test func lockedAppWritesNothing() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        harness.lock.isLocked = true
        await harness.start()
        #expect(harness.context.store.lastUpdated != nil)
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
        #expect(harness.timelines.goalChainReloads.isEmpty)

        harness.lock.isLocked = false
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot != nil)
        #expect(harness.timelines.goalChainReloads.count == 1)
    }

    /// A lock the app engages while it runs removes the snapshot: the widget shows "open Kenet".
    /// Publishes while locked leave it removed; the unlock writes it once.
    @Test func lockingRemovesTheSnapshot() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.snapshot != nil)

        harness.lock.isLocked = true
        harness.writer.lockEngaged()
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
        #expect(harness.timelines.goalChainReloads.count == 2)

        harness.writer.update()
        try await harness.context.store.setGoal(on: GraceDayVault.today, key: "esneme", value: .boolean(true))
        await harness.writer.settle()
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
        #expect(harness.timelines.goalChainReloads.count == 2)

        harness.lock.isLocked = false
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot?.days[0].goals.last?.isPending == false)
        #expect(harness.timelines.goalChainReloads.count == 3)
    }

    /// A lock found on arriving in the foreground (it ran out in the background) leaves the
    /// file as it is: no remove and rewrite flicker. Even a publish that changes a goal waits;
    /// the unlock writes once.
    @Test func foregroundWhileLockedLeavesTheSnapshotAlone() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        let before = try Data(contentsOf: harness.file)

        harness.lock.isLocked = true
        harness.writer.update()
        try await harness.context.store.setGoal(on: GraceDayVault.today, key: "esneme", value: .boolean(true))
        await harness.writer.settle()
        #expect(try Data(contentsOf: harness.file) == before)
        #expect(harness.timelines.goalChainReloads.count == 1)

        harness.lock.isLocked = false
        harness.writer.update()
        await harness.writer.settle()
        #expect(try Data(contentsOf: harness.file) != before)
        #expect(harness.snapshot?.days[0].goals.last?.key == "esneme")
        #expect(harness.timelines.goalChainReloads.count == 2)
    }

    /// A publish that arrives while a write runs is not lost: the writer runs once more, and the
    /// file ends with the last publish (here a new day).
    @Test func publishDuringAWriteRunsOnceMoreAndTheLastWins() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.snapshot?.days.map(\.date) == ["2026-09-20", "2026-09-21"])

        let store = harness.context.store
        let clock = harness.clock
        let writer = harness.writer
        store.testingGoalStatusQueryDidFinish = {
            store.testingGoalStatusQueryDidFinish = nil
            clock.now = WidgetSnapshotTests.noon.addingTimeInterval(24 * 3600)
            writer.update()
        }
        writer.update()
        await writer.settle()

        #expect(harness.snapshot?.days.map(\.date) == ["2026-09-21", "2026-09-22"])
        #expect(harness.timelines.goalChainReloads.count == 2)
    }

    /// Weekly and yearly goals and milestones have no daily chain: the goal query answers them,
    /// the widget leaves them out.
    @Test func onlyDailyGoalsReachTheWidget() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        let goals = [
            "Spor": "name: Spor\nkey: spor\nperiod: week\nkind: boolean\ntarget: 3",
            "Kitap": "name: Kitap\nkey: kitap\nperiod: year\nkind: number\ntarget: 12",
            "Portfolyo": "name: Portfolyo\nkey: portfolyo\nperiod: year\nkind: milestone",
        ]
        for (name, front) in goals {
            try Data("---\ntype: goal\n\(front)\n---\n".utf8)
                .write(to: harness.context.root.appendingPathComponent("goals/\(name).md"))
        }
        await harness.start()

        let answered = try await harness.context.store.computeGoalStatuses(today: GraceDayVault.today)
        #expect(Set(answered.map(\.definition.key)) == ["esneme", "okuma", "spor", "kitap", "portfolyo"])
        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.days.map { $0.goals.map(\.key) } == [["esneme", "okuma"], ["esneme", "okuma"]])
    }

    @Test func inaccessibleVaultRemovesTheSnapshot() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.snapshot != nil)

        let moved = harness.context.directory.appendingPathComponent("Moved", isDirectory: true)
        try FileManager.default.moveItem(at: harness.context.root, to: moved)
        await harness.context.store.retryVaultAccess()
        #expect(harness.context.store.isVaultInaccessible)
        await harness.writer.settle()

        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
        #expect(harness.timelines.goalChainReloads.count == 2)
    }

    /// Another vault that never publishes (its index cannot open) does not leave the previous
    /// vault's goals on the widget.
    @Test func anotherVaultOpeningRemovesThePreviousSnapshot() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.snapshot != nil)

        let other = harness.context.directory.appendingPathComponent("Other", isDirectory: true)
        try GraceDayVault.generate(at: other)
        // A folder where the other vault's index file goes: the index cannot open.
        let blocked = harness.context.directory.appendingPathComponent(
            "indexes/\(WidgetSnapshotWriter.vaultID(for: other)).sqlite", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        await harness.context.store.select(other)
        await harness.writer.settle()

        #expect(harness.context.store.lastUpdated == nil)
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
    }

    @Test func unavailableGroupWritesNothing() async throws {
        let harness = try Harness(group: false)
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.context.store.lastUpdated != nil)
        #expect(!FileManager.default.fileExists(atPath: harness.container.path))
        #expect(harness.timelines.goalChainReloads.isEmpty)
    }

    /// The widget listener is the store's own: the snapshot listener the notifications use still
    /// hears every publish.
    @Test func snapshotListenerStillHearsPublishes() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        var heard: [Bool] = []
        harness.context.store.onSnapshotChange = { content, _ in heard.append(content != nil) }
        await harness.start()
        #expect(heard.last == true)
        #expect(harness.snapshot != nil)
    }

    // MARK: - File

    /// The file is replaced, never rewritten in place: a reader holding the old file (here a hard
    /// link to it) keeps a whole old snapshot while the new one lands.
    @Test func writeReplacesTheFileAtomically() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = WidgetSnapshotFile.url(in: directory)
        let first = WidgetSnapshot(writtenAt: Self.noon, vaultID: "a", days: [])
        try WidgetSnapshotFile.write(first, to: url)
        #expect(WidgetSnapshotFile.read(from: url) == first)

        let reader = directory.appendingPathComponent("reader.json")
        try FileManager.default.linkItem(at: url, to: reader)
        let second = WidgetSnapshot(
            writtenAt: Self.noon, vaultID: "b",
            days: [.init(date: "2026-09-20", goals: [Self.goal("su", pending: true)])])
        try WidgetSnapshotFile.write(second, to: url)

        #expect(WidgetSnapshotFile.read(from: url) == second)
        #expect(WidgetSnapshotFile.read(from: reader) == first)
    }

    @Test func unreadableFileIsNoSnapshot() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = WidgetSnapshotFile.url(in: directory)
        #expect(WidgetSnapshotFile.read(from: url) == nil)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        #expect(WidgetSnapshotFile.read(from: url) == nil)
    }

    // MARK: - Timeline

    static func goal(_ key: String, pending: Bool, kind: WidgetSnapshot.Kind = .boolean) -> WidgetSnapshot.Goal {
        WidgetSnapshot.Goal(
            key: key, name: key.capitalized, kind: kind, target: 1, unit: nil, value: pending ? 0 : 1,
            isPending: pending, streak: 3, chainDays: 0)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// At midnight the widget moves to the next day's entry (every goal open again), and after
    /// the last stored day it shows "open Kenet".
    @Test func timelineMovesToTomorrowThenOpensKenet() {
        let today = WidgetSnapshot.Day(date: "2026-09-20", goals: [Self.goal("esneme", pending: false)])
        let tomorrow = WidgetSnapshot.Day(date: "2026-09-21", goals: [Self.goal("esneme", pending: true)])
        let snapshot = WidgetSnapshot(writtenAt: date(20, hour: 9), vaultID: "v", days: [today, tomorrow])

        #expect(
            snapshot.timeline(from: date(20, hour: 12), calendar: calendar) == [
                WidgetTimelineEntry(date: date(20, hour: 12), day: today),
                WidgetTimelineEntry(date: date(21), day: tomorrow),
                WidgetTimelineEntry(date: date(22), day: nil),
            ])
        #expect(
            snapshot.timeline(from: date(21, hour: 8), calendar: calendar) == [
                WidgetTimelineEntry(date: date(21, hour: 8), day: tomorrow),
                WidgetTimelineEntry(date: date(22), day: nil),
            ])
        #expect(
            snapshot.timeline(from: date(23), calendar: calendar) == [WidgetTimelineEntry(date: date(23), day: nil)])

        var other = snapshot
        other.format += 1
        #expect(
            other.timeline(from: date(20, hour: 12), calendar: calendar) == [
                WidgetTimelineEntry(date: date(20, hour: 12), day: nil)
            ])
    }

    /// A delayed lock ends the timeline early: "open Kenet" from the moment the lock engages, or
    /// at once when that moment is past. A moment after the last day changes nothing.
    @Test func timelineEndsWhereTheDelayedLockEngages() {
        let today = WidgetSnapshot.Day(date: "2026-09-20", goals: [Self.goal("esneme", pending: true)])
        let tomorrow = WidgetSnapshot.Day(date: "2026-09-21", goals: [Self.goal("esneme", pending: true)])
        var snapshot = WidgetSnapshot(writtenAt: date(20, hour: 9), vaultID: "v", days: [today, tomorrow])
        let unlocked = snapshot.timeline(from: date(20, hour: 12), calendar: calendar)

        snapshot.lockedAfter = date(20, hour: 23)
        #expect(
            snapshot.timeline(from: date(20, hour: 12), calendar: calendar) == [
                WidgetTimelineEntry(date: date(20, hour: 12), day: today),
                WidgetTimelineEntry(date: date(20, hour: 23), day: nil),
            ])
        #expect(
            snapshot.timeline(from: date(20, hour: 23), calendar: calendar) == [
                WidgetTimelineEntry(date: date(20, hour: 23), day: nil)
            ])
        #expect(!snapshot.isLocked(at: date(20, hour: 22)))
        #expect(snapshot.isLocked(at: date(20, hour: 23)))

        snapshot.lockedAfter = date(23)
        #expect(snapshot.timeline(from: date(20, hour: 12), calendar: calendar) == unlocked)
    }

    @Test func openGoalsComeFirstThenByName() {
        let goals = [
            Self.goal("yuruyus", pending: false), Self.goal("su", pending: true),
            Self.goal("esneme", pending: false), Self.goal("okuma", pending: true),
        ]
        #expect(WidgetSnapshot.ordered(goals).map(\.key) == ["okuma", "su", "esneme", "yuruyus"])
    }

    // MARK: - Marking in the widget

    /// The widget's own mark: the yes/no goal is done with its chain one longer, the day's open
    /// goals come first, the next day's open entry takes the new chain; nothing else changes.
    @Test func markingShowsTheGoalDoneAndCarriesTheChainToTomorrow() throws {
        var esneme = Self.goal("esneme", pending: true)
        esneme.chainDays = 2
        let okuma = Self.goal("okuma", pending: true, kind: .number)
        let today = WidgetSnapshot.Day(date: "2026-09-20", goals: [esneme, okuma])
        let tomorrow = WidgetSnapshot.Day(date: "2026-09-21", goals: [esneme, okuma])
        let snapshot = WidgetSnapshot(
            writtenAt: Self.noon, vaultID: "v", days: [today, tomorrow], vaultKind: .icloud,
            cloudRelativePath: "Documents/Kenet")
        let later = Self.noon.addingTimeInterval(60)

        let marked = try #require(snapshot.marking(key: "esneme", on: "2026-09-20", at: later))
        var done = esneme
        done.isPending = false
        done.value = 1
        done.streak = 4
        var next = esneme
        next.streak = 4
        #expect(marked.days[0].goals == [okuma, done])
        #expect(marked.days[1].goals == [next, okuma])
        #expect(marked.markedAt == later)
        #expect(marked.writtenAt == Self.noon)
        #expect(marked.vaultID == "v")
        // Only an open yes/no goal of a stored day is marked.
        #expect(snapshot.marking(key: "okuma", on: "2026-09-20", at: later) == nil)
        #expect(marked.marking(key: "esneme", on: "2026-09-20", at: later) == nil)
        #expect(snapshot.marking(key: "esneme", on: "2026-09-22", at: later) == nil)
        #expect(snapshot.marking(key: "yok", on: "2026-09-20", at: later) == nil)
        // The mark is no content of its own: the app's equal answer leaves the widget alone.
        var answered = marked
        answered.markedAt = nil
        #expect(answered.hasSameContent(as: marked))
        var moved = answered
        moved.cloudRelativePath = nil
        #expect(!moved.hasSameContent(as: answered))
        var replaced = answered
        replaced.cloudVaultIdentity = "3:4"
        #expect(!replaced.hasSameContent(as: answered))
        var leaving = answered
        leaving.lockedAfter = later
        #expect(!leaving.hasSameContent(as: answered))
    }

    /// A chain reaching a multiple of 7 earns a chain day, at most 3, as the app counts it
    /// (decision 67): the widget's mark shows it at once, today and tomorrow.
    @Test func markingOnTheSeventhDayEarnsAChainDay() throws {
        func marked(streak: Int, chainDays: Int) throws -> (today: WidgetSnapshot.Goal, tomorrow: WidgetSnapshot.Goal) {
            var esneme = Self.goal("esneme", pending: true)
            esneme.streak = streak
            esneme.chainDays = chainDays
            let snapshot = WidgetSnapshot(
                writtenAt: Self.noon, vaultID: "v",
                days: [.init(date: "2026-09-20", goals: [esneme]), .init(date: "2026-09-21", goals: [esneme])])
            let result = try #require(snapshot.marking(key: "esneme", on: "2026-09-20", at: Self.noon))
            return (try #require(result.days[0].goals.first), try #require(result.days[1].goals.first))
        }
        let seventh = try marked(streak: 6, chainDays: 1)
        #expect(seventh.today.streak == 7)
        #expect(seventh.today.chainDays == 2)
        #expect(seventh.tomorrow.streak == 7)
        #expect(seventh.tomorrow.chainDays == 2)
        #expect(try marked(streak: 13, chainDays: 3).today.chainDays == 3)
        #expect(try marked(streak: 7, chainDays: 1).today.chainDays == 1)
    }

    /// Only an iCloud vault with a known place is marked in the widget; every other vault's tap
    /// opens the app as before.
    @Test func onlyAnICloudVaultIsMarkedInTheWidget() {
        let open = Self.goal("esneme", pending: true)
        let day = WidgetSnapshot.Day(date: "2026-09-20", goals: [open])
        let id = WidgetSnapshot.intentID(vaultID: "v", key: "esneme")
        func snapshot(_ kind: WidgetSnapshot.VaultKind?, _ path: String?, identity: String? = "1:2") -> WidgetSnapshot {
            WidgetSnapshot(
                writtenAt: Self.noon, vaultID: "v", days: [day], vaultKind: kind, cloudRelativePath: path,
                cloudVaultIdentity: identity)
        }
        #expect(snapshot(.icloud, "Documents/Kenet").tap(for: open) == .markInWidget(goalID: id))
        // The app could not name the vault folder on this device: the app marks.
        #expect(snapshot(.icloud, "Documents/Kenet", identity: nil).tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.icloud, nil).tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.icloud, "").tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.local, nil).tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.local, "Documents/Kenet").tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.selected, "Documents/Kenet").tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(.selected, nil).tap(for: open) == .open(.markGoal(id: id)))
        #expect(snapshot(nil, nil).tap(for: open) == .open(.markGoal(id: id)))
        let cloud = snapshot(.icloud, "Documents/Kenet")
        #expect(cloud.tap(for: Self.goal("esneme", pending: false)) == .open(.today))
        #expect(cloud.tap(for: Self.goal("su", pending: true, kind: .number)) == .open(.today))
    }

    /// A snapshot written before the vault's place was kept still reads; its taps open the app.
    @Test func snapshotWithoutTheVaultPlaceStillReads() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = WidgetSnapshotFile.url(in: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"days":[],"format":1,"vaultID":"v","writtenAt":"2026-09-20T09:00:00Z"}"#.utf8).write(to: url)
        let snapshot = try #require(WidgetSnapshotFile.read(from: url))
        #expect(snapshot.vaultKind == nil)
        #expect(snapshot.cloudRelativePath == nil)
        #expect(snapshot.markedAt == nil)
        #expect(!snapshot.widgetCanMark)
    }

    // MARK: - Links

    @Test func linksRoundTripAndOnlyAnOpenYesNoGoalMarks() throws {
        let mark = WidgetLink.markGoal(id: "abc:esneme")
        #expect(WidgetLink(url: mark.url) == mark)
        #expect(WidgetLink(url: WidgetLink.today.url) == .today)
        #expect(WidgetLink(url: try #require(URL(string: "https://example.com/mark?goal=x"))) == nil)
        #expect(WidgetLink(url: try #require(URL(string: "kenet-widget://mark"))) == nil)
        #expect(WidgetLink(url: try #require(URL(string: "kenet-widget://mark?goal"))) == nil)

        #expect(WidgetSnapshot.link(for: Self.goal("esneme", pending: true), vaultID: "abc") == mark)
        #expect(WidgetSnapshot.link(for: Self.goal("esneme", pending: false), vaultID: "abc") == .today)
        #expect(WidgetSnapshot.link(for: Self.goal("su", pending: true, kind: .number), vaultID: "abc") == .today)
    }

    /// A tap on an open yes/no goal opens Today and marks it through the App Intent path; a tap
    /// while the app is locked marks once it unlocks.
    @Test func widgetTapMarksThroughTheIntentPath() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        let snapshot = try #require(harness.snapshot)
        let goal = try #require(snapshot.days[0].goals.first { $0.key == "esneme" })
        let url = WidgetSnapshot.link(for: goal, vaultID: snapshot.vaultID).url

        let lock = harness.lock
        lock.isLocked = true
        let actions = IntentActions(
            store: harness.context.store, now: { WidgetSnapshotTests.noon }, permitsStart: { true },
            isLocked: { lock.isLocked })
        let navigation = IntentNavigation()
        let handler = WidgetLinkHandler(actions: actions, navigation: navigation)
        let day = harness.context.root.appendingPathComponent("journal/\(GraceDayVault.today).md")

        #expect(await handler.open(url))
        #expect(navigation.todayRequest != nil)
        #expect(handler.pendingMark != nil)
        #expect(!String(decoding: try Data(contentsOf: day), as: UTF8.self).contains("esneme"))

        lock.isLocked = false
        await handler.unlocked()
        #expect(handler.pendingMark == nil)
        #expect(String(decoding: try Data(contentsOf: day), as: UTF8.self).contains("goals:\n  esneme: true\n"))
        await harness.writer.settle()
        #expect(harness.snapshot?.days[0].goals.last?.key == "esneme")
        #expect(harness.snapshot?.days[0].goals.last?.isPending == false)

        #expect(!(await handler.open(try #require(URL(string: "https://example.com")))))
    }

    /// A mark link with an empty goal is no widget link: nothing opens, nothing is written.
    @Test func emptyGoalLinkMarksNothing() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.start()
        let url = try #require(URL(string: "kenet-widget://mark?goal="))
        #expect(WidgetLink(url: url) == nil)

        let day = harness.context.root.appendingPathComponent("journal/\(GraceDayVault.today).md")
        let before = try Data(contentsOf: day)
        let actions = IntentActions(
            store: harness.context.store, now: { WidgetSnapshotTests.noon }, permitsStart: { true },
            isLocked: { false })
        let navigation = IntentNavigation()
        let handler = WidgetLinkHandler(actions: actions, navigation: navigation)
        #expect(!(await handler.open(url)))
        #expect(handler.pendingMark == nil)
        #expect(navigation.todayRequest == nil)
        #expect(try Data(contentsOf: day) == before)
    }
}
