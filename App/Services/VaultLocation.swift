import Foundation

/// Result of opening the user's registered vault (or the legacy Documents/Vault).
enum VaultResolution: Equatable {
    case available(url: URL, notice: String?)
    /// Saved vault cannot be opened — no substitute vault is created.
    case inaccessible
}

/// Owns the selected folder's security scope for the lifetime of the app session.
@MainActor
final class VaultLocation {
    private let defaults: UserDefaults
    private let documentsURL: URL
    private let bookmarks: VaultBookmarks
    private var scopedURL: URL?
    private let ubiquity: any UbiquityContainerProviding
    private(set) var cloudContainerURL: URL?
    static let kindKey = "vaultKind"
    private static let migrationQuestionKey = "vaultMigrationQuestionAnswered"
    private static let migrationTemporaryKey = "vaultMigrationTemporaryName"

    enum Kind: String {
        case local, icloud, selected
    }

    var kind: Kind {
        if let value = defaults.string(forKey: Self.kindKey), let kind = Kind(rawValue: value) {
            return kind
        }
        return defaults.data(forKey: Self.bookmarkKey) == nil ? .local : .selected
    }

    var localRoot: URL { documentsURL.appendingPathComponent("Vault", isDirectory: true) }
    var retainedLocalVault: Bool { defaults.bool(forKey: "vaultRetainedLocalCopy") }

    func refreshCloudAvailability() async throws {
        cloudContainerURL = await ubiquity.containerURL()
    }

    func recoverInterruptedMigration() async throws {
        if let container = cloudContainerURL,
            let name = defaults.string(forKey: Self.migrationTemporaryKey),
            name.hasPrefix(".Kenet-tasima-"),
            UUID(uuidString: String(name.dropFirst(".Kenet-tasima-".count))) != nil
        {
            let temporary = container.appendingPathComponent("Documents").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: temporary.path) {
                try await Task.detached { try FileManager.default.removeItem(at: temporary) }.value
            }
            defaults.removeObject(forKey: Self.migrationTemporaryKey)
        }
    }

    var shouldOfferCloudMigration: Bool {
        cloudContainerURL != nil && canOfferCloudMigration
    }

    var canOfferCloudMigration: Bool {
        kind == .local && !hasLostSavedVault
            && defaults.data(forKey: Self.bookmarkKey) == nil
            && FileManager.default.fileExists(atPath: localRoot.path)
            && !defaults.bool(forKey: Self.migrationQuestionKey)
    }

    func declineCloudMigration() { defaults.set(true, forKey: Self.migrationQuestionKey) }

    func useLocalVault() throws -> URL {
        let root = try createDefaultVault()
        defaults.set(Kind.local.rawValue, forKey: Self.kindKey)
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.savedVaultLostKey)
        return root
    }

    /// Longest wait for another device's `.app/vault.json` before the user is asked to retry.
    static let cloudDownloadTimeout: Duration = .seconds(20)

    /// A vault whose settings file is still an iCloud placeholder is recognised and downloaded
    /// before anything opens it; on timeout nothing is created, moved or registered.
    private func awaitCloudVaultDownload(_ root: URL) async throws {
        guard CloudVaultMarker.at(root) == .awaitingDownload else { return }
        let app = root.appendingPathComponent(".app", isDirectory: true)
        let ready = try await ubiquity.download(
            [root, app], waitingFor: app.appendingPathComponent("vault.json"), timeout: Self.cloudDownloadTimeout)
        guard ready else { throw CloudVaultError.downloading }
    }

    func useCloudVault() async throws -> URL {
        guard let container = cloudContainerURL else { throw CocoaError(.fileReadNoPermission) }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try await awaitCloudVaultDownload(documents.appendingPathComponent("Kenet", isDirectory: true))
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let name = ".Kenet-tasima-" + UUID().uuidString
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<URL, any Error>?
        coordinator.coordinate(writingItemAt: documents, options: .forMerging, error: &coordinationError) {
            documents in
            outcome = Result {
                let root = documents.appendingPathComponent("Kenet", isDirectory: true)
                if FileManager.default.fileExists(atPath: root.path) {
                    switch CloudVaultMarker.at(root) {
                    case .present: break
                    case .awaitingDownload: throw CloudVaultError.downloading
                    case .absent: throw CocoaError(.fileReadUnknown)
                    }
                    try validateDirectory(root)
                } else {
                    let temporary = documents.appendingPathComponent(name, isDirectory: true)
                    defaults.set(name, forKey: Self.migrationTemporaryKey)
                    try bootstrapVault(at: temporary)
                    try FileManager.default.moveItem(at: temporary, to: root)
                    defaults.removeObject(forKey: Self.migrationTemporaryKey)
                }
                return root
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        let root = try outcome.get()
        registerCloudVault()
        return root
    }

    func migrateToCloud(deviceName: String, migration: VaultMigration = VaultMigration()) async throws
        -> VaultMigration.Result
    {
        guard kind == .local, let container = cloudContainerURL else {
            throw CocoaError(.fileReadNoPermission)
        }
        // Another device's vault is downloaded before the copy, so the vault opened afterwards
        // has its format version on disk.
        try await awaitCloudVaultDownload(container.appendingPathComponent("Documents/Kenet", isDirectory: true))
        let name = ".Kenet-tasima-" + UUID().uuidString
        defaults.removeObject(forKey: Self.migrationQuestionKey)
        defaults.set(name, forKey: Self.migrationTemporaryKey)
        let source = localRoot
        let result = try await Task.detached {
            try migration.copy(source: source, container: container, temporaryName: name, deviceName: deviceName)
        }.value
        guard await ubiquity.containerURL() == container else {
            throw CocoaError(.fileReadNoPermission)
        }
        registerCloudVault()
        defaults.set(true, forKey: "vaultRetainedLocalCopy")
        defaults.removeObject(forKey: Self.migrationTemporaryKey)
        declineCloudMigration()
        return result
    }

    private func registerCloudVault() {
        defaults.set(Kind.icloud.rawValue, forKey: Self.kindKey)
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.savedVaultLostKey)
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func resolveCloudVault() throws -> VaultResolution {
        guard let container = cloudContainerURL else { return .inaccessible }
        let root = container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        // Opening an existing registration never creates a replacement vault.
        do { try validateDirectory(root) } catch { return .inaccessible }
        return .available(url: root, notice: nil)
    }
    private static let bookmarkKey = "vaultBookmark"
    /// Set when a malformed bookmark is cleared so later launches do not open Documents/Vault.
    static let savedVaultLostKey = "savedVaultLost"

    init(
        defaults: UserDefaults = .standard, documentsURL: URL? = nil, bookmarks: VaultBookmarks = VaultBookmarks(),
        ubiquity: (any UbiquityContainerProviding)? = nil
    ) {
        self.ubiquity = ubiquity ?? Self.defaultUbiquityContainer()
        self.defaults = defaults
        self.bookmarks = bookmarks
        self.documentsURL = documentsURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func defaultUbiquityContainer(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> any UbiquityContainerProviding {
        if AppLaunchPolicy.allowsAutomaticStart(environment: environment, arguments: arguments) {
            return SystemUbiquityContainer()
        }
        return FakeUbiquityContainer(url: nil)
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    private var hasLostSavedVault: Bool { defaults.bool(forKey: Self.savedVaultLostKey) }

    var needsFirstLaunch: Bool {
        kind == .local && !hasLostSavedVault
            && defaults.data(forKey: Self.bookmarkKey) == nil
            && !FileManager.default.fileExists(atPath: documentsURL.appendingPathComponent("Vault").path)
    }

    func resolve() throws -> VaultResolution {
        if kind == .icloud { return try resolveCloudVault() }
        if kind == .selected, defaults.data(forKey: Self.bookmarkKey) == nil { return .inaccessible }
        if hasLostSavedVault { return .inaccessible }
        if defaults.data(forKey: Self.bookmarkKey) != nil {
            return try resolveSavedBookmark()
        }
        return .available(url: try createDefaultVault(), notice: nil)
    }

    /// Retries only the saved bookmark (or legacy Documents/Vault). Never creates a new local vault.
    func resolveSavedVault() throws -> VaultResolution {
        if kind == .icloud { return try resolveCloudVault() }
        if kind == .selected, defaults.data(forKey: Self.bookmarkKey) == nil { return .inaccessible }
        if hasLostSavedVault {
            if defaults.data(forKey: Self.bookmarkKey) != nil {
                return try resolveSavedBookmark()
            }
            return .inaccessible
        }
        if defaults.data(forKey: Self.bookmarkKey) != nil {
            return try resolveSavedBookmark()
        }
        let root = documentsURL.appendingPathComponent("Vault", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return .inaccessible }
        try beginAccess(to: root)
        return .available(url: root, notice: nil)
    }

    private func resolveSavedBookmark() throws -> VaultResolution {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return .inaccessible }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try bookmarks.resolve(data)
        } catch {
            // A missing disk or temporary resolver failure must not erase the user's choice.
            // Malformed bytes cannot be retried: clear them and remember the loss.
            if bookmarks.isMalformed(data) {
                defaults.removeObject(forKey: Self.bookmarkKey)
                defaults.set(true, forKey: Self.savedVaultLostKey)
            }
            return .inaccessible
        }
        do {
            try beginAccess(to: resolved.url)
        } catch {
            return .inaccessible
        }
        if resolved.isStale {
            do {
                defaults.set(try bookmarks.create(resolved.url), forKey: Self.bookmarkKey)
            } catch {
                return .available(
                    url: resolved.url,
                    notice: String(
                        localized:
                            "Klasör açıldı ancak yer imi yenilenemedi. Sonraki açılışta yeniden denenecek.")
                )
            }
        }
        return .available(url: resolved.url, notice: nil)
    }

    /// No fallback vault is substituted for an inaccessible bookmark during automation.
    func existingVaultForIntent() throws -> URL {
        if kind == .icloud { return try cloudURLForBackground() }
        if kind == .selected, defaults.data(forKey: Self.bookmarkKey) == nil {
            throw CocoaError(.fileReadNoPermission)
        }
        if hasLostSavedVault { throw CocoaError(.fileReadNoPermission) }
        if defaults.data(forKey: Self.bookmarkKey) != nil { return try resolveForBackground() }
        let root = documentsURL.appendingPathComponent("Vault", isDirectory: true)
        try validateDirectory(root)
        return root
    }

    func resolveForBackground() throws -> URL {
        if kind == .icloud { return try cloudURLForBackground() }
        if kind == .selected, defaults.data(forKey: Self.bookmarkKey) == nil {
            throw CocoaError(.fileReadNoPermission)
        }
        if hasLostSavedVault { throw CocoaError(.fileReadNoPermission) }
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return try createDefaultVault() }
        let resolved = try bookmarks.resolve(data)
        try beginAccess(to: resolved.url)
        if resolved.isStale { defaults.set(try bookmarks.create(resolved.url), forKey: Self.bookmarkKey) }
        return resolved.url
    }

    private func cloudURLForBackground() throws -> URL {
        guard case .available(let url, _) = try resolveCloudVault() else {
            throw CocoaError(.fileReadNoPermission)
        }
        return url
    }

    func resumeBackgroundAccess(to expected: URL) throws {
        if kind == .icloud {
            guard try cloudURLForBackground().standardizedFileURL == expected.standardizedFileURL else {
                throw CocoaError(.fileReadNoPermission)
            }
            return
        }
        if let data = defaults.data(forKey: Self.bookmarkKey) {
            let resolved = try bookmarks.resolve(data)
            guard resolved.url.standardizedFileURL == expected.standardizedFileURL else {
                throw CocoaError(.fileReadNoPermission)
            }
            try beginAccess(to: resolved.url)
            if resolved.isStale { defaults.set(try bookmarks.create(resolved.url), forKey: Self.bookmarkKey) }
        } else {
            try beginAccess(to: expected)
        }
    }

    func select(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            try validateDirectory(url)
            let data = try bookmarks.create(url)
            defaults.set(Kind.selected.rawValue, forKey: Self.kindKey)
            defaults.set(data, forKey: Self.bookmarkKey)
            defaults.removeObject(forKey: Self.savedVaultLostKey)
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = accessed ? url : nil
            return url
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func createDefaultVault() throws -> URL {
        let root = documentsURL.appendingPathComponent("Vault", isDirectory: true)
        try bootstrapVault(at: root)
        return root
    }

    private func bootstrapVault(at root: URL) throws {
        if !VaultImportScanner.supportsSettings(at: root) { return }
        for name in [".app"] + VaultImportReport.folders {
            _ = try VaultImportBootstrap.directory(name, root: root)
        }
        _ = try VaultImportBootstrap.file(".app/vault.json", bytes: Data("{ \"formatVersion\": 1 }\n".utf8), root: root)
        for kind in ["person", "place"] {
            _ = try VaultImportBootstrap.file(
                "templates/" + kind + ".md", bytes: VaultImportBootstrap.template(kind), root: root)
        }
    }

    private func beginAccess(to url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            try validateDirectory(url)
            scopedURL?.stopAccessingSecurityScopedResource()
            scopedURL = accessed ? url : nil
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func validateDirectory(_ url: URL) throws {
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
    }
}
