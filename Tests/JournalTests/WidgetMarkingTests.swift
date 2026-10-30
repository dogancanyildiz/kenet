import AppIntents
import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

/// An iCloud vault as the app and its widget see it, with no iCloud: the container is a temporary
/// folder (`FakeUbiquityContainer`), the App Group another. `GraceDayVault` sits where the app
/// keeps an iCloud vault (`Documents/Kenet`); on 20 September "Esneme" (yes/no) is open with a
/// 64-day chain and 2 chain days.
@MainActor struct CloudWidgetHarness {
    let directory: URL
    let defaults: TestDefaults
    let container: URL
    let root: URL
    let group: URL
    let store: IndexStore
    let timelines = FakeWidgetTimelines()
    let lock = WidgetSnapshotTests.Lock()
    let clock = WidgetSnapshotTests.Clock()
    let writer: WidgetSnapshotWriter

    init() throws {
        directory = try testDirectory()
        defaults = try TestDefaults()
        container = directory.appendingPathComponent("Cloud", isDirectory: true)
        root = container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        group = directory.appendingPathComponent("group", isDirectory: true)
        try GraceDayVault.generate(at: root)
        defaults.defaults.set(VaultLocation.Kind.icloud.rawValue, forKey: VaultLocation.kindKey)
        let location = VaultLocation(
            defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks(),
            ubiquity: FakeUbiquityContainer(url: container))
        store = IndexStore(location: location, supportURL: directory.appendingPathComponent("indexes"))
        let lock = lock
        let clock = clock
        writer = WidgetSnapshotWriter(
            store: store, group: FolderAppGroupStore(containerURL: group), timelines: timelines,
            isLocked: { lock.isLocked }, lockDeadline: { lock.locksAt }, now: { clock.now })
        writer.attach()
    }

    func start() async {
        await store.start()
        await writer.settle()
    }

    func clean() {
        store.setForeground(false)
        try? FileManager.default.removeItem(at: directory)
        defaults.clean()
    }

    var snapshotFile: URL { WidgetSnapshotFile.url(in: group) }
    var snapshot: WidgetSnapshot? { WidgetSnapshotFile.read(from: snapshotFile) }
    var dayFile: URL { root.appendingPathComponent("journal/\(GraceDayVault.today).md") }

    /// The widget's side, as `MarkGoalInWidgetIntent` builds it, at the test's clock.
    func marker(container: URL?? = nil) -> WidgetGoalMarker {
        let cloud = container ?? self.container
        let now = clock.now
        return WidgetGoalMarker(groupContainer: group, ubiquityContainer: { cloud }, now: { now })
    }

    func goalID(_ key: String) throws -> String {
        let snapshot = try #require(snapshot)
        return WidgetSnapshot.intentID(vaultID: snapshot.vaultID, key: key)
    }

    /// The days the app would write now: the goal query for today and tomorrow.
    func indexDays() async throws -> [WidgetSnapshot.Day] {
        let today = LocalDay.today(at: clock.now)
        let tomorrow = try #require(today.addingDays(1))
        var days: [WidgetSnapshot.Day] = [
            .init(date: today, rows: try await store.computeGoalStatuses(today: today)),
            .init(date: tomorrow, rows: try await store.computeGoalStatuses(today: tomorrow)),
        ]
        let counts = try await store.computeNotificationDays(from: today, through: tomorrow)
        days[0].openTaskCount = counts.openTaskCounts[today, default: 0]
        days[1].openTaskCount = counts.openTaskCounts[tomorrow, default: 0]
        return days
    }
}

/// The widget marks an iCloud vault's open yes/no goal in its own process
/// (docs/architecture.md "Widget'lar"): Core's writer changes the day file's `goals:` entry under
/// file coordination, and the snapshot shows the mark at once. A local vault's tap still opens
/// the app.
@MainActor @Suite("Widget marking")
struct WidgetMarkingTests {
    /// The day file of `GraceDayVault.today` as generated, and with "Esneme" marked.
    static let unmarkedDay = "---\ntype: journal\ndate: 2026-09-20\n---\n\n## Events\n- 08:30 Sabah yürüyüşü ^gr4c01\n"
    static let markedDay =
        "---\ntype: journal\ndate: 2026-09-20\ngoals:\n  esneme: true\n---\n\n## Events\n- 08:30 Sabah yürüyüşü ^gr4c01\n"

    @Test func cloudSnapshotNamesTheVaultPlaceAndTheWidgetMarksItsOpenYesNoGoal() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()

        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.vaultKind == .icloud)
        #expect(snapshot.cloudRelativePath == "Documents/Kenet")
        #expect(snapshot.markedAt == nil)
        let esneme = try #require(snapshot.days[0].goals.first { $0.key == "esneme" })
        let okuma = try #require(snapshot.days[0].goals.first { $0.key == "okuma" })
        #expect(snapshot.tap(for: esneme) == .markInWidget(goalID: try harness.goalID("esneme")))
        // A number goal's amount is entered in the app.
        #expect(snapshot.tap(for: okuma) == .open(.today))
        // The vault folder the app saw on this device; without it the tap is the app's.
        #expect(snapshot.cloudVaultIdentity != nil)
        #expect(snapshot.cloudVaultIdentity == WidgetSnapshot.cloudVaultIdentity(at: harness.root))
        var unnamed = snapshot
        unnamed.cloudVaultIdentity = nil
        #expect(unnamed.tap(for: esneme) == .open(.markGoal(id: try harness.goalID("esneme"))))
    }

    /// Another vault where the app's was (another account's container, a folder put there in
    /// Files): the widget writes nothing into it, though it has the same place and settings file.
    @Test func anotherVaultAtTheSamePlaceIsLeftAlone() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        let snapshot = try Data(contentsOf: harness.snapshotFile)
        let other = harness.directory.appendingPathComponent("OtherCloud", isDirectory: true)
        let root = other.appendingPathComponent("Documents/Kenet", isDirectory: true)
        try GraceDayVault.generate(at: root)
        let day = root.appendingPathComponent("journal/\(GraceDayVault.today).md")
        let before = try Data(contentsOf: day)

        #expect(await harness.marker(container: .some(other)).mark(goalID: id) == .unavailable)
        #expect(try Data(contentsOf: day) == before)
        #expect(try Data(contentsOf: harness.snapshotFile) == snapshot)

        // The app's own vault, its settings file put back by another vault's: also left alone.
        let settings = harness.root.appendingPathComponent(".app/vault.json")
        let bytes = try Data(contentsOf: settings)
        try FileManager.default.removeItem(at: settings)
        try bytes.write(to: settings)
        #expect(await harness.marker().mark(goalID: id) == .unavailable)
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
    }

    /// No events today yet, so no day file (and no placeholder): the widget creates it as the
    /// app would, with the goal's entry alone.
    @Test func missingDayFileIsCreated() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        try FileManager.default.removeItem(at: harness.dayFile)

        #expect(await harness.marker().mark(goalID: id) == .marked)
        #expect(
            try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self)
                == "---\ntype: journal\ndate: 2026-09-20\ngoals:\n  esneme: true\n---\n")
        #expect(harness.snapshot?.markedAt == WidgetSnapshotTests.noon)
    }

    /// After midnight, with no app to write a new snapshot, the widget shows the "tomorrow"
    /// entry: a tap there writes tomorrow's day file, the day of the device clock, and leaves
    /// yesterday's alone.
    @Test func afterMidnightTheTomorrowEntryIsWrittenToTomorrowsFile() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        harness.clock.now = WidgetSnapshotTests.noon.addingTimeInterval(24 * 3600)
        let tomorrow = harness.root.appendingPathComponent("journal/2026-09-21.md")
        #expect(!FileManager.default.fileExists(atPath: tomorrow.path))

        #expect(await harness.marker().mark(goalID: id) == .marked)
        #expect(
            try String(decoding: Data(contentsOf: tomorrow), as: UTF8.self)
                == "---\ntype: journal\ndate: 2026-09-21\ngoals:\n  esneme: true\n---\n")
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.days[0].goals.first { $0.key == "esneme" }?.isPending == true)
        #expect(snapshot.days[1].goals.first { $0.key == "esneme" }?.isPending == false)
    }

    /// The app left with a delayed lock (5 minutes): the snapshot keeps its days and learns when
    /// the lock engages. Until then a tap marks, as the app's own intents would; from then on the
    /// widget shows "open Kenet" and writes nothing. Back in the foreground, unlocked, the app
    /// leaves the moment out again.
    @Test func delayedLockStopsTheWidgetOnceItRunsOut() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        let reloads = harness.timelines.reloads.count
        let unlocked = try Data(contentsOf: harness.snapshotFile)
        let before = try #require(harness.snapshot)

        // No lock: leaving changes nothing.
        harness.writer.lockDeferred()
        #expect(try Data(contentsOf: harness.snapshotFile) == unlocked)

        let deadline = WidgetSnapshotTests.noon.addingTimeInterval(300)
        harness.lock.locksAt = deadline
        harness.writer.lockDeferred()
        let left = try #require(harness.snapshot)
        #expect(left.lockedAfter == deadline)
        #expect(left.days == before.days)
        #expect(harness.timelines.reloads.count == reloads + WidgetKinds.all.count)
        #expect(
            left.timeline(from: WidgetSnapshotTests.noon, calendar: WidgetDay.deviceCalendar).map(\.date) == [
                WidgetSnapshotTests.noon, deadline,
            ])
        #expect(left.timeline(from: deadline, calendar: WidgetDay.deviceCalendar).map(\.day) == [nil])

        // A publish in the background, before the lock engages, keeps the moment.
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot?.lockedAfter == deadline)

        // Six minutes later the app counts as locked: nothing is written.
        harness.clock.now = WidgetSnapshotTests.noon.addingTimeInterval(360)
        let locked = try Data(contentsOf: harness.snapshotFile)
        #expect(await harness.marker().mark(goalID: id) == .nothingToMark)
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
        #expect(try Data(contentsOf: harness.snapshotFile) == locked)

        // Within the delay a tap still marks, and the moment stays.
        harness.clock.now = WidgetSnapshotTests.noon.addingTimeInterval(60)
        #expect(await harness.marker().mark(goalID: id) == .marked)
        #expect(harness.snapshot?.lockedAfter == deadline)

        // Foreground, unlocked: the next write leaves the moment out.
        harness.lock.locksAt = nil
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot?.lockedAfter == nil)
    }

    /// The lock service names the moment only while a delayed lock waits in the background.
    @Test func lockServiceNamesTheMomentOnlyWhileADelayedLockWaits() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        let lock = fixture.lock()
        await lock.becomeActive()
        lock.resignActive(startTimeout: true)
        #expect(lock.locksAt == nil)

        await lock.becomeActive()
        await lock.setEnabled(true)
        lock.delay = .fiveMinutes
        #expect(lock.locksAt == nil)
        // Inactive starts no timeout, but names the moment in case no background phase follows.
        lock.resignActive(startTimeout: false)
        #expect(lock.locksAt == fixture.time.addingTimeInterval(300))
        fixture.time = fixture.time.addingTimeInterval(20)
        lock.resignActive(startTimeout: true)
        #expect(lock.locksAt == fixture.time.addingTimeInterval(300))
        await lock.becomeActive()
        #expect(lock.locksAt == nil)

        lock.delay = .immediately
        lock.resignActive(startTimeout: true)
        #expect(lock.isLocked)
        #expect(lock.locksAt == nil)
    }

    /// `JournalApp` hands every scene phase that leaves the foreground to the writer
    /// (`sceneLeftForeground`), with the real lock service. Lock off: the file stays as it is.
    /// Delayed lock: inactive already writes the moment, the foreground leaves it out again, the
    /// background writes the moment the delay runs out. Only the background reloads the widget:
    /// inactive and the foreground write without a reload (WidgetKit's daily budget).
    /// "Immediately": the lock engages on leaving and the file goes.
    @Test func leavingTheSceneTellsTheWidgetWhenTheLockEngages() async throws {
        let harness = try AppLockWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let unlocked = try Data(contentsOf: harness.file)
        let before = try #require(harness.snapshot)
        let reloads = harness.timelines.reloads.count

        harness.writer.sceneLeftForeground(lockService: harness.lock, background: false)
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: true)
        #expect(try Data(contentsOf: harness.file) == unlocked)
        #expect(harness.timelines.reloads.count == reloads)

        await harness.lock.becomeActive()
        await harness.lock.setEnabled(true)
        harness.lock.delay = .fiveMinutes
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: false)
        #expect(harness.snapshot?.lockedAfter == WidgetSnapshotTests.noon.addingTimeInterval(300))
        #expect(harness.snapshot?.days == before.days)
        #expect(harness.timelines.reloads.count == reloads)

        await harness.foreground()
        #expect(harness.snapshot?.lockedAfter == nil)
        #expect(harness.timelines.reloads.count == reloads)

        harness.fixture.time = harness.fixture.time.addingTimeInterval(60)
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: false)
        #expect(harness.timelines.reloads.count == reloads)
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: true)
        #expect(!harness.lock.isLocked)
        #expect(harness.snapshot?.lockedAfter == WidgetSnapshotTests.noon.addingTimeInterval(360))
        #expect(harness.snapshot?.days == before.days)
        #expect(harness.timelines.reloads.count == reloads + WidgetKinds.all.count)

        await harness.foreground()
        #expect(harness.snapshot?.lockedAfter == nil)
        #expect(harness.timelines.reloads.count == reloads + WidgetKinds.all.count)
        harness.lock.delay = .immediately
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: false)
        // Inactive does not lock; with no delay the moment is now.
        #expect(!harness.lock.isLocked)
        #expect(harness.snapshot?.lockedAfter == WidgetSnapshotTests.noon.addingTimeInterval(60))
        #expect(harness.timelines.reloads.count == reloads + WidgetKinds.all.count)
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: true)
        #expect(harness.lock.isLocked)
        #expect(!FileManager.default.fileExists(atPath: harness.file.path))
        #expect(harness.timelines.reloads.count == reloads + 2 * WidgetKinds.all.count)
    }

    /// The snapshot keeps whole seconds, the lock service's clock does not: the moment is
    /// rounded down, so the file reads back the same moment and a publish in the background
    /// before the lock engages neither rewrites the file nor redraws the widget. Inactive writes
    /// the moment without a reload; the background, finding the same moment, reloads once.
    @Test func lockMomentInWholeSecondsKeepsBackgroundPublishesQuiet() async throws {
        let harness = try AppLockWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        await harness.lock.setEnabled(true)
        harness.lock.delay = .fiveMinutes
        let before = harness.timelines.reloads.count

        harness.writer.sceneLeftForeground(lockService: harness.lock, background: false)
        #expect(harness.snapshot?.lockedAfter == WidgetSnapshotTests.noon.addingTimeInterval(300))
        #expect(harness.timelines.reloads.count == before)
        harness.writer.sceneLeftForeground(lockService: harness.lock, background: true)
        let deadline = try #require(harness.lock.locksAt)
        #expect(deadline == WidgetSnapshotTests.noon.addingTimeInterval(300))
        #expect(harness.snapshot?.lockedAfter == deadline)
        #expect(harness.timelines.reloads.count == before + WidgetKinds.all.count)
        let written = try Data(contentsOf: harness.file)
        let reloads = harness.timelines.reloads.count

        harness.fixture.time = harness.fixture.time.addingTimeInterval(10)
        harness.writer.update()
        await harness.writer.settle()
        #expect(!harness.lock.isLockedNow())
        #expect(try Data(contentsOf: harness.file) == written)
        #expect(harness.timelines.reloads.count == reloads)
    }

    /// A local vault lives in the app's sandbox: its snapshot names no cloud path, a tap opens
    /// the app, and the widget's marker refuses to write it.
    @Test func localVaultTapOpensTheAppAndTheWidgetWritesNothing() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()

        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.vaultKind == .local)
        #expect(snapshot.cloudRelativePath == nil)
        let esneme = try #require(snapshot.days[0].goals.first { $0.key == "esneme" })
        let id = WidgetSnapshot.intentID(vaultID: snapshot.vaultID, key: "esneme")
        #expect(snapshot.tap(for: esneme) == .open(.markGoal(id: id)))

        let before = try Data(contentsOf: harness.file)
        let day = harness.context.root.appendingPathComponent("journal/\(GraceDayVault.today).md")
        let dayBefore = try Data(contentsOf: day)
        // Even handed the vault's own folder as a container, the marker leaves a local vault alone.
        let marker = WidgetGoalMarker(
            groupContainer: harness.container, ubiquityContainer: { [root = harness.context.root] in root },
            now: { WidgetSnapshotTests.noon })
        #expect(await marker.mark(goalID: id) == .needsApp)
        #expect(try Data(contentsOf: day) == dayBefore)
        #expect(try Data(contentsOf: harness.file) == before)
    }

    /// The tap writes only the goal's entry into the day file and shows the mark at once: done,
    /// the chain one longer, open goals first; tomorrow's open entry takes the new chain.
    @Test func markingWritesTheGoalEntryAndShowsTheMarkAtOnce() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
        let before = try #require(harness.snapshot)

        #expect(await harness.marker().mark(goalID: try harness.goalID("esneme")) == .marked)

        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.markedDay)
        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.markedAt == WidgetSnapshotTests.noon)
        let today = snapshot.days[0].goals
        #expect(today.map(\.key) == ["okuma", "esneme"])
        #expect(today.map(\.isPending) == [true, false])
        #expect(today[1].value == 1)
        #expect(today[1].streak == GraceDayVault.streak + 1)
        #expect(today[1].chainDays == GraceDayVault.balance)
        #expect(today[0] == before.days[0].goals.first { $0.key == "okuma" })
        let tomorrow = try #require(snapshot.days[1].goals.first { $0.key == "esneme" })
        #expect(tomorrow.isPending)
        #expect(tomorrow.streak == GraceDayVault.streak + 1)
        // The widget asked WidgetKit nothing through the app's writer.
        #expect(harness.timelines.reloads.count == WidgetKinds.all.count)
    }

    /// The app writes the same day while the widget marks: whichever holds the day file first,
    /// the other waits for it and changes the new bytes. Both changes stay, nothing else moves.
    @Test func appWritingTheSameDayAndTheWidgetMarkingBothStay() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        let original = RawDocument(bytes: try Data(contentsOf: harness.dayFile))
        let event: @Sendable (Data) throws -> Data = { bytes in
            Data(try RawDocument(bytes: bytes).addingEvent(text: "Öğle yemeği", id: "w2ev01").serialized())
        }

        // The app's write, as its VaultStore makes it from another process: a coordinated
        // read-change-write it holds until the widget's write is done, or for at most 3 seconds.
        let app = HeldCoordinatedWrite(url: harness.dayFile, change: event)
        await app.waitUntilHolding()
        let outcome = await harness.marker().mark(goalID: id)
        app.release()
        await app.waitUntilDone()

        #expect(outcome == .marked)
        let expected = try original.addingEvent(text: "Öğle yemeği", id: "w2ev01")
            .settingFrontmatterEntry(.boolean(true), forKey: "esneme", inMapping: "goals")
        #expect(try Data(contentsOf: harness.dayFile) == Data(expected.serialized()))
        #expect(app.error == nil)
    }

    /// iCloud off or signed out: no container, nothing written, the snapshot as it was.
    @Test func noICloudContainerChangesNothing() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let snapshot = try Data(contentsOf: harness.snapshotFile)

        #expect(await harness.marker(container: .some(nil)).mark(goalID: try harness.goalID("esneme")) == .unavailable)
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
        #expect(try Data(contentsOf: harness.snapshotFile) == snapshot)
    }

    /// The day is in iCloud but not on this device yet: the widget never writes a new day file
    /// over it, and shows nothing it did not write.
    @Test func dayStillDownloadingIsNotOverwritten() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let snapshot = try Data(contentsOf: harness.snapshotFile)
        let id = try harness.goalID("esneme")
        try FileManager.default.removeItem(at: harness.dayFile)
        let placeholder = harness.root.appendingPathComponent("journal/.\(GraceDayVault.today).md.icloud")
        try Data().write(to: placeholder)

        #expect(await harness.marker().mark(goalID: id) == .unavailable)
        #expect(!FileManager.default.fileExists(atPath: harness.dayFile.path))
        #expect(try Data(contentsOf: harness.snapshotFile) == snapshot)
    }

    /// No snapshot (vault unavailable, app locked on leaving), another vault's goal, a number
    /// goal or a done one: the widget writes nothing.
    @Test func onlyAnOpenYesNoGoalOfTheSnapshotsVaultIsMarked() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let marker = harness.marker()
        let snapshot = try Data(contentsOf: harness.snapshotFile)

        #expect(await marker.mark(goalID: try harness.goalID("okuma")) == .nothingToMark)
        #expect(await marker.mark(goalID: WidgetSnapshot.intentID(vaultID: "other", key: "esneme")) == .nothingToMark)
        #expect(await marker.mark(goalID: try harness.goalID("")) == .nothingToMark)
        #expect(try Data(contentsOf: harness.snapshotFile) == snapshot)

        #expect(await marker.mark(goalID: try harness.goalID("esneme")) == .marked)
        let marked = try Data(contentsOf: harness.snapshotFile)
        #expect(await marker.mark(goalID: try harness.goalID("esneme")) == .nothingToMark)
        #expect(try Data(contentsOf: harness.snapshotFile) == marked)

        let id = try harness.goalID("esneme")
        try FileManager.default.removeItem(at: harness.snapshotFile)
        try Data(Self.unmarkedDay.utf8).write(to: harness.dayFile)
        #expect(await marker.mark(goalID: id) == .nothingToMark)
        #expect(try String(decoding: Data(contentsOf: harness.dayFile), as: UTF8.self) == Self.unmarkedDay)
    }

    /// Core's writer updates its index after the write, and an empty index first reads the
    /// whole vault. The widget's throwaway index starts from a stand-in with the vault's entity
    /// types, so that update reads the written day alone (a five-year vault: 0.08 s instead of
    /// 7.5 s, `fiveYearVaultMarkCost`).
    @Test func throwawayIndexReadsOnlyTheWrittenDay() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Kenet", isDirectory: true)
        try GraceDayVault.generate(at: root)
        // Custom entity types: Core rebuilds the whole index when they differ from the index's.
        let types = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/gallery/.app/types.json")
        try FileManager.default.copyItem(at: types, to: root.appendingPathComponent(".app/types.json"))
        let day = "journal/\(GraceDayVault.today).md"

        let reads = ReadLog()
        let index = try WidgetGoalMarker.throwawayIndex(for: root) { url in
            reads.append(url.lastPathComponent)
            return try Data(contentsOf: url)
        }
        reads.clear()
        let result = try index.update(paths: [day], vaultRoot: root)

        #expect(reads.names == ["\(GraceDayVault.today).md"])
        #expect(result.addedPaths == [day])
        #expect(try index.files().map(\.path).contains(day))
    }

    /// A container whose vault has not arrived yet (its settings file still an iCloud
    /// placeholder) gets nothing: no day file written ahead of the vault's own.
    @Test func vaultNotOnThisDeviceYetGetsNothing() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        let id = try harness.goalID("esneme")
        let other = harness.directory.appendingPathComponent("OtherCloud", isDirectory: true)
        let root = other.appendingPathComponent("Documents/Kenet", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".app"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent(".app/.vault.json.icloud"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)

        #expect(await harness.marker(container: .some(other)).mark(goalID: id) == .unavailable)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("journal").path).isEmpty)
    }
}

#if os(iOS)
    /// An open yes/no goal's row in the medium widget looks the same whether its tap opens the app
    /// (a link) or marks the goal in the widget (an App Intent button). The widget is iOS only.
    @MainActor @Suite("Widget mark button")
    struct WidgetMarkButtonTests {
        /// Stands in for the widget's `MarkGoalInWidgetIntent`, which only the widget target builds.
        struct SampleIntent: AppIntent {
            static let title: LocalizedStringResource = "Hedefi işaretle"
            static let isDiscoverable = false
            func perform() async throws -> some IntentResult { .result() }
        }

        /// Drawn side by side, the two differ at most by text rasterized half a pixel apart (the
        /// trailing chain, 0.16 % of the pixels); a row drawn another way differs in whole rows.
        @Test func intentRowLooksLikeTheLinkRow() throws {
            let day = WidgetViewSnapshotSample.day
            func render(intents: Bool) throws -> [UInt8] {
                let view = GoalChainWidgetView(
                    day: day, link: { WidgetSnapshot.link(for: $0, vaultID: "vault").url }, layout: .medium,
                    intent: intents ? { $0.isPending && $0.kind == .boolean ? SampleIntent() : nil } : nil
                )
                .frame(width: 332, height: 138)
                .environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                return try Self.rgba(try #require(renderer.cgImage))
            }
            let link = try render(intents: false)
            let intent = try render(intents: true)
            try #require(link.count == intent.count)
            var differing = 0
            for start in stride(from: 0, to: link.count, by: 4) {
                let channels = (0..<4).map { abs(Int(link[start + $0]) - Int(intent[start + $0])) }
                if channels.max() ?? 0 > 32 { differing += 1 }
            }
            #expect(Double(differing) / Double(link.count / 4) < 0.005, "\(differing) pixels differ")
        }

        /// The image's pixels as RGBA, 8 bits each.
        private static func rgba(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let context = CGContext(
                        data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            try #require(drawn)
            return bytes
        }
    }
#endif

/// Two open goals (a yes/no one, a number one) and a done one, in the order the app writes them.
enum WidgetViewSnapshotSample {
    static let day = WidgetSnapshot.Day(
        date: "2026-09-20",
        goals: WidgetSnapshot.ordered([
            .init(
                key: "esneme", name: "Esneme", kind: .boolean, target: 1, unit: nil, value: 0, isPending: true,
                streak: 64, chainDays: 2),
            .init(
                key: "su", name: "Su", kind: .number, target: 8, unit: "bardak", value: 3, isPending: true,
                streak: 12, chainDays: 0),
            .init(
                key: "okuma", name: "Okuma", kind: .boolean, target: 1, unit: nil, value: 1, isPending: false,
                streak: 5, chainDays: 0),
        ]))
}

/// Another process's write to one file: a coordinated read-change-write (`.forMerging`, as Core's
/// writer asks) on its own thread. It holds the claim until `release()`, or for at most
/// `timeout`, then writes `change` of the bytes it read when the claim began.
final class HeldCoordinatedWrite: @unchecked Sendable {
    private let holding = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private let done = DispatchSemaphore(value: 0)
    private(set) var error: (any Error)?

    init(url: URL, timeout: DispatchTimeInterval = .seconds(3), change: @escaping @Sendable (Data) throws -> Data) {
        Thread.detachNewThread { [self] in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var denied: NSError?
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &denied) { url in
                do {
                    let bytes = try Data(contentsOf: url)
                    holding.signal()
                    _ = released.wait(timeout: .now() + timeout)
                    try change(bytes).write(to: url, options: .atomic)
                } catch {
                    self.error = error
                    holding.signal()
                }
            }
            if let denied { error = denied }
            done.signal()
        }
    }

    func waitUntilHolding() async { await Self.wait(for: holding) }

    func release() { released.signal() }

    func waitUntilDone() async { await Self.wait(for: done) }

    private static func wait(for semaphore: DispatchSemaphore) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                semaphore.wait()
                continuation.resume()
            }
        }
    }
}

/// The writer joined to a real `AppLockService` as `JournalApp` joins them, on `GraceDayVault`
/// in a local vault. The clock starts at noon and 0.68 seconds: the lock service's moments carry
/// a fraction of a second, as `Date()` does.
@MainActor struct AppLockWidgetHarness {
    let context: TaskTestContext
    let group: URL
    let fixture = LockFixture()
    let lock: AppLockService
    let timelines = FakeWidgetTimelines()
    let writer: WidgetSnapshotWriter

    init() throws {
        context = try TaskTestContext()
        try GraceDayVault.generate(at: context.root)
        group = context.directory.appendingPathComponent("group", isDirectory: true)
        let fixture = fixture
        fixture.time = WidgetSnapshotTests.noon.addingTimeInterval(0.68)
        let lock = fixture.lock()
        self.lock = lock
        writer = WidgetSnapshotWriter(
            store: context.store, group: FolderAppGroupStore(containerURL: group), timelines: timelines,
            isLocked: { lock.isLockedNow() }, lockDeadline: { lock.locksAt }, now: { fixture.time })
        writer.attach()
    }

    var file: URL { WidgetSnapshotFile.url(in: group) }
    var snapshot: WidgetSnapshot? { WidgetSnapshotFile.read(from: file) }

    func start() async {
        await context.start()
        await writer.settle()
        await lock.becomeActive()
    }

    /// Back in the foreground, unlocked: the lock service first, then the snapshot (`JournalApp`).
    func foreground() async {
        await lock.becomeActive()
        writer.update()
        await writer.settle()
    }

    func clean() {
        context.clean()
        fixture.clean()
    }
}

/// File names an index read, in order.
final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var names: [String] { lock.withLock { log } }
    func append(_ name: String) { lock.withLock { log.append(name) } }
    func clear() { lock.withLock { log.removeAll() } }
}
