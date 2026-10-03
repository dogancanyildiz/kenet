import Foundation

/// Store failures; format and filesystem errors otherwise retain their original type.
public enum VaultStoreError: Error, Sendable, Equatable {
    /// The target is stale, or a day-file creation collision persisted after one retry.
    case staleTarget
    /// A filename with the same comparison key already exists in the vault.
    case nameTaken
    /// The name or qualifier is empty, multiline, contains controls or exceeds the filename byte limit.
    case invalidName
    /// The requested path is outside the vault, hidden, reserved or a symbolic link.
    case invalidPath
    /// The file was written successfully; only index updating failed. Do not repeat the write.
    case indexUpdateFailed(path: String, underlying: any Error)

    /// Compares wrapped failures using their NSError representation.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.staleTarget, .staleTarget), (.nameTaken, .nameTaken), (.invalidName, .invalidName),
            (.invalidPath, .invalidPath):
            return true
        case (.indexUpdateFailed(let leftPath, let leftError), .indexUpdateFailed(let rightPath, let rightError)):
            return leftPath == rightPath && (leftError as NSError) == (rightError as NSError)
        default: return false
        }
    }
}

/// The entity kinds supported by the store.
public enum VaultEntityKind: String, Sendable {
    /// A person stored under people/.
    case person
    /// A place stored under places/.
    case place

    var directory: String { self == .person ? "people" : "places" }
}
