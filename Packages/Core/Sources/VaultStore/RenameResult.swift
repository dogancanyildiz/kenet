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

/// A file left partially or wholly unchanged, or an index publication failure.
public struct RenameFailure: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case rawField(String)
        case file(String)
        case index(String)
        case partialChange(String)
    }
    public let path: String
    public let reason: Reason
}
