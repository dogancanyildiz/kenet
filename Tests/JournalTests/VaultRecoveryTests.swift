import Foundation
import Testing
import VaultStore

@testable import Journal

@MainActor
struct VaultRecoveryTests {
    @Test func automaticStartupLeavesVaultUntouched() async throws {
        try await expectAutomaticStartBlocked(environment: ["XCTestConfigurationFilePath": "test"], arguments: [])
        try await expectAutomaticStartBlocked(environment: [:], arguments: ["JOURNAL_NO_AUTOSTART"])
        try await expectAutomaticStartBlocked(environment: ["JOURNAL_NO_AUTOSTART": "1"], arguments: [])
        #expect(AppLaunchPolicy.allowsAutomaticStart(environment: [:], arguments: []))
    }

    @Test func uiTestVaultDisablesAutomaticStartWithoutOpeningDefaultVault() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let path = temp.appendingPathComponent("ui-test-vault").path
        #expect(AppLaunchPolicy.uiTestVaultPath(environment: ["JOURNAL_UITEST_VAULT": path], arguments: []) == path)
        #expect(
            AppLaunchPolicy.uiTestVaultPath(environment: [:], arguments: ["JOURNAL_UITEST_VAULT=" + path]) == path)
        #expect(!AppLaunchPolicy.allowsAutomaticStart(environment: ["JOURNAL_UITEST_VAULT": path], arguments: []))
        try await expectAutomaticStartBlocked(environment: ["JOURNAL_UITEST_VAULT": path], arguments: [])
        try await expectAutomaticStartBlocked(environment: [:], arguments: ["JOURNAL_UITEST_VAULT=" + path])
    }

    private func expectAutomaticStartBlocked(environment: [String: String], arguments: [String]) async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let documents = temp.appendingPathComponent("documents", isDirectory: true)
        let indexes = temp.appendingPathComponent("indexes", isDirectory: true)
        let saved = Data(temp.path.utf8)
        suite.defaults.set(saved, forKey: "vaultBookmark")
        let before = try #require(suite.defaults.persistentDomain(forName: suite.name))
        var resolutionAttempts = 0
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in
            resolutionAttempts += 1
            // Fail closed even if the launch guard regresses; no vault is opened by this test.
            throw CocoaError(.fileReadNoPermission)
        }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: documents, bookmarks: bookmarks)
        let store = IndexStore(location: location, supportURL: indexes)
        // A saved bookmark bypasses onboarding, so only the launch policy blocks startup.
        #expect(!store.requiresOnboarding)
        // startAutomatically awaits start(); its return is the synchronization boundary.
        await store.startAutomatically(environment: environment, arguments: arguments)
        #expect(resolutionAttempts == 0)
        #expect(store.vaultURL == nil)
        #expect(!store.isProcessing)
        #expect(!store.isVaultInaccessible)
        #expect(store.errorText == nil)
        let after = try #require(suite.defaults.persistentDomain(forName: suite.name))
        #expect(NSDictionary(dictionary: after) == NSDictionary(dictionary: before))
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path).isEmpty)
        // Positive control: this exact store attempts resolution when startup is allowed.
        await store.startAutomatically(environment: [:], arguments: [])
        #expect(resolutionAttempts == 1)
        #expect(store.isVaultInaccessible)
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

    /// Path A: two automatic starts must not open Documents/Vault after a malformed bookmark.
    @Test func doubleAutomaticStartWithMalformedBookmarkStaysInaccessible() async throws {
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
        await store.startAutomatically(environment: [:], arguments: [])
        await store.startAutomatically(environment: [:], arguments: [])
        #expect(store.vaultURL == nil)
        #expect(store.isVaultInaccessible)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
        #expect(!store.requiresOnboarding)
        #expect(suite.defaults.bool(forKey: "savedVaultLost"))
    }

    /// Path B: a later launch with Documents/Vault present still stays inaccessible when the lost flag is set.
    @Test func freshStoreWithLostFlagAndLocalVaultStaysInaccessible() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadCorruptFile) }
        bookmarks.isMalformed = { _ in true }
        suite.defaults.set(Data("broken".utf8), forKey: "vaultBookmark")
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let first = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes-a"))
        await first.start()
        #expect(first.isVaultInaccessible)
        #expect(suite.defaults.bool(forKey: "savedVaultLost"))
        let vault = temp.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let second = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks()),
            supportURL: temp.appendingPathComponent("indexes-b"))
        await second.start()
        #expect(second.isVaultInaccessible)
        #expect(second.vaultURL == nil)
        #expect(!second.requiresOnboarding)
        #expect(!second.canAddEvent)
    }

    /// Path C: retry must not open an existing Documents/Vault after a lost saved vault.
    @Test func retryWithLocalVaultPresentDoesNotOpenItWhenSavedVaultLost() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadCorruptFile) }
        bookmarks.isMalformed = { _ in true }
        suite.defaults.set(Data("broken".utf8), forKey: "vaultBookmark")
        let vault = temp.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        await store.retryVaultAccess()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(store.errorText != nil)
    }

    /// Path B (background): lost flag alone must block resolveForBackground scaffolding even before start().
    @Test func prepareForBackgroundWithLostFlagDoesNotCreateLocalVault() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        suite.defaults.set(true, forKey: "savedVaultLost")
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        #expect(throws: CocoaError.self) { try location.resolveForBackground() }
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await #expect(throws: CocoaError.self) {
            try await store.prepareForBackground()
        }
        #expect(
            !FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault/.app/vault.json").path))
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
    }

    /// After choosing another folder, the lost flag clears and a later launch opens that vault.
    @Test func selectClearsLostFlagAndNextLaunchOpensSelection() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadCorruptFile) }
        bookmarks.isMalformed = { _ in true }
        suite.defaults.set(Data("broken".utf8), forKey: "vaultBookmark")
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let first = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes-a"))
        await first.start()
        #expect(suite.defaults.bool(forKey: "savedVaultLost"))
        let next = temp.appendingPathComponent("chosen")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        await first.select(next)
        #expect(!suite.defaults.bool(forKey: "savedVaultLost"))
        #expect(first.vaultURL?.path == next.path)
        let second = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks()),
            supportURL: temp.appendingPathComponent("indexes-b"))
        await second.start()
        #expect(!second.isVaultInaccessible)
        #expect(second.vaultURL?.path == next.path)
    }

    /// Renamed from malformedBookmarkClearsBookmarkWithoutLocalVault; also covers Documents/Vault present.
    @Test func malformedBookmarkMarksLostWithoutOpeningLocalVaultEvenWhenPresent() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        var bookmarks = pathBookmarks()
        bookmarks.resolve = { _ in throw CocoaError(.fileReadCorruptFile) }
        bookmarks.isMalformed = { _ in true }
        suite.defaults.set(Data("broken".utf8), forKey: "vaultBookmark")
        let vault = temp.appendingPathComponent("Vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: bookmarks)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(suite.defaults.data(forKey: "vaultBookmark") == nil)
        #expect(suite.defaults.bool(forKey: "savedVaultLost"))
        #expect(!store.requiresOnboarding)
        await store.retryVaultAccess()
        #expect(store.isVaultInaccessible)
        #expect(store.vaultURL == nil)
        #expect(store.errorText != nil)
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

    @Test func appRootScreenPrefersInaccessibleOverMain() {
        #expect(AppRootScreen.resolve(requiresOnboarding: true, isVaultInaccessible: false) == .onboarding)
        #expect(AppRootScreen.resolve(requiresOnboarding: true, isVaultInaccessible: true) == .onboarding)
        #expect(AppRootScreen.resolve(requiresOnboarding: false, isVaultInaccessible: true) == .vaultInaccessible)
        #expect(AppRootScreen.resolve(requiresOnboarding: false, isVaultInaccessible: false) == .main)
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
