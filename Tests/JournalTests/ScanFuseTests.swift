import Foundation
import Testing

@testable import Journal

/// Whole-vault scans the store asks for besides events: the foreground fuse and foreground return
/// run only on directory sources (iOS, or the Mac without an event stream), and one launch opens the
/// vault once. A whole-vault scan holds the index's single write queue, so every extra one stalls
/// the screens' queries.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct ScanFuseTests {
    @Test func directorySourcesRunTheFuseAndRescanOnForegroundReturn() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let scopes = ScopeLog()
        let ticker = ManualTicker()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), watcherTicker: ticker, watcherFileEvents: false,
            scopedUpdate: scopes.recordingUpdate())
        await store.start()
        defer { store.setForeground(false) }
        #expect(await scopes.all == [nil])

        // An in-place edit made in the background reached no source: the return rescans everything.
        store.setForeground(true)
        try await scopes.wait(for: 2)
        await waitUntil { ticker.scheduleCount == 1 }
        #expect(ticker.scheduleCount == 1)
        ticker.advance(by: VaultWatcher.foregroundInterval)
        try await scopes.wait(for: 3)
        #expect(await scopes.all == [nil, nil, nil])
    }

    @Test func secondStartWaitsForTheFirstAndOpensTheVaultOnce() async throws {
        let provider = HeldUbiquityContainer()
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        await provider.set(context.container)
        let root = context.container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sampleVault, to: root)
        context.defaults.defaults.set(VaultLocation.Kind.icloud.rawValue, forKey: VaultLocation.kindKey)
        let walks = LockedLog<Bool>()
        context.store.testingWatcherInitialScan = { walks.append(true) }

        // Each call is awaited with a bound: a start lock that never opens fails the test instead
        // of hanging the run (Swift Testing's time limit cannot end a suspended continuation).
        let firstReturned = LockedLog<Bool>()
        let secondReturned = LockedLog<Bool>()
        // The window's start waits for iCloud; the quick entry's start arrives meanwhile.
        _ = await startedTask {
            await context.store.start()
            firstReturned.append(true)
        }
        await waitUntil { await provider.lookups == 1 }
        _ = await startedTask {
            await context.store.start()
            secondReturned.append(true)
        }
        #expect(context.store.lastUpdated == nil)
        await provider.release()
        #expect(await waitUntil { !secondReturned.all.isEmpty }, "the second start never returned")
        // The second call returned only once the first had opened the vault.
        #expect(context.store.lastUpdated != nil)
        #expect(await waitUntil { !firstReturned.all.isEmpty }, "the first start never returned")

        #expect(await provider.lookups == 1)
        #expect(walks.all.count == 1)
        #expect(samePath(context.store.vaultURL, root))
        #expect(context.store.errorText == nil)

        // The lock is open again: a later start returns at once with the vault already open.
        let thirdReturned = LockedLog<Bool>()
        _ = await startedTask {
            await context.store.start()
            thirdReturned.append(true)
        }
        #expect(await waitUntil { !thirdReturned.all.isEmpty }, "a later start waited for a finished one")
        #expect(await provider.lookups == 1)
    }

    @Test func failedRefreshIsRetriedOnForegroundReturn() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let scopes = ScopeLog()
        // The Mac's default here is the event stream: no fuse would retry the failed refresh.
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"), watcherTicker: ManualTicker(),
            scopedUpdate: scopes.recordingUpdate())
        await store.start()
        defer { store.setForeground(false) }
        await scopes.failNext()
        await store.refresh(directories: ["notes"])
        #expect(store.errorText != nil)

        store.setForeground(true)
        try await scopes.wait(for: 3)
        await store.waitWhileRefreshInFlight()
        #expect(await scopes.all == [nil, ["notes"], nil])
        #expect(store.errorText == nil)

        // Nothing left to retry: on the Mac's stream the next return scans nothing.
        store.setForeground(false)
        store.setForeground(true)
        let clock = try WatcherClock()
        defer { clock.stop() }
        await clock.waitDebounces()
        await store.waitWhileRefreshInFlight()
        #if os(macOS)
            #expect(await scopes.all == [nil, ["notes"], nil])
        #else
            #expect(await scopes.all == [nil, ["notes"], nil, nil])
        #endif
    }

    #if os(macOS)
        @Test func eventStreamSchedulesNoFuseAndScansNothingOnForegroundReturn() async throws {
            for fileEvents in [true, false] {
                let root = try testDirectory()
                defer { try? FileManager.default.removeItem(at: root) }
                let ticker = ManualTicker()
                let changes = LockedLog<VaultChange>()
                let watcher = VaultWatcher(root: root, ticker: ticker, fileEvents: fileEvents) { changes.append($0) }
                defer { watcher.stop() }
                await watcher.waitUntilReady()
                watcher.setForeground(true)
                // The watcher queue is serial: once this returns, the foreground call has run.
                await watcher.waitUntilReady()
                #expect(ticker.scheduleCount == (fileEvents ? 0 : 1), "file events: \(fileEvents)")
                let clock = try WatcherClock()
                defer { clock.stop() }
                await clock.waitDebounces()
                #expect(changes.all == (fileEvents ? [] : [.full]), "file events: \(fileEvents)")
            }
        }

        @Test func eventStreamOnANetworkVolumeKeepsTheFuse() async throws {
            for localVolume in [true, false] {
                let root = try testDirectory()
                defer { try? FileManager.default.removeItem(at: root) }
                let ticker = ManualTicker()
                let changes = LockedLog<VaultChange>()
                let watcher = VaultWatcher(root: root, ticker: ticker, localVolume: localVolume) {
                    changes.append($0)
                }
                defer { watcher.stop() }
                await watcher.waitUntilReady()
                // The stream runs either way; on a network volume it misses other machines' writes.
                #expect(await watcher.testingFileEventStream() != nil)
                watcher.setForeground(true)
                await watcher.waitUntilReady()
                #expect(ticker.scheduleCount == (localVolume ? 0 : 1), "local volume: \(localVolume)")
                let clock = try WatcherClock()
                defer { clock.stop() }
                await clock.waitDebounces()
                #expect(changes.all == (localVolume ? [] : [.full]), "local volume: \(localVolume)")
                ticker.advance(by: VaultWatcher.foregroundInterval)
                if !localVolume {
                    try await changes.wait(for: 2)
                    #expect(changes.all == [.full, .full])
                }
            }
        }

        @Test func eventStreamStoreScansOnlyAtOpening() async throws {
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
            ticker.advance(by: VaultWatcher.foregroundInterval)
            store.setForeground(false)
            store.setForeground(true)
            // Negative check: a fuse tick or a foreground scan would refresh within two debounces.
            let clock = try WatcherClock()
            defer { clock.stop() }
            await clock.waitDebounces()
            await store.waitWhileRefreshInFlight()
            #expect(ticker.scheduleCount == 0)
            #expect(await scopes.all == [nil])
        }

        @Test(arguments: [true, false])
        func quickEntryPanelAsksForNoScanOfItsOwn(fileEvents: Bool) async throws {
            let temp = try testDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let suite = try TestDefaults()
            defer { suite.clean() }
            let scopes = ScopeLog()
            let store = IndexStore(
                location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
                supportURL: temp.appendingPathComponent("indexes"), watcherTicker: ManualTicker(),
                watcherFileEvents: fileEvents, scopedUpdate: scopes.recordingUpdate())
            await store.start()
            defer { store.setForeground(false) }
            let window = QuickEntryWindowModel(store: store)
            let clock = try WatcherClock()
            defer { clock.stop() }

            // From the background: the foreground return is the only scan; the event stream needs none.
            MacQuickEntryController.present(window)
            #expect(window.isPresented)
            let expected: [Set<String>?] = fileEvents ? [nil] : [nil, nil]
            try await scopes.wait(for: expected.count)
            await clock.waitDebounces()
            await store.waitWhileRefreshInFlight()
            #expect(await scopes.all == expected)

            // The app already in the foreground: opening the panel again scans nothing.
            window.close()
            MacQuickEntryController.present(window)
            await clock.waitDebounces()
            await store.waitWhileRefreshInFlight()
            #expect(await scopes.all == expected)
        }
    #endif
}

/// Holds every container lookup until released, as a slow iCloud answer at launch does.
private actor HeldUbiquityContainer: UbiquityContainerProviding {
    private var url: URL?
    private var released = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private(set) var lookups = 0

    func set(_ url: URL?) { self.url = url }

    func containerURL() async -> URL? {
        lookups += 1
        if !released { await withCheckedContinuation { held.append($0) } }
        return url
    }

    func release() {
        released = true
        for waiter in held { waiter.resume() }
        held = []
    }
}

private let sampleVault = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/vaults/sample")
