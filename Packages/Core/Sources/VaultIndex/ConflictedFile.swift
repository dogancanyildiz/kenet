import Foundation

/// A vault file for which the sync service keeps unresolved conflicting versions beside the
/// current one. The app lists these and changes nothing: no version is merged, kept or removed.
public struct ConflictedFile: Sendable, Hashable {
    /// The file's vault-relative path, NFC, such as `journal/2026-10-02.md`.
    public let path: String
    /// The conflicting versions; `sorted(_:)` puts the newest first.
    public let versions: [ConflictVersion]

    public init(path: String, versions: [ConflictVersion]) {
        self.path = path.precomposedStringWithCanonicalMapping
        self.versions = versions
    }

    /// Files in path byte order, each with its versions newest first.
    public static func sorted(_ files: [ConflictedFile]) -> [ConflictedFile] {
        files.map { ConflictedFile(path: $0.path, versions: ConflictVersion.newestFirst($0.versions)) }
            .sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
    }
}

/// One conflicting version as the sync service describes it.
public struct ConflictVersion: Sendable, Hashable {
    /// Whole seconds since 1970 in UTC when the version was saved; 0 when unknown.
    public let modificationTime: Int
    /// The name of the device that saved the version, when the service knows it.
    public let deviceName: String?

    public init(modificationTime: Int, deviceName: String?) {
        self.modificationTime = modificationTime
        self.deviceName = deviceName
    }

    /// Newest first; versions saved in the same second follow device name byte order, unnamed last.
    public static func newestFirst(_ versions: [ConflictVersion]) -> [ConflictVersion] {
        versions.sorted { lhs, rhs in
            if lhs.modificationTime != rhs.modificationTime { return lhs.modificationTime > rhs.modificationTime }
            switch (lhs.deviceName, rhs.deviceName) {
            case (let left?, let right?): return left.utf8.lexicographicallyPrecedes(right.utf8)
            case (.some, nil): return true
            default: return false
            }
        }
    }
}
