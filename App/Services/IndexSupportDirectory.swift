import Foundation

/// Prepares the disposable SQLite index directory under Application Support.
enum IndexSupportDirectory {
    /// Creates `url` if needed, excludes it from device backup, and applies the chosen
    /// data-protection class where the platform supports it.
    static func prepare(
        at url: URL,
        fileManager: FileManager = .default,
        applyProtection: (URL) throws -> Void = applyDefaultProtection
    ) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        var resourceURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resourceURL.setResourceValues(values)
        try applyProtection(url)
    }

    /// CompleteUntilFirstUserAuthentication: background refresh, notification actions, and
    /// geofence writes must run before the user unlocks again. Stricter `.complete` blocks that.
    ///
    /// Uses `FileManager` attributes because `URLResourceValues.fileProtection` is get-only on
    /// current iOS SDKs. The app entitlement sets the same default for the container.
    static func applyDefaultProtection(_ url: URL) throws {
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
        #else
            _ = url
        #endif
    }
}
