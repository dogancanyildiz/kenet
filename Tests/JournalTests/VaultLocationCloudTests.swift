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

    /// Another device's vault as it first appears here: folders and iCloud placeholders only.
    func installPlaceholderCloudVault() throws -> URL {
        let root = container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        let app = root.appendingPathComponent(".app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: app.appendingPathComponent(".vault.json.icloud"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("journal/.2030-01-01.md.icloud"))
        return root
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

/// Stands in for iCloud's download: records each request and, when it delivers, swaps the
/// placeholder for the settings file as the system would.
actor DownloadingUbiquityContainer: UbiquityContainerProviding {
    static let settings = Data("{\"formatVersion\":1}".utf8)
    private var url: URL?
    private let delivers: Bool
    private(set) var requests: [URL] = []

    init(delivers: Bool) { self.delivers = delivers }
    func set(_ url: URL?) { self.url = url }
    func containerURL() async -> URL? { url }

    func download(_ items: [URL], waitingFor file: URL, timeout: Duration) async throws -> Bool {
        requests += items
        guard delivers else { return false }
        let app = file.deletingLastPathComponent()
        try FileManager.default.removeItem(at: app.appendingPathComponent(".vault.json.icloud"))
        try Self.settings.write(to: file)
        return true
    }
}

func samePath(_ lhs: URL?, _ rhs: URL) -> Bool {
    lhs?.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        == rhs.resolvingSymlinksInPath().standardizedFileURL.pathComponents
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
        let opened = try await context.location.useCloudVault()
        #expect(
            opened.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                == root.resolvingSymlinksInPath().standardizedFileURL.pathComponents)
        #expect(try Data(contentsOf: root.appendingPathComponent(".app/vault.json")) == bytes)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("templates").path))
    }

    @Test func placeholderCloudVaultIsDownloadedAndOpenedWithoutBootstrapping() async throws {
        let provider = DownloadingUbiquityContainer(delivers: true)
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        await provider.set(context.container)
        let root = try context.installPlaceholderCloudVault()
        await context.store.createCloudVault()
        #expect(context.store.errorText == nil)
        #expect(samePath(context.store.vaultURL, root))
        #expect(context.location.kind == .icloud)
        #expect(!context.store.isOpeningCloudVault)
        let requested = await provider.requests
        #expect(requested.count == 2)
        #expect(samePath(requested.first, root))
        #expect(samePath(requested.last, root.appendingPathComponent(".app")))
        // The downloaded settings stay as they arrived; nothing is bootstrapped over them.
        #expect(
            try Data(contentsOf: root.appendingPathComponent(".app/vault.json"))
                == DownloadingUbiquityContainer.settings)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("templates").path))
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("journal/.2030-01-01.md.icloud").path))
    }

    @Test func placeholderCloudVaultThatDoesNotArriveChangesNothing() async throws {
        let provider = DownloadingUbiquityContainer(delivers: false)
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        await provider.set(context.container)
        let root = try context.installPlaceholderCloudVault()
        let before = try FileManager.default.subpathsOfDirectory(atPath: context.container.path).sorted()
        await context.store.createCloudVault()
        let message = try #require(CloudVaultError.downloading.errorDescription)
        #expect(context.store.errorText?.contains(message) == true)
        #expect(await provider.requests.count == 2)
        #expect(context.location.kind == .local)
        #expect(context.store.vaultURL == nil)
        #expect(!context.store.isOpeningCloudVault)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: context.container.path).sorted() == before)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".app/vault.json").path))
        #expect(!FileManager.default.fileExists(atPath: context.location.localRoot.path))
    }

    @Test func missingCloudFolderIsNotReportedAsICloudOff() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        context.defaults.defaults.set("icloud", forKey: VaultLocation.kindKey)
        await context.store.start()
        #expect(context.store.isVaultInaccessible)
        // iCloud answered: the inaccessible screen names the missing folder, not a disabled iCloud.
        #expect(context.store.isCloudAvailable)
        #expect(context.location.kind == .icloud)
        #expect(
            !FileManager.default.fileExists(atPath: context.container.appendingPathComponent("Documents/Kenet").path))
    }

    @Test func unavailableCloudKeepsRegistrationAndDoesNotCreateLocalVault() async throws {
        let context = try CloudVaultContext(available: false)
        defer { context.clean() }
        context.defaults.defaults.set("icloud", forKey: VaultLocation.kindKey)
        await context.store.start()
        #expect(context.store.isVaultInaccessible)
        #expect(!context.store.isCloudAvailable)
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
