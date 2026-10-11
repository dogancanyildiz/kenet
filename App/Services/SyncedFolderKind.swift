import Foundation

/// Classification of known synchronized cloud storage providers.
enum SyncedFolderKind: Sendable, Equatable, CaseIterable {
    case iCloudDrive
    case dropbox
    case oneDrive
    case googleDrive
    case fileProvider

    /// Detects whether the folder at the given path is located in a synced cloud storage provider.
    ///
    /// - Parameters:
    ///   - path: The filesystem path string to inspect.
    ///   - isUbiquitous: Whether the item is flagged as ubiquitous (stored in iCloud).
    ///                   Pass `true` when `NSURLIsUbiquitousItemKey` is true (e.g. iCloud Desktop/Documents).
    /// - Returns: The detected `SyncedFolderKind`, or `nil` if not in a known synced folder.
    static func detect(path: String, isUbiquitous: Bool?) -> SyncedFolderKind? {
        if isUbiquitous == true {
            return .iCloudDrive
        }

        if let kind = matchPath(path) {
            return kind
        }

        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            let resolved =
                destination.hasPrefix("/")
                ? destination
                : URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(destination).path
            if let kind = matchPath(resolved) {
                return kind
            }
        }

        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if resolved != path, let kind = matchPath(resolved) {
            return kind
        }

        return nil
    }

    /// Convenience overload when `isUbiquitous` flag is unknown.
    static func detect(path: String) -> SyncedFolderKind? {
        detect(path: path, isUbiquitous: nil)
    }

    /// Thin adapter reading `isUbiquitousItemKey` from the URL, falling back to path-only inspection on failure.
    static func detect(url: URL) -> SyncedFolderKind? {
        let isUbiquitous = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
        return detect(path: url.path, isUbiquitous: isUbiquitous)
    }

    private static func matchPath(_ rawPath: String) -> SyncedFolderKind? {
        guard !rawPath.isEmpty else { return nil }

        let normalized =
            rawPath
            .precomposedStringWithCanonicalMapping
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        let normalizedWithSlash = normalized.hasSuffix("/") ? normalized : normalized + "/"

        // iCloud Drive: Library/Mobile Documents/ or com~apple~CloudDocs
        if normalizedWithSlash.contains("library/mobile documents/")
            || normalized.contains("com~apple~clouddocs")
        {
            return .iCloudDrive
        }

        // Dropbox: Library/CloudStorage/Dropbox...
        if normalized.contains("library/cloudstorage/dropbox") {
            return .dropbox
        }

        // OneDrive: Library/CloudStorage/OneDrive-...
        if normalized.contains("library/cloudstorage/onedrive-")
            || normalizedWithSlash.contains("library/cloudstorage/onedrive/")
        {
            return .oneDrive
        }

        // Google Drive: Library/CloudStorage/GoogleDrive-...
        if normalized.contains("library/cloudstorage/googledrive-")
            || normalizedWithSlash.contains("library/cloudstorage/googledrive/")
        {
            return .googleDrive
        }

        // File Provider: File Provider Storage (iOS / macOS FileProvider)
        if normalized.contains("file provider storage") {
            return .fileProvider
        }

        return nil
    }
}
