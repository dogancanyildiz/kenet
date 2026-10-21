import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct CloudVaultContext {
    let directory: URL
    let defaults: TestDefaults
    let container: URL
    let location: VaultLocation
    let store: IndexStore

    init(available: Bool = true, ubiquity: (any UbiquityContainerProviding)? = nil) throws {
        directory = try testDirectory()
        defaults = try TestDefaults()
        container = directory.appendingPathComponent("Cloud")
        location = VaultLocation(
            defaults: defaults.defaults, documentsURL: directory,
            bookmarks: pathBookmarks(),
            ubiquity: ubiquity ?? FakeUbiquityContainer(url: available ? container : nil))
        store = IndexStore(location: location, supportURL: directory.appendingPathComponent("indexes"))
    }

    func installLocalSample() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/vaults/sample")
        try FileManager.default.copyItem(at: fixture, to: location.localRoot)
    }

    func clean() {
        store.setForeground(false)
        try? FileManager.default.removeItem(at: directory)
        defaults.clean()
    }
}

private actor CountingUbiquityContainer: UbiquityContainerProviding {
    private(set) var calls = 0
    func containerURL() async -> URL? {
        calls += 1
        return nil
    }
}

private actor SwitchingUbiquityContainer: UbiquityContainerProviding {
    private var url: URL?
    func set(_ url: URL?) { self.url = url }
    func containerURL() async -> URL? { url }
}

@MainActor
struct VaultLocationCloudTests {
    @Test func cloudRegistrationResolvesFreshContainerWithoutBookmark() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        await context.store.createCloudVault()
        let expected = context.container.appendingPathComponent("Documents/Kenet")
        #expect(context.store.vaultURL?.standardizedFileURL == expected.standardizedFileURL)
        #expect(context.location.kind == .icloud)
        #expect(context.defaults.defaults.data(forKey: "vaultBookmark") == nil)
        let relocated = context.directory.appendingPathComponent("OtherCloud")
        try FileManager.default.copyItem(at: context.container, to: relocated)
        let next = VaultLocation(
            defaults: context.defaults.defaults, documentsURL: context.directory,
            ubiquity: FakeUbiquityContainer(url: relocated))
        #expect(!next.needsFirstLaunch)
        try await next.refreshCloudAvailability()
        #expect(
            try next.resolve()
                == .available(
                    url: relocated.appendingPathComponent("Documents/Kenet"), notice: nil))
    }

    @Test func existingCloudVaultIsOpenedWithoutBootstrapping() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        let root = context.container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".app"), withIntermediateDirectories: true)
        let bytes = Data("{ \"formatVersion\": 99 }\n".utf8)
        try bytes.write(to: root.appendingPathComponent(".app/vault.json"))
        try await context.location.refreshCloudAvailability()
        let opened = try context.location.useCloudVault()
        #expect(
            opened.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                == root.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
        #expect(try Data(contentsOf: root.appendingPathComponent(".app/vault.json")) == bytes)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("templates").path))
    }

    @Test func unavailableCloudKeepsRegistrationAndDoesNotCreateLocalVault() async throws {
        let context = try CloudVaultContext(available: false)
        defer { context.clean() }
        context.defaults.defaults.set("icloud", forKey: VaultLocation.kindKey)
        await context.store.start()
        #expect(context.store.isVaultInaccessible)
        #expect(!context.store.canAddEvent)
        #expect(context.location.kind == .icloud)
        #expect(!FileManager.default.fileExists(atPath: context.location.localRoot.path))
        await context.store.retryVaultAccess()
        #expect(context.store.isVaultInaccessible)
        #expect(context.location.kind == .icloud)
    }

    @Test func accountLossClosesWriterAndRetryReopensTheSameVault() async throws {
        let provider = SwitchingUbiquityContainer()
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        await provider.set(context.container)
        await context.store.createCloudVault()
        let root = try #require(context.store.vaultURL)
        let file = root.appendingPathComponent(".app/vault.json")
        let before = try Data(contentsOf: file)
        await provider.set(nil)
        try await context.store.refreshCloudAvailability()
        #expect(context.store.isVaultInaccessible)
        #expect(!context.store.canAddEvent)
        #expect(context.store.vaultURL == nil)
        #expect(context.location.kind == .icloud)
        #expect(try Data(contentsOf: file) == before)
        #expect(!FileManager.default.fileExists(atPath: context.location.localRoot.path))
        await provider.set(context.container)
        await context.store.retryVaultAccess()
        #expect(context.store.vaultURL == root)
        #expect(context.store.canAddEvent)
        #expect(context.store.lastUpdated != nil)
    }

    @Test func identityIsRequiredEvenWhenContainerLookupSucceeds() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        let url = context.container
        let provider = SystemUbiquityContainer(hasIdentity: { false }, lookup: { url })
        #expect(await provider.containerURL() == nil)
    }

    @Test func systemLookupRunsOutsideTheMainThread() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        let url = context.container
        let provider = SystemUbiquityContainer(
            hasIdentity: { !Thread.isMainThread }, lookup: { Thread.isMainThread ? nil : url })
        #expect(await provider.containerURL() == url)
    }

    @Test func unavailableRegistrationPreservesExistingBytesAndExplicitLocalChoiceWorks() async throws {
        let context = try CloudVaultContext(available: false)
        defer { context.clean() }
        try context.installLocalSample()
        let file = context.location.localRoot.appendingPathComponent("journal/2026-09-20.md")
        let before = try Data(contentsOf: file)
        context.defaults.defaults.set("icloud", forKey: VaultLocation.kindKey)
        await context.store.start()
        #expect(context.location.kind == .icloud)
        #expect(try Data(contentsOf: file) == before)
        await context.store.continueLocally()
        #expect(context.location.kind == .local)
        #expect(!context.store.isVaultInaccessible)
        #expect(context.store.lastUpdated != nil)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func existingLocalVaultOpensBeforeMigrationQuestionAndSecondStartDoesNotAskAgain() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        await context.store.start()
        #expect(context.store.vaultURL == context.location.localRoot)
        #expect(context.store.lastUpdated != nil)
        #expect(context.store.counts.events == 40)
        #expect(context.store.showsCloudMigration)
        #expect(!context.store.requiresOnboarding)
        context.store.showsCloudMigration = false
        await context.store.start()
        #expect(!context.store.showsCloudMigration)
        #expect(context.store.vaultURL == context.location.localRoot)
    }

    @Test func localAndSelectedBackgroundPathsDoNotLookUpCloud() async throws {
        let provider = CountingUbiquityContainer()
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        try context.installLocalSample()
        context.location.declineCloudMigration()
        await context.store.start()
        try await context.store.prepareForIntent()
        try await context.store.prepareForBackground()
        await context.store.retryVaultAccess()
        #expect(await provider.calls == 0)
        _ = try context.location.select(context.location.localRoot)
        try await context.store.prepareForIntent()
        try await context.store.prepareForBackground()
        await context.store.retryVaultAccess()
        #expect(await provider.calls == 0)
        #expect(context.store.lastUpdated != nil)
    }

    @Test func defaultProviderIsUnavailableInTestProcesses() async throws {
        for environment in [
            ["XCTestConfigurationFilePath": "/fictional/test.xctestconfiguration"],
            ["JOURNAL_NO_AUTOSTART": "1"],
            ["JOURNAL_UITEST_VAULT": "/fictional/sample"],
        ] {
            let provider = VaultLocation.defaultUbiquityContainer(environment: environment, arguments: [])
            try #require(provider is FakeUbiquityContainer)
            #expect(await provider.containerURL() == nil)
        }

    }

    @Test func migrationQuestionIsOnlyForDefaultLocalVaultAndOnlyOnce() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        await context.store.start()
        #expect(context.store.showsCloudMigration)
        #expect(context.store.vaultURL == context.location.localRoot)
        await context.store.continueLocally()
        #expect(!context.store.showsCloudMigration)
        let next = VaultLocation(
            defaults: context.defaults.defaults, documentsURL: context.directory,
            bookmarks: pathBookmarks(), ubiquity: FakeUbiquityContainer(url: context.container))
        try await next.refreshCloudAvailability()
        #expect(!next.shouldOfferCloudMigration)
        // A folder bookmark, including one to Documents/Vault, is the user's own choice.
        _ = try context.location.select(context.location.localRoot)
        context.defaults.defaults.removeObject(forKey: "vaultMigrationQuestionAnswered")
        #expect(!context.location.shouldOfferCloudMigration)
    }
}
