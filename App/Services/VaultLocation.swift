import Foundation

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

    func resolve() throws -> (url: URL, notice: String?) {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            return (try createDefaultVault(), nil)
        }
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try bookmarks.resolve(data)
        } catch {
            // A missing disk or temporary resolver failure must not erase the user's choice.
            if bookmarks.isMalformed(data) { defaults.removeObject(forKey: Self.bookmarkKey) }
            return try fallback()
        }
        do {
            try beginAccess(to: resolved.url)
        } catch {
            return try fallback()
        }
        if resolved.isStale {
            do {
                defaults.set(try bookmarks.create(resolved.url), forKey: Self.bookmarkKey)
            } catch {
                return (
                    resolved.url,
                    String(localized: "Klasör açıldı ancak yer imi yenilenemedi. Sonraki açılışta yeniden denenecek.")
                )
            }
        }
        return (resolved.url, nil)
    }

    /// No fallback vault is substituted for an inaccessible bookmark during automation.
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

    private func fallback() throws -> (url: URL, notice: String?) {
        (try createDefaultVault(), String(localized: "Kayıtlı klasöre erişilemedi. Yerel kasa açıldı."))
    }

    func createDefaultVault() throws -> URL {
        let root = documentsURL.appendingPathComponent("Vault", isDirectory: true)
        for name in [".app", "journal", "people", "places", "goals", "notes"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let settings = root.appendingPathComponent(".app/vault.json")
        if !FileManager.default.fileExists(atPath: settings.path) {
            try Data("{ \"formatVersion\": 1 }\n".utf8).write(to: settings, options: .atomic)
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
