import Foundation

/// The on-disk outcome of a rename, including partial failures. Never repeat it blindly.
public struct RenameResult: Sendable, Equatable {
    public let path: String
    public let updatedFiles: [String]
    public let failures: [RenameFailure]
    public var hasPartialChange: Bool {
        failures.contains { if case .partialChange = $0.reason { true } else { false } }
    }
}

/// Why a frontmatter list could not be rewritten during rename.
public enum RenameListFailureReason: Sendable, Equatable {
    /// List item token ranges could not be matched back to the source bytes.
    case unmatchedTokens
    /// An unexpected error blocked the list rewrite.
    case unexpected
}

/// A file left partially or wholly unchanged, or an index publication failure.
public struct RenameFailure: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case rawField(String)
        case file(String)
        /// Frontmatter list at `key` could not be rewritten; body updates may still apply.
        case frontmatterList(key: String, reason: RenameListFailureReason)
        case index(String)
        case partialChange(String)
    }
    public let path: String
    public let reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}
