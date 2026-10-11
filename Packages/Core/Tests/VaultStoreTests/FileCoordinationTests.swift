import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

struct FileCoordinationTests {
    enum Workflow: CaseIterable, Sendable {
        case edit, createDay, entity, rename, typeSave, typeDelete, goal, journal, link, read
    }

    enum Outcome: CaseIterable, Sendable {
        case allow, deny, fail
    }

    @Test(arguments: Workflow.allCases, Outcome.allCases)
    func accessLogAndRejection(workflow: Workflow, outcome: Outcome) async throws {
        let vault = try workflow == .link ? UnlinkedMentionTests().setup() : StoreVault(sample: true)
        defer { vault.remove() }
        if workflow == .goal {
            try FileManager.default.removeItem(at: vault.root.appendingPathComponent("goals/Su.md"))
            try vault.index.rebuild(vaultRoot: vault.root)
        }
        let spy = CoordinationSpy(root: vault.root, outcome: outcome)
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index, randomValue: { 0 },
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            readFile: { url in
                spy.recordRead(url)
                return try Data(contentsOf: url)
            }, fileCoordination: spy)
        let definition = try #require(
            EntityTypeReader.read(vaultRoot: Fixtures.root().appendingPathComponent("vaults/typed")).types.first)
        if workflow == .typeDelete { try await vault.store.savingEntityType(definition) }
        let document = RawDocument(bytes: try vault.bytes(workflow == .link ? UnlinkedMentionTests.day : storePath))
        let source = "people/Deniz Arıkan.md"
        let destination = "people/Deniz Arıkan Yılmaz.md"
        let paths = try vault.index.files().map(\.path).sorted()
        let before = try CoordinationSpy.snapshot(vault.root)
        let indexBefore = try vault.index.snapshot()
        let sql = StatementLog()
        try await vault.index.database.write { db in db.trace { sql.append($0.expandedDescription) } }
        let operation: FileCoordinationOperation
        switch workflow {
        case .rename: operation = .move(source: spy.url(source), destination: spy.url(destination))
        case .read: operation = .read(spy.url(storePath))
        case .entity: operation = .modify(spy.url("people/Ece Yalın (iş).md"))
        case .goal: operation = .modify(spy.url("goals/Su.md"))
        case .typeSave, .typeDelete: operation = .modify(spy.url(".app/types.json"))
        case .createDay: operation = .modify(spy.url("journal/2026-10-01.md"))
        case .link: operation = .modify(spy.url(UnlinkedMentionTests.day))
        default: operation = .modify(spy.url(storePath))
        }
        let action: () async throws -> Void = {
            switch workflow {
            case .edit:
                _ = try await store.changingText(of: document.bodyLines.events[0].block, at: storePath, to: "Su")
            case .createDay:
                _ = try await store.addingEvent(on: CalendarDate("2026-10-01")!, text: "Su")
            case .entity:
                _ = try await store.creatingEntity(kind: .person, name: "Ece Yalın", qualifier: "iş")
            case .rename:
                let result = try await store.renamingEntity(at: source, to: "Deniz Arıkan Yılmaz")
                #expect(result.failures.isEmpty)
            case .typeSave: try await store.savingEntityType(definition)
            case .typeDelete: try await store.deletingEntityType(definition)
            case .goal:
                _ = try await store.creatingGoal(name: "Su", period: .day, kind: .number, target: 8)
            case .journal: _ = try await store.appendingJournal(on: storeDate, lines: ["Su"])
            case .link:
                let helper = UnlinkedMentionTests()
                let entity = try helper.entity(UnlinkedMentionTests.elif, in: vault)
                let mention = try helper.mention(vault, line: 7)
                _ = try await store.linkingMention(mention, to: entity)
            case .read: _ = try await store.document(at: storePath)
            }
        }
        if outcome == .allow {
            try await action()
            var expected: [CoordinationSpy.Event] = [.begin(operation)]
            if workflow == .rename {
                expected += [
                    .willMove(spy.url(source), spy.url(destination)), .didMove(spy.url(source), spy.url(destination)),
                ]
            }
            expected.append(.end(operation))
            if workflow == .rename {
                for path in paths {
                    let update = FileCoordinationOperation.modify(spy.url(path == source ? destination : path))
                    expected += [.begin(update), .end(update)]
                }
            }
            #expect(spy.events == expected)
            #expect(spy.maximumDepth == 1)
            let after = try CoordinationSpy.snapshot(vault.root)
            #expect(spy.changesOutsideBoundaries(before: before, after: after).isEmpty)
            #expect(workflow == .read ? after == before : after != before)
            if workflow == .edit || workflow == .journal || workflow == .link || workflow == .read {
                let target = workflow == .link ? UnlinkedMentionTests.day : storePath
                #expect(spy.reads.filter { $0.url == spy.url(target) }.map(\.active) == [operation])
            }
            try vault.check()
        } else {
            let error = outcome == .deny ? CoordinationSpy.Failure.denied : .failed
            await #expect(throws: error) { try await action() }
            #expect(spy.events == [.begin(operation)])
            #expect(spy.maximumDepth == 1)
            #expect(spy.boundaries.isEmpty)
            #expect(try CoordinationSpy.snapshot(vault.root) == before)
            #expect(try vault.index.snapshot() == indexBefore)
            #expect(sql.contentMutations.isEmpty)
        }
    }

    @Test func directCoordinationRunsFilesystemAccessAndPropagatesAccessorErrors() throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let coordinator = DirectFileCoordination()
        let source = vault.root.appendingPathComponent(storePath)
        let target = vault.root.appendingPathComponent("journal/2026-10-01.md")
        let original = try vault.bytes()
        let read = try coordinator.coordinate(.read(source)) { _ in try Data(contentsOf: source) }
        #expect(read == original)
        let appended = original + Data("\nSu\n".utf8)
        try coordinator.coordinate(.modify(source)) { _ in try appended.write(to: source) }
        #expect(try vault.bytes() == appended)
        try coordinator.coordinate(.move(source: source, destination: target)) { access in
            access.itemWillMove(from: source, to: target)
            try FileManager.default.moveItem(at: source, to: target)
            access.itemDidMove(from: source, to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: target) == appended)
        try coordinator.coordinate(.delete(target)) { _ in try FileManager.default.removeItem(at: target) }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(throws: CoordinationSpy.Failure.failed) {
            try coordinator.coordinate(.read(source)) { _ in throw CoordinationSpy.Failure.failed }
        }
    }

    @Test func concurrentEditsCompleteEachBoundaryBeforeTheNextBegins() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let spy = CoordinationSpy(root: vault.root)
        let first = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: spy)
        let second = VaultStore(vaultRoot: vault.root, index: vault.index, fileCoordination: spy)
        async let a = first.appendingJournal(on: storeDate, lines: ["Kitap"])
        async let b = second.appendingJournal(on: storeDate, lines: ["Su"])
        _ = try await (a, b)
        let operation = FileCoordinationOperation.modify(spy.url(storePath))
        #expect(spy.events == [.begin(operation), .end(operation), .begin(operation), .end(operation)])
        #expect(spy.maximumDepth == 1)
        let boundaries = spy.boundaries
        #expect(boundaries.count == 2)
        let firstBytes = try #require(boundaries.first?.end[storePath])
        let finalBytes = try #require(boundaries.last?.end[storePath])
        #expect(boundaries.last?.begin[storePath] == firstBytes)
        let firstDocument = RawDocument(bytes: firstBytes)
        let finalDocument = RawDocument(bytes: finalBytes)
        let added = firstDocument.lines.compactMap(\.text).filter { $0 == "Kitap" || $0 == "Su" }
        #expect(added.count == 1)
        #expect(finalDocument.lines.compactMap(\.text).contains("Kitap"))
        #expect(finalDocument.lines.compactMap(\.text).contains("Su"))
        #expect(try vault.bytes() == finalBytes)
        try vault.check()
    }

    /// A failed move restores the source before the boundary ends and never reports a move.
    @Test(arguments: [false, true])
    func failedRenameRestoresInsideTheMoveBoundary(restoreFails: Bool) async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let source = "people/Deniz Arıkan.md"
        let destination = "people/Deniz Arıkan Yılmaz.md"
        let spy = CoordinationSpy(root: vault.root)
        let failingRestore: @Sendable (Data, URL) throws -> Void = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            moveFile: { _, _ in throw CoordinationSpy.Failure.failed },
            restoreRenameFile: restoreFails ? failingRestore : nil,
            fileCoordination: spy)
        let before = try CoordinationSpy.snapshot(vault.root)
        if restoreFails {
            let result = try await store.renamingEntity(at: source, to: "Deniz Arıkan Yılmaz")
            #expect(result.hasPartialChange)
        } else {
            await #expect(throws: CoordinationSpy.Failure.failed) {
                try await store.renamingEntity(at: source, to: "Deniz Arıkan Yılmaz")
            }
        }
        let operation = FileCoordinationOperation.move(source: spy.url(source), destination: spy.url(destination))
        #expect(spy.events == [.begin(operation), .willMove(spy.url(source), spy.url(destination)), .end(operation)])
        #expect(spy.maximumDepth == 1)
        let after = try CoordinationSpy.snapshot(vault.root)
        #expect(spy.changesOutsideBoundaries(before: before, after: after).isEmpty)
        #expect((after == before) == !restoreFails)
        #expect(!FileManager.default.fileExists(atPath: spy.url(destination).path))
        try vault.check()
    }
}

private final class CoordinationSpy: FileCoordination, @unchecked Sendable {
    enum Failure: Error, Equatable { case denied, failed }
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
    /// Disk contents when an accessor started and when it returned or threw.
    struct Boundary {
        let begin: [String: Data]
        let end: [String: Data]
    }

    let root: URL
    private let outcome: FileCoordinationTests.Outcome
    private let lock = NSLock()
    private var eventLog: [Event] = []
    private var boundaryLog: [Boundary] = []
    private var readLog: [Read] = []
    private var active: [FileCoordinationOperation] = []
    private var depth = 0
    private var storedMaximumDepth = 0

    init(root: URL, outcome: FileCoordinationTests.Outcome = .allow) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.outcome = outcome
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }
    var events: [Event] { lock.withLock { eventLog } }
    var boundaries: [Boundary] { lock.withLock { boundaryLog } }
    var reads: [Read] { lock.withLock { readLog } }
    /// More than one means an accessor started another coordination: `NSFileCoordinator` deadlocks there.
    var maximumDepth: Int { lock.withLock { storedMaximumDepth } }

    func recordRead(_ url: URL) { lock.withLock { readLog.append(Read(url: url, active: active.last)) } }

    /// Paths whose bytes changed while no accessor ran: before the first, between two, or after the last.
    func changesOutsideBoundaries(before: [String: Data], after: [String: Data]) -> [String] {
        var states = [before]
        for boundary in boundaries { states += [boundary.begin, boundary.end] }
        states.append(after)
        var changed: Set<String> = []
        for index in stride(from: 0, to: states.count, by: 2) where states[index] != states[index + 1] {
            let keys = Set(states[index].keys).union(states[index + 1].keys)
            changed.formUnion(keys.filter { states[index][$0] != states[index + 1][$0] })
        }
        return changed.sorted()
    }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        lock.withLock {
            eventLog.append(.begin(operation))
            active.append(operation)
            depth += 1
            storedMaximumDepth = max(storedMaximumDepth, depth)
        }
        defer {
            lock.withLock {
                active.removeLast()
                depth -= 1
            }
        }
        switch outcome {
        case .deny: throw Failure.denied
        case .fail: throw Failure.failed
        case .allow: break
        }
        let begin = try Self.snapshot(root)
        defer {
            let end = (try? Self.snapshot(root)) ?? [:]
            lock.withLock {
                boundaryLog.append(Boundary(begin: begin, end: end))
                eventLog.append(.end(operation))
            }
        }
        let access = FileCoordinationAccess(
            itemWillMove: { source, destination in self.log(.willMove(source, destination)) },
            itemDidMove: { source, destination in self.log(.didMove(source, destination)) })
        return try accessor(access)
    }

    private func log(_ event: Event) { lock.withLock { eventLog.append(event) } }

    static func snapshot(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(path)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files[path] = try Data(contentsOf: url)
            }
        }
        return files
    }
}
