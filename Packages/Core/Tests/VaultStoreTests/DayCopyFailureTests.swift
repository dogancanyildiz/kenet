import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

struct DayCopyFailureTests {
    enum Shape: CaseIterable, Sendable {
        case merged, renamed, identical

        var copy: String {
            switch self {
            case .merged: "journal/2026-10-01 2.md"
            case .renamed: "journal/2026-10-03 2.md"
            case .identical: "journal/2026-10-04 2.md"
            }
        }
    }

    /// Reading both files, saving conflict copies, replacing the day, removing the copy and updating
    /// the index all happen inside one `.move(copy → day)` boundary, with no nested coordination.
    @Test(arguments: Shape.allCases)
    func everyStepRunsInsideOneMoveBoundary(shape: Shape) async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let spy = DayCopySpy(root: vault.root)
        let store = vault.store(
            readFile: { url in
                spy.recordRead(url)
                return try Data(contentsOf: url)
            }, fileCoordination: spy)
        let copyURL = spy.url(shape.copy)
        let dayURL = spy.url(try #require(DayCopyName.dayPath(ofCopy: shape.copy)))
        let before = try vault.tree()
        _ = try await store.mergingDayCopy(shape.copy)
        let operation = FileCoordinationOperation.move(source: copyURL, destination: dayURL)
        var expected: [DayCopySpy.Event] = [.begin(operation)]
        if shape == .renamed { expected += [.willMove(copyURL, dayURL), .didMove(copyURL, dayURL)] }
        expected.append(.end(operation))
        #expect(spy.events == expected)
        #expect(spy.maximumDepth == 1)
        #expect(spy.reads.allSatisfy { $0.active == operation })
        #expect(spy.reads.map(\.url) == (shape == .renamed ? [copyURL] : [copyURL, dayURL]))
        let after = try vault.tree()
        #expect(after != before)
        #expect(spy.changesOutsideBoundary(before: before, after: after).isEmpty)
        #expect(after[shape.copy] == nil)
        try equivalent(vault.index, vault.root)
    }

    @Test(arguments: [DayCopySpy.Failure.denied, .failed])
    func rejectedCoordinationChangesNothing(failure: DayCopySpy.Failure) async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let spy = DayCopySpy(root: vault.root, failure: failure)
        let store = vault.store(fileCoordination: spy)
        let before = try vault.tree()
        let snapshot = try vault.index.snapshot()
        let copy = Shape.merged.copy
        await #expect(throws: failure) { try await store.mergingDayCopy(copy) }
        let operation = FileCoordinationOperation.move(
            source: spy.url(copy), destination: spy.url("journal/2026-10-01.md"))
        #expect(spy.events == [.begin(operation)])
        #expect(try vault.tree() == before)
        #expect(try vault.index.snapshot() == snapshot)
    }

    enum Fault: CaseIterable, Sendable {
        case readCopy, readDay, conflictStep, conflictLink, dayStep, removeUnchangedDay, move
    }

    /// A failure at any step before the day file is replaced leaves the day, the copy, `conflicts/`
    /// (even its absence) and the index exactly as they were, with no temporary file left behind.
    @Test(arguments: Fault.allCases, [false, true])
    func failedStepLeavesBothVersions(fault: Fault, hasConflictsFolder: Bool) async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        if !hasConflictsFolder { try FileManager.default.removeItem(at: vault.url("conflicts")) }
        let copy: String
        switch fault {
        case .removeUnchangedDay: copy = "journal/2026-10-05 2.md"
        case .move: copy = Shape.renamed.copy
        default: copy = Shape.merged.copy
        }
        let store = vault.store(
            linkFile: { source, destination in
                // An existing name makes every candidate taken until the numbering gives up.
                if fault == .conflictLink { throw CocoaError(.fileWriteFileExists) }
                try FileManager.default.linkItem(at: source, to: destination)
            },
            moveFile: { source, destination in
                if fault == .move { throw InjectedFailure.failed }
                try FileManager.default.moveItem(at: source, to: destination)
            },
            readFile: { url in
                if fault == .readDay, url.lastPathComponent == "2026-10-01.md" { throw InjectedFailure.failed }
                if fault == .readCopy, url.lastPathComponent == "2026-10-01 2.md" { throw InjectedFailure.failed }
                return try Data(contentsOf: url)
            },
            removeFile: { url in
                if fault == .removeUnchangedDay { throw InjectedFailure.failed }
                try FileManager.default.removeItem(at: url)
            },
            dayCopyStep: { step in
                switch (fault, step) {
                case (.conflictStep, .conflictCopy), (.dayStep, .dayFile): throw InjectedFailure.failed
                default: break
                }
            })
        let before = try vault.tree()
        let snapshot = try vault.index.snapshot()
        await #expect(throws: (any Error).self) { try await store.mergingDayCopy(copy) }
        #expect(try vault.tree() == before)
        #expect(try vault.index.snapshot() == snapshot)
    }

    /// Removing the copy is the last step. When only it fails, the day file already holds the merge
    /// and the conflict copy is kept; the next call removes the copy without saving anything again.
    @Test func failedCopyRemovalIsCompletedByTheNextMerge() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let copy = Shape.merged.copy
        let dayPath = "journal/2026-10-01.md"
        let merge = ConflictMerge.merge(try vault.version(dayPath), try vault.version(copy))
        let failing = vault.store(removeFile: { _ in throw InjectedFailure.failed })
        await #expect(throws: InjectedFailure.failed) { try await failing.mergingDayCopy(copy) }
        let conflict = "conflicts/2026-10-01 (conflict 20261001T090000Z 2).md"
        #expect(Array(try Data(contentsOf: vault.url(dayPath))) == merge.bytes)
        #expect(Array(try Data(contentsOf: vault.url(conflict))) == merge.preserved.first?.bytes)
        #expect(FileManager.default.fileExists(atPath: vault.url(copy).path))
        try equivalent(vault.index, vault.root)
        try vault.settle(dayPath)
        let partial = try vault.tree()
        let outcome = try await vault.store().mergingDayCopy(copy)
        // The day file now holds everything the copy has: nothing is preserved again.
        #expect(outcome.conflictPaths.isEmpty)
        var expected = partial
        expected.removeValue(forKey: copy)
        #expect(try vault.tree() == expected)
        try equivalent(vault.index, vault.root)
    }

    @Test func placeholdersAwaitDownload() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let copy = Shape.merged.copy
        try FileManager.default.removeItem(at: vault.url(copy))
        try Data("bplist00".utf8).write(to: vault.url("journal/.2026-10-01 2.md.icloud"))
        try Data("bplist00".utf8).write(to: vault.url("journal/.2026-10-03.md.icloud"))
        let store = vault.store()
        let before = try vault.tree()
        await #expect(throws: VaultStoreError.awaitingDownload(path: copy)) { try await store.mergingDayCopy(copy) }
        await #expect(throws: VaultStoreError.awaitingDownload(path: "journal/2026-10-03.md")) {
            try await store.mergingDayCopy(Shape.renamed.copy)
        }
        #expect(try vault.tree() == before)
    }

    @Test func unusableTargetsAreRejected() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let store = vault.store()
        await #expect(throws: VaultStoreError.invalidPath) { try await store.mergingDayCopy("notes/2026-10-02 2.md") }
        await #expect(throws: VaultStoreError.invalidPath) { try await store.mergingDayCopy("journal/2026-10-02.md") }
        await #expect(throws: VaultStoreError.staleTarget) { try await store.mergingDayCopy("journal/2026-10-09 2.md") }
        let before = try vault.tree()
        let snapshot = try vault.index.snapshot()
        // A differently spelled `Conflicts/` would be scanned; a linked one leads outside the vault.
        let staging = vault.url("staging")
        try FileManager.default.moveItem(at: vault.url("conflicts"), to: staging)
        try FileManager.default.moveItem(at: staging, to: vault.url("Conflicts"))
        await #expect(throws: VaultStoreError.reservedFolderCaseMismatch(found: "Conflicts", expected: "conflicts")) {
            try await store.mergingDayCopy(Shape.merged.copy)
        }
        try FileManager.default.moveItem(at: vault.url("Conflicts"), to: staging)
        let outside = vault.scratch.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.url("conflicts"), withDestinationURL: outside)
        await #expect(throws: VaultStoreError.invalidPath) { try await store.mergingDayCopy(Shape.merged.copy) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.removeItem(at: vault.url("conflicts"))
        try FileManager.default.moveItem(at: staging, to: vault.url("conflicts"))
        #expect(try vault.tree() == before)
        #expect(try vault.index.snapshot() == snapshot)
    }
}

/// Records the coordination boundary and the disk as it was when the accessor began and returned.
final class DayCopySpy: FileCoordination, @unchecked Sendable {
    enum Failure: Error, Equatable, Sendable { case denied, failed }
    enum Event: Equatable {
        case begin(FileCoordinationOperation)
        case willMove(URL, URL)
        case didMove(URL, URL)
        case end(FileCoordinationOperation)
    }
    struct Read {
        let url: URL
        let active: FileCoordinationOperation?
    }

    let root: URL
    private let failure: Failure?
    private let lock = NSLock()
    private var eventLog: [Event] = []
    private var readLog: [Read] = []
    private var states: [[String: Data?]] = []
    private var active: [FileCoordinationOperation] = []
    private var storedMaximumDepth = 0

    init(root: URL, failure: Failure? = nil) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.failure = failure
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    var events: [Event] { lock.withLock { eventLog } }
    var reads: [Read] { lock.withLock { readLog } }
    var maximumDepth: Int { lock.withLock { storedMaximumDepth } }

    func recordRead(_ url: URL) { lock.withLock { readLog.append(Read(url: url, active: active.last)) } }

    /// Paths that changed before the first accessor began, between accessors, or after the last returned.
    func changesOutsideBoundary(before: [String: Data?], after: [String: Data?]) -> [String] {
        let all = [before] + lock.withLock { states } + [after]
        var changed: Set<String> = []
        for index in stride(from: 0, to: all.count, by: 2) where all[index] != all[index + 1] {
            for key in Set(all[index].keys).union(all[index + 1].keys) where all[index][key] != all[index + 1][key] {
                changed.insert(key)
            }
        }
        return changed.sorted()
    }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        lock.withLock {
            eventLog.append(.begin(operation))
            active.append(operation)
            storedMaximumDepth = max(storedMaximumDepth, active.count)
        }
        defer { lock.withLock { _ = active.removeLast() } }
        if let failure { throw failure }
        let begin = try DayCopyVault.tree(root)
        defer {
            let end = (try? DayCopyVault.tree(root)) ?? [:]
            lock.withLock {
                states += [begin, end]
                eventLog.append(.end(operation))
            }
        }
        return try accessor(
            FileCoordinationAccess(
                itemWillMove: { source, destination in
                    self.lock.withLock { self.eventLog.append(.willMove(source, destination)) }
                },
                itemDidMove: { source, destination in
                    self.lock.withLock { self.eventLog.append(.didMove(source, destination)) }
                }))
    }
}
