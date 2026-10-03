import Foundation
import Testing

@testable import Journal

@MainActor
struct VaultRecoveryTests {
    @Test func automaticStartupLeavesRealHomeUntouched() async throws {
        let before = try homeVaultState()
        let store = IndexStore()
        await store.startAutomatically(environment: ["XCTestConfigurationFilePath": "test"], arguments: [])
        await store.startAutomatically(environment: [:], arguments: ["JOURNAL_NO_AUTOSTART"])
        await store.startAutomatically(environment: ["JOURNAL_NO_AUTOSTART": "1"], arguments: [])
        try await Task.sleep(for: .milliseconds(500))
        #expect(store.vaultURL == nil)
        #expect(!store.isProcessing)
        #expect(try homeVaultState() == before)
        #expect(AppLaunchPolicy.allowsAutomaticStart(environment: [:], arguments: []))
    }

    @Test func staleBookmarkIsUsedAndRenewed() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        suite.defaults.set(Data(temp.path.utf8), forKey: "vaultBookmark")
        var created = 0
        var bookmarks = pathBookmarks(stale: true)
        bookmarks.create = { (url: URL) throws -> Data in
            #expect(url == temp)
            #expect(try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
            created += 1
            return Data("renewed".utf8)
        }
        let location = VaultLocation(
            defaults: suite.defaults, documentsURL: temp.appendingPathComponent("documents"), bookmarks: bookmarks)
        let result = try location.resolve()
        #expect(result.url == temp)
        #expect(result.notice == nil)
        #expect(created == 1)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == Data("renewed".utf8))
    }

    @Test func unavailableFolderPreservesBookmarkAndRetries() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let selected = temp.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let suite = try TestDefaults()
        defer { suite.clean() }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        _ = try location.select(selected)
        let saved = suite.defaults.data(forKey: "vaultBookmark")
        try FileManager.default.removeItem(at: selected)
        let result = try location.resolve()
        #expect(result.url == temp.appendingPathComponent("Vault", isDirectory: true))
        #expect(result.notice != nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        #expect(try location.resolve().url.path == selected.path)
    }

    @Test func validSerializedBookmarkSurvivesResolverFailure() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        // Ordinary bookmark serialization does not require the security-scope agent.
        let data = try temp.bookmarkData(
            options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        var bookmarks = VaultBookmarks()
        #expect(!bookmarks.isMalformed(data))
        bookmarks.resolve = { _ in throw CocoaError(.fileReadNoPermission) }
        suite.defaults.set(data, forKey: "vaultBookmark")
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        #expect(try location.resolve().notice != nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == data)
    }

    @Test func temporaryResolverAndRenewalFailuresPreserveChoice() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let saved = Data(temp.path.utf8)
        suite.defaults.set(saved, forKey: "vaultBookmark")
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadNoPermission) }
        let failed = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        #expect(try failed.resolve().notice != nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
        bookmarks = pathBookmarks(stale: true)
        bookmarks.create = { _ in throw CocoaError(.fileWriteNoPermission) }
        let stale = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let resolved = try stale.resolve()
        #expect(resolved.url == temp)
        #expect(resolved.notice != nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
    }
}

@MainActor
struct IndexSchedulingTests {
    @Test func selectionWaitsForRefreshAndShowsNewVaultCounts() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = UpdateGate()
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        let store = IndexStore(
            location: location, supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild in
                let result = try await IndexUpdate.read(index: index, root: root, rebuild: rebuild)
                await gate.hold()
                return result
            })
        await store.start()
        let next = temp.appendingPathComponent("next")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        try Data("- [ ] First\n- [ ] Second\n".utf8).write(to: next.appendingPathComponent("note.md"))
        await gate.arm()
        let refresh = Task { await store.refresh() }
        try await waitForGate(gate)
        await store.select(next)
        #expect(store.pendingSelection == next)
        #expect(store.vaultURL != next)
        #expect(store.isProcessing)
        await gate.release()
        await refresh.value
        #expect(store.pendingSelection == nil)
        #expect(store.vaultURL == next)
        #expect(store.counts.tasks == 2)
        #expect(store.errorText == nil)
        #expect(!store.isProcessing)
    }

    @Test func refreshDuringOperationIsNotLost() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = UpdateGate()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild in
                let result = try await IndexUpdate.read(index: index, root: root, rebuild: rebuild)
                await gate.hold()
                return result
            })
        await store.start()
        let root = try #require(store.vaultURL)
        await gate.arm()
        let refresh = Task { await store.refresh() }
        try await waitForGate(gate)
        try Data("- [ ] Arrived during refresh\n".utf8).write(to: root.appendingPathComponent("notes/new.md"))
        await store.refresh()
        await gate.release()
        await refresh.value
        #expect(store.counts.tasks == 1)
        #expect(await gate.calls == 3)
    }

    @Test func foregroundStartupRefreshesOnlyOnce() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = UpdateGate()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild in
                await gate.hold()
                return try await IndexUpdate.read(index: index, root: root, rebuild: rebuild)
            })
        store.setForeground(true)
        await store.start()
        try await Task.sleep(for: .milliseconds(700))
        #expect(await gate.calls == 1)
        store.setForeground(false)
    }
}
