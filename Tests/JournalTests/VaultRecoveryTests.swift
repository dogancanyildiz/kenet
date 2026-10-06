import Foundation
import Testing
import VaultStore

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

    @Test func uiTestVaultDisablesAutomaticStartWithoutOpeningRealHome() async throws {
        let before = try homeVaultState()
        let path = "/tmp/journal-uitest-vault-does-not-exist"
        #expect(AppLaunchPolicy.uiTestVaultPath(environment: ["JOURNAL_UITEST_VAULT": path], arguments: []) == path)
        #expect(
            AppLaunchPolicy.uiTestVaultPath(environment: [:], arguments: ["JOURNAL_UITEST_VAULT=" + path]) == path)
        #expect(!AppLaunchPolicy.allowsAutomaticStart(environment: ["JOURNAL_UITEST_VAULT": path], arguments: []))
        let store = IndexStore()
        await store.startAutomatically(environment: ["JOURNAL_UITEST_VAULT": path], arguments: [])
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.vaultURL == nil)
        #expect(try homeVaultState() == before)
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
        guard case .available(let url, let notice) = result else {
            Issue.record("Expected available vault")
            return
        }
        #expect(url == temp)
        #expect(notice == nil)
        #expect(created == 1)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == Data("renewed".utf8))
    }

    @Test func unavailableFolderIsInaccessibleWithoutCreatingLocalVault() throws {
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
        #expect(try location.resolve() == .inaccessible)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        guard case .available(let url, _) = try location.resolve() else {
            Issue.record("Expected available vault after folder returns")
            return
        }
        #expect(url.path == selected.path)
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
        #expect(try location.resolve() == .inaccessible)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == data)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
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
        #expect(try failed.resolve() == .inaccessible)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
        bookmarks = pathBookmarks(stale: true)
        bookmarks.create = { _ in throw CocoaError(.fileWriteNoPermission) }
        let stale = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let resolved = try stale.resolve()
        guard case .available(let url, let notice) = resolved else {
            Issue.record("Expected available vault when folder exists")
            return
        }
        #expect(url == temp)
        #expect(notice != nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == saved)
    }

    @Test func legacyDocumentsVaultOpensWithoutBookmark() throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let vault = temp.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        guard case .available(let url, let notice) = try location.resolve() else {
            Issue.record("Expected legacy Documents/Vault to open")
            return
        }
        #expect(url.path == vault.path)
        #expect(notice == nil)
    }
}

@MainActor
struct VaultInaccessibleStoreTests {
    @Test func startMarksInaccessibleWithoutOpeningWriter() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let selected = temp.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let suite = try TestDefaults()
        defer { suite.clean() }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        _ = try location.select(selected)
        try FileManager.default.removeItem(at: selected)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(!store.canAddEvent)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.performEdit(path: "notes/x.md") { _ in }
        }
    }

    @Test func retryOpensVaultWhenBookmarkBecomesAvailable() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let selected = temp.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let suite = try TestDefaults()
        defer { suite.clean() }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        _ = try location.select(selected)
        try FileManager.default.removeItem(at: selected)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        await store.retryVaultAccess()
        #expect(!store.isVaultInaccessible)
        #expect(store.vaultURL?.path == selected.path)
        #expect(store.canAddEvent)
    }

    @Test func selectClearsInaccessibleState() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let selected = temp.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let suite = try TestDefaults()
        defer { suite.clean() }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        _ = try location.select(selected)
        try FileManager.default.removeItem(at: selected)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        let next = temp.appendingPathComponent("next")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        await store.select(next)
        #expect(!store.isVaultInaccessible)
        #expect(store.vaultURL?.path == next.path)
        #expect(store.canAddEvent)
    }

    @Test func malformedBookmarkClearsBookmarkWithoutLocalVault() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadCorruptFile) }
        bookmarks.isMalformed = { _ in true }
        suite.defaults.set(Data("broken".utf8), forKey: "vaultBookmark")
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
        await store.retryVaultAccess()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
    }

    @Test func legacyDocumentsVaultStillOpensFromStore() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let vault = temp.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks()),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(!store.isVaultInaccessible)
        #expect(store.vaultURL?.path == vault.path)
        #expect(store.canAddEvent)
    }

    @Test func contentViewShowsInaccessibleBranch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(
            contentsOf: root.appendingPathComponent("App/ContentView.swift"), encoding: .utf8)
        #expect(content.contains("isVaultInaccessible"))
        let screen = try String(
            contentsOf: root.appendingPathComponent("App/Screens/Onboarding/VaultInaccessibleView.swift"),
            encoding: .utf8)
        #expect(screen.contains("retryVaultAccess"))
        #expect(screen.contains("Başka klasör seç") || screen.contains("fileImporter"))
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
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                let result = try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
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
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                let result = try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
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
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                await gate.hold()
                return try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
            })
        store.setForeground(true)
        await store.start()
        try await Task.sleep(for: .milliseconds(700))
        #expect(await gate.calls == 1)
        store.setForeground(false)
    }
}
