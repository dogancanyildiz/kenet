import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// The watcher reports changed directories, and the store rescans only those.
@Suite(.serialized)
struct DirectoryWatcherTests {
    @Test func eventsReportOnlyTheChangedDirectoriesInOneDebouncedChange() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b", "c"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let changes = ChangeLog()
        let watcher = VaultWatcher(root: root, interval: 60) { change in Task { await changes.append(change) } }
        defer { watcher.stop() }
        await watcher.waitUntilReady()

        // Both events wait on the held queue, then reach the debounce back to back.
        watcher.testingSuspendEvents()
        try Data("a".utf8).write(to: root.appendingPathComponent("a/one.md"))
        try Data("b".utf8).write(to: root.appendingPathComponent("b/two.md"))
        watcher.testingResumeEvents()
        try await changes.wait(for: 1)
        #expect(await changes.all == [.directories(["a", "b"])])

        // A new subdirectory gains its own source without a whole-tree walk.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a/new"), withIntermediateDirectories: true)
        try await changes.wait(for: 2)
        try Data("nested".utf8).write(to: root.appendingPathComponent("a/new/three.md"))
        try await changes.wait(for: 3)
        #expect(await changes.all.last == .directories(["a/new"]))

        // A hidden subdirectory stays unwatched.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("c/.cache"), withIntermediateDirectories: true)
        try await changes.wait(for: 4)
        #expect(await changes.all.last == .directories(["c"]))
        try Data("hidden".utf8).write(to: root.appendingPathComponent("c/.cache/four.md"))
        // Negative check: a source would report within two debounces of the clock watcher.
        let clock = try WatcherClock()
        defer { clock.stop() }
        await clock.waitDebounces()
        #expect(await changes.all.count == 4)
    }

    @Test func removedSubtreeLeavesNoUnwatchedDirectoryBehind() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        // Both logs record on the watcher queue, coverage before the change it belongs to.
        let coverage = LockedLog<Int>()
        let changes = LockedLog<VaultChange>()
        let watcher = VaultWatcher(
            root: root, interval: 60, onCoverageChange: { coverage.append($0) },
            onChange: { changes.append($0) })
        defer { watcher.stop() }
        await watcher.waitUntilReady()

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a/sub/deep"), withIntermediateDirectories: true)
        try await changes.wait(for: 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("a/sub"))
        try await changes.wait(for: 2)
        // A pruned walk forgets the removed subtree; otherwise it counts as unwatched forever.
        #expect(coverage.all == [0])
        #expect(!changes.all.contains(.full))
    }

    @Test func rootChangesAndTooManyDirectoriesAskForAFullScan() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b", "c"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let changes = ChangeLog()
        let watcher = VaultWatcher(root: root, interval: 60, fullScanThreshold: 2) { change in
            Task { await changes.append(change) }
        }
        defer { watcher.stop() }
        await watcher.waitUntilReady()

        watcher.testingSuspendEvents()
        for name in ["a", "b", "c"] {
            try Data(name.utf8).write(to: root.appendingPathComponent("\(name)/note.md"))
        }
        watcher.testingResumeEvents()
        try await changes.wait(for: 1)
        #expect(await changes.all == [.full])

        try Data("top".utf8).write(to: root.appendingPathComponent("top.md"))
        try await changes.wait(for: 2)
        #expect(await changes.all == [.full, .full])

        let names = (0...VaultChange.fullScanThreshold).map { "d\($0)" }
        let within = VaultChange.directories(Set(names.dropLast()))
        #expect(within.merging(.directories([])) == within)
        #expect(within.merging(.directories([names.last!])) == .full)
        #expect(VaultChange.directories(["x"]).merging(.full) == .full)
    }
}

@MainActor
struct DirectoryRefreshTests {
    /// Skipped paths of a notified directory are matched as the index matches its scope: by the
    /// vault's name key, so `people/IŞIK` holds `people/Işık/a.md`.
    @Test func notifiedDirectoryHoldsPathsByTheNameKey() {
        #expect(pathIsInside("people/Işık/a.md", ["people/IŞIK"]))
        #expect(pathIsInside("İSTANBUL/x.md", ["istanbul"]))
        #expect(!pathIsInside("people/işık/a.md", ["people/IŞIK"]))
        #expect(pathIsInside("people/x.md", [""]))
        #expect(!pathIsInside("peoplex/a.md", ["people"]))
    }

    @Test func directoryEventRescansOnlyThatDirectory() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        try write("- [ ] Seed task\n", to: root.appendingPathComponent("notes/seed.md"))
        try write("- [ ] Other task\n", to: root.appendingPathComponent("projects/other.md"))
        let suite = try TestDefaults()
        defer { suite.clean() }
        let scopes = ScopeLog()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), scopedUpdate: scopes.recordingUpdate())
        await store.start()
        #expect(store.counts.tasks == 2)
        #expect(await scopes.all == [nil])

        // An in-place edit reaches no directory source; only the full scan would see it.
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("projects/other.md"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] Unseen edit\n".utf8))
        try handle.close()
        try write("- [ ] Fresh task\n", to: root.appendingPathComponent("notes/fresh.md"))
        await waitUntil { store.counts.tasks >= 3 }
        // Counts publish before recognition reloads; a refresh call meanwhile would only queue.
        await store.waitWhileRefreshInFlight()
        #expect(store.counts.tasks == 3)
        #expect(await scopes.all == [nil, ["notes"]])

        await store.refresh()
        #expect(store.counts.tasks == 4)
    }

    @Test func openingWalkLeavesTheMainActorFree() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        let probe = ScanProbe()
        let release = DispatchSemaphore(value: 0)
        store.testingWatcherInitialScan = {
            probe.begin()
            // Bounded: a walk on the main actor would block this test here, not hang it.
            probe.finish(timedOut: release.wait(timeout: .now() + 5) == .timedOut)
        }
        let opening = Task { await store.start() }
        await waitUntil { probe.state.began }
        // This line runs on the main actor; the walk must still be held.
        let heldWhileMainRan = probe.state.began && !probe.state.finished
        release.signal()
        await opening.value
        #expect(heldWhileMainRan)
        #expect(!probe.state.timedOut)
        #expect(store.lastUpdated != nil)
    }

    @Test func openingRefreshWaitsForTheFirstWalk() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let probe = ScanProbe()
        let walkDoneAtUpdate = LockedLog<Bool>()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"),
            scopedUpdate: { index, root, rebuild, directories, previous, skip, skipped, previousContent in
                walkDoneAtUpdate.append(probe.state.finished)
                return try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous, skipUnchanged: skip,
                    previousSkipped: skipped, previousContent: previousContent, directories: directories)
            })
        let release = DispatchSemaphore(value: 0)
        store.testingWatcherInitialScan = {
            probe.begin()
            probe.finish(timedOut: release.wait(timeout: .now() + 5) == .timedOut)
        }
        let opening = Task { await store.start() }
        await waitUntil { probe.state.began }
        // Written before any source exists: only the opening scan can see it.
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        try Data("- [ ] Early task\n".utf8).write(to: root.appendingPathComponent("notes/early.md"))
        // Negative check: an opening refresh that did not wait would start within two debounces.
        let clock = try WatcherClock()
        defer { clock.stop() }
        await clock.waitDebounces()
        release.signal()
        await opening.value
        #expect(walkDoneAtUpdate.all.first == true)
        #expect(store.counts.tasks == 1)
        #expect(!probe.state.timedOut)
    }

    @Test func foregroundFuseRescansTheWholeVaultEveryTenSeconds() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let scopes = ScopeLog()
        let ticker = ManualTicker()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), watcherTicker: ticker,
            scopedUpdate: scopes.recordingUpdate())
        store.setForeground(true)
        await store.start()
        defer { store.setForeground(false) }
        #expect(await scopes.all == [nil])
        await waitUntil { ticker.isScheduled }
        #expect(ticker.isScheduled)

        ticker.advance(by: 9)
        // Negative check: a tick would refresh within two debounces of the clock watcher.
        let clock = try WatcherClock()
        defer { clock.stop() }
        await clock.waitDebounces()
        #expect(await scopes.all == [nil])
        ticker.advance(by: 1)
        try await scopes.wait(for: 2)
        #expect(await scopes.all == [nil, nil])
    }

    @Test func directoryRequestsQueueTogetherAndAFullRequestAbsorbsThem() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = UpdateGate()
        let scopes = ScopeLog()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), scopedUpdate: scopes.recordingUpdate(gate: gate))
        await store.start()

        let tooMany = Set((0...VaultChange.fullScanThreshold).map { "d\($0)" })
        await store.refresh(directories: tooMany)
        await store.refresh(directories: Set(tooMany.sorted().dropLast()))
        #expect(await scopes.all.dropFirst().map { $0?.count } == [nil, VaultChange.fullScanThreshold])

        await gate.arm()
        let firstRefresh = Task { await store.refresh(directories: ["a"]) }
        try await waitForGate(gate)
        await store.refresh(directories: ["b"])
        await store.refresh(directories: ["c"])
        await gate.release()
        await firstRefresh.value
        #expect(await scopes.all.suffix(2) == [["a"], ["b", "c"]])

        await gate.arm()
        let secondRefresh = Task { await store.refresh(directories: ["a"]) }
        try await waitForGate(gate)
        await store.refresh(directories: ["b"])
        await store.refresh()
        await store.refresh(directories: ["c"])
        await gate.release()
        await secondRefresh.value
        #expect(await scopes.all.suffix(2) == [["a"], nil])
    }

    @Test func directoryRefreshKeepsSkippedPathsElsewhereAndDoesNotRepublish() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        try write("- [ ] Real task\n", to: root.appendingPathComponent("notes/real.md"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("projects/link.md"),
            withDestinationURL: root.appendingPathComponent("notes/real.md"))
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let opened = try #require(store.lastUpdated)
        #expect(store.skippedPaths.map(\.path) == ["projects/link.md"])

        await store.refresh(directories: ["notes"])
        #expect(store.skippedPaths.map(\.path) == ["projects/link.md"])
        #expect(store.lastUpdated == opened)

        try FileManager.default.removeItem(at: root.appendingPathComponent("projects/link.md"))
        await store.refresh(directories: ["projects"])
        #expect(store.skippedPaths.isEmpty)
        #expect(store.lastUpdated != opened)
    }

    @Test func failedRefreshMakesTheNextDirectoryRequestAFullScan() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        try write("Notes\n", to: root.appendingPathComponent("projects/missed.md"))
        let scopes = ScopeLog()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), scopedUpdate: scopes.recordingUpdate())
        await store.start()
        #expect(store.counts.tasks == 0)
        // In place: no directory event, so only this test's requests refresh.
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("projects/missed.md"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("- [ ] Missed task\n".utf8))
        try handle.close()

        await scopes.failNext()
        await store.refresh(directories: ["projects"])
        #expect(store.errorText != nil)
        await store.refresh(directories: ["notes"])
        #expect(await scopes.all.suffix(2) == [["projects"], nil])
        #expect(store.counts.tasks == 1)
        #expect(store.errorText == nil)

        await store.refresh(directories: ["notes"])
        #expect(await scopes.all.last == ["notes"])
    }
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

actor ChangeLog {
    private(set) var all: [VaultChange] = []
    func append(_ change: VaultChange) { all.append(change) }

    func wait(for count: Int) async throws {
        if !(await waitUntil { all.count >= count }) {
            Issue.record("Expected \(count) watcher changes, got \(all.count)")
        }
    }
}

/// Records each refresh's directories (`nil` for the whole vault) and runs the real update.
actor ScopeLog {
    enum Failure: Error { case injected }
    private(set) var all: [Set<String>?] = []
    private var failing = false

    func failNext() { failing = true }

    func record(_ scope: Set<String>?) throws {
        all.append(scope)
        if failing {
            failing = false
            throw Failure.injected
        }
    }

    func wait(for count: Int) async throws {
        if !(await waitUntil { all.count >= count }) {
            Issue.record("Expected \(count) refreshes, got \(all.count)")
        }
    }

    nonisolated func recordingUpdate(gate: UpdateGate? = nil)
        -> @Sendable (
            VaultIndex, URL, Bool, Set<String>?, EntityTypeCatalog, Bool, [SkippedPath], VaultReadModel
        ) async throws -> IndexUpdate
    {
        { index, root, rebuild, directories, previous, skip, skipped, previousContent in
            try await self.record(directories)
            await gate?.hold()
            return try await IndexUpdate.read(
                index: index, root: root, rebuild: rebuild, previousTypes: previous, skipUnchanged: skip,
                previousSkipped: skipped, previousContent: previousContent, directories: directories)
        }
    }
}

/// Records from any thread; readers see every append made before they look.
final class LockedLog<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [Element] = []
    var all: [Element] { lock.withLock { elements } }
    func append(_ element: Element) { lock.withLock { elements.append(element) } }

    func wait(for count: Int) async throws {
        if !(await waitUntil { all.count >= count }) {
            Issue.record("Expected \(count) records, got \(all.count)")
        }
    }
}

final class ScanProbe: @unchecked Sendable {
    struct State {
        var began = false
        var finished = false
        var timedOut = false
    }
    private let lock = NSLock()
    private var current = State()
    var state: State { lock.withLock { current } }
    func begin() { lock.withLock { current.began = true } }
    func finish(timedOut: Bool) {
        lock.withLock {
            current.finished = true
            current.timedOut = timedOut
        }
    }
}

/// A clock the test moves by hand; ticks run on the watcher queue as a timer's would.
final class ManualTicker: WatcherTicker, @unchecked Sendable {
    private struct Entry {
        let id: UUID
        let interval: TimeInterval
        var elapsed: TimeInterval
        let queue: DispatchQueue
        let tick: @Sendable () -> Void
    }
    private let lock = NSLock()
    private var entries: [Entry] = []

    var isScheduled: Bool { lock.withLock { !entries.isEmpty } }

    func schedule(
        every interval: TimeInterval, on queue: DispatchQueue, _ tick: @escaping @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let id = UUID()
        lock.withLock { entries.append(Entry(id: id, interval: interval, elapsed: 0, queue: queue, tick: tick)) }
        return { [weak self] in self?.lock.withLock { self?.entries.removeAll { $0.id == id } } }
    }

    func advance(by seconds: TimeInterval) {
        let due: [Entry] = lock.withLock {
            var fired: [Entry] = []
            for position in entries.indices {
                entries[position].elapsed += seconds
                while entries[position].elapsed >= entries[position].interval {
                    entries[position].elapsed -= entries[position].interval
                    fired.append(entries[position])
                }
            }
            return fired
        }
        for entry in due { entry.queue.async(execute: entry.tick) }
    }
}
