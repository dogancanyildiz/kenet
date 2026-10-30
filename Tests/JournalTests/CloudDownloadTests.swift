import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// Records every download request instead of reaching iCloud.
actor RecordingCloudDownloader: CloudDownloading {
    private(set) var calls: [[URL]] = []
    /// How many requests of each call the fake refuses.
    private let refusals: Int

    init(refusing refusals: Int = 0) { self.refusals = refusals }

    func startDownloading(_ items: [URL]) async -> Int {
        calls.append(items)
        return min(refusals, items.count)
    }
}

/// Holds every request until the test opens it, so a refresh or a write can be shown not to wait.
actor GatedCloudDownloader: CloudDownloading {
    private(set) var calls: [[URL]] = []
    private var isOpen = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var callWaiters: [CheckedContinuation<Void, Never>] = []

    /// Refuses every request once let through.
    func startDownloading(_ items: [URL]) async -> Int {
        calls.append(items)
        for waiter in callWaiters { waiter.resume() }
        callWaiters = []
        if !isOpen { await withCheckedContinuation { held.append($0) } }
        return items.count
    }

    func waitForCall() async {
        guard calls.isEmpty else { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    func open() {
        isOpen = true
        for request in held { request.resume() }
        held = []
    }
}

/// A vault with iCloud placeholders opened as the iCloud vault, the default local vault or a
/// selected folder (one inside iCloud Drive, which still is not the iCloud vault).
@MainActor
struct CloudSyncTestContext {
    enum Kind { case icloud, local, selected }

    nonisolated static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults")

    let kind: Kind
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let downloader: RecordingCloudDownloader
    let store: IndexStore

    /// `fixture` is a folder under `Fixtures/vaults`, copied as the vault.
    init(
        _ kind: Kind, fixture: String, policy: SyncPolicy = .standard,
        downloader: RecordingCloudDownloader = RecordingCloudDownloader(),
        cloudDownloader: (any CloudDownloading)? = nil
    ) throws {
        self.kind = kind
        directory = try testDirectory()
        defaults = try TestDefaults()
        let container = directory.appendingPathComponent("Cloud", isDirectory: true)
        switch kind {
        case .icloud:
            root = container.appendingPathComponent("Documents/Kenet", isDirectory: true)
            defaults.defaults.set(VaultLocation.Kind.icloud.rawValue, forKey: VaultLocation.kindKey)
        case .local:
            root = directory.appendingPathComponent("Vault", isDirectory: true)
        case .selected:
            root = directory.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs/Kenet", isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(fixture), to: root)
        self.downloader = downloader
        store = IndexStore(
            location: VaultLocation(
                defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks(),
                ubiquity: FakeUbiquityContainer(url: container)),
            supportURL: directory.appendingPathComponent("indexes"), cloudDownloader: cloudDownloader ?? downloader,
            syncPolicy: policy)
    }

    /// Opens the vault and waits for the download requests its first refresh sent.
    func start() async {
        if kind == .selected { await store.select(root) } else { await store.start() }
        await store.waitForDownloadRequests()
    }

    /// Refreshes the whole vault, or only `directories`, and waits for any refresh the watcher
    /// started meanwhile. A refresh that finds no Markdown change still publishes the lists.
    func refresh(directories: Set<String>? = nil) async {
        await store.waitWhileRefreshInFlight()
        await store.refresh(directories: directories)
        await store.waitWhileRefreshInFlight()
        await store.waitForDownloadRequests()
    }

    func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    /// iCloud brings the file: its placeholder goes and the original takes its place.
    func arrive(_ path: String, bytes: String) throws {
        try FileManager.default.removeItem(at: placeholder(of: path))
        try Data(bytes.utf8).write(to: url(path))
    }

    /// iCloud evicts the file again: only its placeholder stays.
    func evict(_ path: String) throws {
        try FileManager.default.removeItem(at: url(path))
        try Data().write(to: placeholder(of: path))
    }

    private func placeholder(of path: String) -> URL {
        let original = url(path)
        return original.deletingLastPathComponent()
            .appendingPathComponent(PlaceholderName.placeholderName(for: original.lastPathComponent))
    }

    func clean() {
        store.setForeground(false)
        try? FileManager.default.removeItem(at: directory)
        defaults.clean()
    }
}

/// The placeholder fixture's expectations (`Fixtures/vaults/placeholder/expected.json`).
struct PlaceholderExpectation: Decodable {
    let pending: [String]
    let files: [String]

    /// Core's pending Markdown files and the type catalog's placeholder (`.app/.types.json.icloud`),
    /// which the app adds: every original the iCloud vault asks for, in UTF-8 byte order.
    var waiting: [String] { ([SyncLists.typesPath] + pending).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) } }

    static func load() throws -> Self {
        try JSONDecoder().decode(
            Self.self,
            from: Data(
                contentsOf: CloudSyncTestContext.fixtures.appendingPathComponent("placeholder/expected.json")))
    }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct CloudDownloadTests {
    static let arrivedDay = "---\ntype: journal\ndate: 2026-09-30\n---\n\n## Events\n- Sabah yürüyüşü\n"

    @Test func iCloudVaultRequestsEachPlaceholderOnce() async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(.icloud, fixture: "placeholder")
        defer { context.clean() }
        await context.start()
        #expect(context.store.vaultURL == context.root)
        #expect(context.store.sync.pendingDownloads == expected.waiting)
        let calls = await context.downloader.calls
        #expect(calls.count == 1)
        #expect(
            calls.first?.map(\.standardizedFileURL.path)
                == expected.waiting.map { context.url($0).standardizedFileURL.path })

        // The next publish finds the same placeholders: nothing is asked for again.
        await context.refresh()
        #expect(context.store.sync.pendingDownloads == expected.waiting)
        #expect(await context.downloader.calls.count == 1)
    }

    @Test func arrivedFileIsIndexedAndLeavesTheList() async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(.icloud, fixture: "placeholder")
        defer { context.clean() }
        await context.start()
        let day = try #require(CalendarDate("2026-09-30"))
        #expect(!(try await context.store.computeDaySummaries()).contains { $0.date == day })

        try context.arrive("journal/2026-09-30.md", bytes: Self.arrivedDay)
        // The watcher's refresh of the one folder: the other folders' placeholders still wait.
        await context.refresh(directories: ["journal"])

        #expect(context.store.sync.pendingDownloads == expected.waiting.filter { $0 != "journal/2026-09-30.md" })
        let days = try await context.store.computeDaySummaries()
        #expect(days.first { $0.date == day }?.eventCount == 1)
        // The arrived file is not asked for again, nor are the others.
        #expect(await context.downloader.calls.count == 1)

        // Evicted again, the file is asked for again, alone.
        try context.evict("journal/2026-09-30.md")
        await context.refresh()
        #expect(context.store.sync.pendingDownloads == expected.waiting)
        let calls = await context.downloader.calls
        #expect(calls.count == 2)
        #expect(calls.last?.map(\.lastPathComponent) == ["2026-09-30.md"])
    }

    @Test(arguments: [CloudSyncTestContext.Kind.local, .selected])
    func otherVaultsNeverRequestDownloads(_ kind: CloudSyncTestContext.Kind) async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(kind, fixture: "placeholder")
        defer { context.clean() }
        await context.start()
        #expect(context.store.vaultURL == context.root)
        #expect(!context.store.isCloudVault)
        // The scan still lists the placeholders; only the request is the iCloud vault's.
        #expect(context.store.sync.pendingDownloads == expected.waiting)
        await context.refresh()
        #expect(await context.downloader.calls.isEmpty)
    }

    @Test func refusedRequestsAreCountedNotRetried() async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(
            .icloud, fixture: "placeholder", downloader: RecordingCloudDownloader(refusing: 2))
        defer { context.clean() }
        await context.start()
        #expect(context.store.sync.downloadFailures == 2)
        await context.refresh()
        #expect(await context.downloader.calls.count == 1)
        #expect(context.store.sync.downloadFailures == 2)
        #expect(context.store.sync.pendingDownloads == expected.waiting)
    }

    /// The refresh publishes and a write goes through while iCloud has not answered a request.
    @Test func refreshAndWritesDoNotWaitForRequests() async throws {
        let expected = try PlaceholderExpectation.load()
        let gated = GatedCloudDownloader()
        let context = try CloudSyncTestContext(.icloud, fixture: "placeholder", cloudDownloader: gated)
        defer { context.clean() }
        await context.store.start()
        await gated.waitForCall()

        // The request is still held: the vault is open and its days are published.
        #expect(context.store.lastUpdated != nil)
        #expect(context.store.sync.pendingDownloads == expected.waiting)
        let day = try #require(CalendarDate("2026-10-01"))
        #expect(try await context.store.computeDaySummaries().contains { $0.date == day })
        #expect(await context.store.addEvent(on: day, text: "Akşam yürüyüşü", time: nil))
        #expect(
            try String(contentsOf: context.url("journal/2026-10-01.md"), encoding: .utf8).contains("Akşam yürüyüşü"))
        #expect(context.store.sync.downloadFailures == 0)

        await gated.open()
        await context.store.waitForDownloadRequests()
        #expect(await gated.calls.count == 1)
        #expect(context.store.sync.downloadFailures == expected.waiting.count)
    }

    /// Back in the foreground every placeholder still waiting is asked for again, once per return.
    @Test func foregroundReturnAsksAgain() async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(
            .icloud, fixture: "placeholder", downloader: RecordingCloudDownloader(refusing: 1))
        defer { context.clean() }
        await context.start()
        #expect(await context.downloader.calls.count == 1)

        context.store.setForeground(true)
        await context.refresh()
        var calls = await context.downloader.calls
        #expect(calls.count == 2)
        #expect(calls.last?.count == expected.waiting.count)
        // Still in the foreground: nothing new to ask for.
        context.store.setForeground(true)
        await context.refresh()
        #expect(await context.downloader.calls.count == 2)
        context.store.setForeground(false)
        context.store.setForeground(true)
        await context.refresh()
        calls = await context.downloader.calls
        #expect(calls.count == 3)
        #expect(context.store.sync.downloadFailures == 3)
    }

    /// The same vault opened again starts over: its placeholders are asked for again and the
    /// counts of the previous opening are gone.
    @Test func reopeningTheVaultStartsOver() async throws {
        let context = try CloudSyncTestContext(
            .icloud, fixture: "placeholder", downloader: RecordingCloudDownloader(refusing: 1))
        defer { context.clean() }
        await context.start()
        #expect(context.store.sync.downloadFailures == 1)
        await context.store.retryVaultAccess()
        #expect(context.store.vaultURL == context.root)
        await context.store.waitForDownloadRequests()
        #expect(await context.downloader.calls.count == 2)
        #expect(context.store.sync.downloadFailures == 1)
    }
}
