import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// `SystemFileCoordination` against the real `NSFileCoordinator`, observed by a registered file
/// presenter of the target. A presenter's relinquish and save replies are part of the coordinated
/// access itself, so they are recorded before the accessor runs. A move notice is delivered later;
/// a following coordinated read of the destination reaches the presenter only after it.
struct SystemFileCoordinationTests {
    enum Intent: String, CaseIterable, Sendable {
        case read, modify, move, delete

        func operation(_ file: URL, _ destination: URL) -> FileCoordinationOperation {
            switch self {
            case .read: .read(file)
            case .modify: .modify(file)
            case .move: .move(source: file, destination: destination)
            case .delete: .delete(file)
            }
        }

        /// What the presenter of `file` has been asked by the time the accessor runs.
        var claim: Set<String> {
            switch self {
            case .read: ["toReader", "save"]
            case .modify, .move: ["toWriter", "save"]
            case .delete: ["toWriter", "deletion"]
            }
        }
    }

    enum ProbeError: Error, Equatable { case accessor }

    @Test(arguments: Intent.allCases)
    func theAccessorRunsOnceOnTheCallingThreadInsideTheClaim(_ intent: Intent) throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.md")
        let destination = directory.appendingPathComponent("b.md")
        try Data("önce\n".utf8).write(to: file)
        let presenter = PresenterProbe(file)
        defer { presenter.remove() }
        let caller = pthread_self()
        var calls = 0
        var onCaller = false
        var seen: [String] = []
        var read = Data()

        let value = try SystemFileCoordination().coordinate(intent.operation(file, destination)) { access in
            calls += 1
            onCaller = pthread_equal(pthread_self(), caller) != 0
            seen = presenter.events
            switch intent {
            case .read: read = try Data(contentsOf: file)
            case .modify: try Data("sonra\n".utf8).write(to: file)
            case .move:
                access.itemWillMove(from: file, to: destination)
                try FileManager.default.moveItem(at: file, to: destination)
                access.itemDidMove(from: file, to: destination)
            case .delete: try FileManager.default.removeItem(at: file)
            }
            return 42
        }

        #expect(value == 42)
        #expect(calls == 1)
        #expect(onCaller)
        #expect(Set(seen) == intent.claim)
        switch intent {
        case .read: #expect(read == Data("önce\n".utf8))
        case .modify: #expect(try Data(contentsOf: file) == Data("sonra\n".utf8))
        case .move:
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(try Data(contentsOf: destination) == Data("önce\n".utf8))
        case .delete: #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test(arguments: Intent.allCases)
    func anAccessorErrorComesBackUnchanged(_ intent: Intent) throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.md")
        try Data("önce\n".utf8).write(to: file)
        let destination = directory.appendingPathComponent("b.md")

        #expect(throws: ProbeError.accessor) {
            try SystemFileCoordination().coordinate(intent.operation(file, destination)) { _ -> Int in
                throw ProbeError.accessor
            }
        }
    }

    /// A presenter that cannot save (or give way to a deletion) denies the claim: nothing runs.
    @Test(arguments: Intent.allCases)
    func aDeniedClaimThrowsWithoutRunningTheAccessor(_ intent: Intent) throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.md")
        try Data("önce\n".utf8).write(to: file)
        let destination = directory.appendingPathComponent("b.md")
        let presenter = PresenterProbe(file, refusal: NSError(domain: "PresenterProbe", code: 7))
        defer { presenter.remove() }
        var ran = false

        let error = #expect(throws: NSError.self) {
            try SystemFileCoordination().coordinate(intent.operation(file, destination)) { _ in ran = true }
        }

        #expect(error?.domain == "PresenterProbe" && error?.code == 7)
        #expect(!ran)
        #expect(try Data(contentsOf: file) == Data("önce\n".utf8))
    }

    @Test func aMoveReportedInsideTheClaimReachesThePresenterOfTheSource() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.md")
        let destination = directory.appendingPathComponent("b.md")
        try Data("önce\n".utf8).write(to: file)
        let presenter = PresenterProbe(file)
        defer { presenter.remove() }
        let coordination = SystemFileCoordination()

        // As in a rename: the source is replaced atomically first, so the moved item is a new file
        // the coordinator cannot follow by identity; only the reported move tells the presenter.
        try coordination.coordinate(.move(source: file, destination: destination)) { access in
            try Data("sonra\n".utf8).write(to: file, options: .atomic)
            access.itemWillMove(from: file, to: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            access.itemDidMove(from: file, to: destination)
        }
        try coordination.coordinate(.read(destination)) { _ in }
        let events = presenter.drain()

        #expect(presenter.moves.map(Self.canonical) == [Self.canonical(destination)])
        let moved = try #require(events.firstIndex(of: "moved"))
        #expect(events[moved...].contains("toReader"))
    }

    static func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
}

/// Vault writes made through `IndexStore` claim their files with the system coordinator.
@MainActor
struct CoordinatedVaultWriteTests {
    private static let day =
        "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Tasks\n- [ ] süt al ^sut\n\n## Events\n"
        + "- 08:00 kahve ^kahve\n\n## Journal\nEski.\n"
    private static let person = "---\ntype: person\nname: Ada Kurgu\n---\n"

    private func seed(_ context: TaskTestContext) async throws {
        for (path, text) in ["journal/2026-10-03.md": Self.day, "people/Ada Kurgu.md": Self.person] {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.store.refresh()
    }

    @Test func eventTaskJournalAndRenameWritesAreCoordinatedAndIndexed() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await seed(context)
        let store = context.store
        let today = context.today
        let dayProbe = PresenterProbe(context.file)
        defer { dayProbe.remove() }
        let personFile = context.root.appendingPathComponent("people/Ada Kurgu.md")
        let personProbe = PresenterProbe(personFile)
        defer { personProbe.remove() }

        #expect(await store.addEvent(on: today, text: "kurgu olay", time: nil))
        #expect(dayProbe.count("toWriter") == 1)
        #expect(try context.document().bodyLines.events.map(\.block.text) == ["kahve", "kurgu olay"])
        #expect(store.content.day(on: today).events.map(\.text.plainText).contains("kurgu olay"))

        try await store.completeTask(try context.row("süt al"), on: today)
        #expect(dayProbe.count("toWriter") == 2)
        #expect(try context.document().bodyLines.tasks.first?.status == .done)
        #expect(try context.row("süt al").isClosed)

        try await store.appendToJournal(on: today, lines: ["Kurgu satır."])
        #expect(dayProbe.count("toWriter") == 3)
        #expect(try String(contentsOf: context.file, encoding: .utf8).hasSuffix("Eski.\n\nKurgu satır.\n"))
        #expect(store.content.day(on: today).journal.last?.text.plainText == "Kurgu satır.")

        let result = try await store.renameEntity(at: "people/Ada Kurgu.md", to: "Ada Kurgulu", qualifier: nil)
        let renamed = context.root.appendingPathComponent("people/Ada Kurgulu.md")
        try SystemFileCoordination().coordinate(.read(renamed)) { _ in }
        personProbe.drain()
        #expect(result.path == "people/Ada Kurgulu.md" && result.failures.isEmpty)
        #expect(personProbe.events.prefix(2).sorted() == ["save", "toWriter"])
        #expect(
            personProbe.moves.map(SystemFileCoordinationTests.canonical) == [
                SystemFileCoordinationTests.canonical(renamed)
            ])
        #expect(!FileManager.default.fileExists(atPath: personFile.path))
        #expect(try String(contentsOf: renamed, encoding: .utf8).contains("name: Ada Kurgulu"))
        #expect(store.content.entities.contains { $0.id == "people/Ada Kurgulu.md" })
        #expect(!store.content.entities.contains { $0.id == "people/Ada Kurgu.md" })
    }

    /// Presenters answer on their own queues, never on the vault write queue: every kind of write,
    /// and a vault switch, finishes while both vaults, the day and the person are presented. A
    /// deadlock fails the step after ten seconds.
    @Test(.timeLimit(.minutes(2)))
    func everyWriteAndAVaultSwitchFinishWhileTheVaultIsPresented() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try await seed(context)
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        let probes = [
            context.root, other, context.file, context.root.appendingPathComponent("people/Ada Kurgu.md"),
        ].map { PresenterProbe($0) }
        defer { for probe in probes { probe.remove() } }
        let store = context.store
        let today = context.today
        let row = try context.row("süt al")

        #expect(try await finishes { await store.addEvent(on: today, text: "kilitsiz", time: nil) })
        #expect(try await finishes { (try? await store.completeTask(row, on: today)) != nil })
        #expect(try await finishes { (try? await store.appendToJournal(on: today, lines: ["Kilitsiz."])) != nil })
        #expect(
            try await finishes {
                (try? await store.renameEntity(at: "people/Ada Kurgu.md", to: "Ada Kilitsiz", qualifier: nil)) != nil
            })
        #expect(
            try await finishes {
                (try? await store.createEntity(kind: .place, name: "Kurgu Park", qualifier: nil)) != nil
            })
        #expect(
            try await finishes {
                await store.select(other)
                return store.vaultURL == other && store.lastUpdated != nil
            })
        #expect(try await finishes { await store.addEvent(on: today, text: "öteki kasa", time: nil) })

        // Three day edits. The rename claims only the files linking to the person; the day has none.
        #expect(probes[2].count("toWriter") == 3)
        let day = RawDocument(bytes: try Data(contentsOf: context.file))
        #expect(day.bodyLines.events.map(\.block.text).contains("kilitsiz"))
        #expect(day.bodyLines.tasks.first?.status == .done)
        let otherDay = RawDocument(bytes: try Data(contentsOf: other.appendingPathComponent("journal/2026-10-03.md")))
        #expect(otherDay.bodyLines.events.map(\.block.text).contains("öteki kasa"))
        let renamed = context.root.appendingPathComponent("people/Ada Kilitsiz.md")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    /// On a case-insensitive volume a case-only rename moves a file onto itself: its presenter is
    /// asked to save, never to accommodate the file's deletion.
    @Test func aCaseOnlyRenameNeverAnnouncesTheFilesDeletion() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let caseSensitive = try context.directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        guard caseSensitive.volumeSupportsCaseSensitiveNames == false else { return }
        await context.start()
        try await seed(context)
        let people = context.root.appendingPathComponent("people")
        let probe = PresenterProbe(people.appendingPathComponent("Ada Kurgu.md"))
        defer { probe.remove() }

        let result = try await context.store.renameEntity(at: "people/Ada Kurgu.md", to: "ada kurgu", qualifier: nil)
        let events = probe.drain()

        #expect(result.path == "people/ada kurgu.md" && result.failures.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: people.path) == ["ada kurgu.md"])
        #expect(events.contains("save"))
        #expect(!events.contains("deletion"))
    }

    /// Runs `body` on the main actor and waits at most ten seconds for it to report success.
    private func finishes(_ body: @escaping @MainActor () async -> Bool) async throws -> Bool {
        let outcome = WriteOutcome()
        Task { outcome.saved = await body() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while outcome.saved == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return outcome.saved == true
    }
}

/// Import typing reads and writes each approved file through the system coordinator: the file's
/// presenter is asked to give way to a reader and then to one writer that lets it save first.
struct CoordinatedVaultImportTests {
    @Test func approvedTypeInsertionClaimsTheFile() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("people/Deniz.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("---\nname: Deniz Kurgu\n---\n".utf8).write(to: file)
        let report = try VaultImportScanner.inspect(root)
        try #require(report.candidates.map(\.path) == ["people/Deniz.md"])
        let probe = PresenterProbe(file)
        defer { probe.remove() }

        let result = await VaultImportWriter.apply(report: report, options: VaultImportOptions())

        #expect(result.typed == ["people/Deniz.md"] && result.failures.isEmpty)
        #expect(try String(contentsOf: file, encoding: .utf8) == "---\nname: Deniz Kurgu\ntype: person\n---\n")
        #expect(probe.count("toReader") == 1)
        #expect(probe.count("toWriter") == 1)
    }
}

@MainActor
private final class WriteOutcome {
    var saved: Bool?
}

/// A registered file presenter that records what coordinated access asks of it, answering on its
/// own serial queue. A refusal fails its save and deletion replies.
final class PresenterProbe: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemOperationQueue: OperationQueue
    private let lock = NSLock()
    private let refusal: NSError?
    private var url: URL
    private var log: [String] = []
    private var moved: [URL] = []

    init(_ url: URL, refusal: NSError? = nil) {
        self.url = url
        self.refusal = refusal
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func remove() { NSFileCoordinator.removeFilePresenter(self) }

    var presentedItemURL: URL? { lock.withLock { url } }
    var events: [String] { lock.withLock { log } }
    var moves: [URL] { lock.withLock { moved } }
    func count(_ event: String) -> Int { events.filter { $0 == event }.count }

    /// Runs the messages already handed to the presenter's queue.
    @discardableResult
    func drain() -> [String] {
        presentedItemOperationQueue.waitUntilAllOperationsAreFinished()
        return events
    }

    private func record(_ event: String) { lock.withLock { log.append(event) } }

    func relinquishPresentedItem(toReader reader: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        record("toReader")
        reader(nil)
    }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        record("toWriter")
        writer(nil)
    }

    func savePresentedItemChanges(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        record("save")
        completionHandler(refusal)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        record("deletion")
        completionHandler(refusal)
    }

    func presentedItemDidMove(to newURL: URL) {
        lock.withLock {
            url = newURL
            moved.append(newURL)
            log.append("moved")
        }
    }
}
