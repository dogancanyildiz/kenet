import Foundation

/// Result of opening the user's registered vault (or the legacy Documents/Vault).
enum VaultResolution: Equatable {
    case available(url: URL, notice: String?)
    /// Bookmark present but unusable, or bookmark was malformed and cleared — no vault opened.
    case inaccessible
}

/// Owns the selected folder's security scope for the lifetime of the app session.
@MainActor
final class VaultLocation {
    private let defaults: UserDefaults
    private let documentsURL: URL
    private let bookmarks: VaultBookmarks
    private var scopedURL: URL?
    private static let bookmarkKey = "vaultBookmark"

    init(defaults: UserDefaults = .standard, documentsURL: URL? = nil, bookmarks: VaultBookmarks = VaultBookmarks()) {
        self.defaults = defaults
        self.bookmarks = bookmarks
        self.documentsURL = documentsURL ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    var needsFirstLaunch: Bool {
        defaults.data(forKey: Self.bookmarkKey) == nil
            && !FileManager.default.fileExists(atPath: documentsURL.appendingPathComponent("Vault").path)
    }

    func resolve() throws -> VaultResolution {
        if defaults.data(forKey: Self.bookmarkKey) != nil {
            return try resolveSavedBookmark()
        }
        return .available(url: try createDefaultVault(), notice: nil)
    }

    /// Retries only the saved bookmark (or legacy Documents/Vault). Never creates a new local vault.
    func resolveSavedVault() throws -> VaultResolution {
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
            if bookmarks.isMalformed(data) { defaults.removeObject(forKey: Self.bookmarkKey) }
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
        if defaults.data(forKey: Self.bookmarkKey) != nil { return try resolveForBackground() }
        let root = documentsURL.appendingPathComponent("Vault", isDirectory: true)
        try validateDirectory(root)
        return root
    }

    func resolveForBackground() throws -> URL {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return try createDefaultVault() }
        let resolved = try bookmarks.resolve(data)
        try beginAccess(to: resolved.url)
        if resolved.isStale { defaults.set(try bookmarks.create(resolved.url), forKey: Self.bookmarkKey) }
        return resolved.url
    }

    func resumeBackgroundAccess(to expected: URL) throws {
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
            defaults.set(data, forKey: Self.bookmarkKey)
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
        if !VaultImportScanner.supportsSettings(at: root) { return root }
        for name in [".app"] + VaultImportReport.folders {
            _ = try VaultImportBootstrap.directory(name, root: root)
        }
        _ = try VaultImportBootstrap.file(".app/vault.json", bytes: Data("{ \"formatVersion\": 1 }\n".utf8), root: root)
        for kind in ["person", "place"] {
            _ = try VaultImportBootstrap.file(
                "templates/" + kind + ".md", bytes: VaultImportBootstrap.template(kind), root: root)
        }
        return root
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
