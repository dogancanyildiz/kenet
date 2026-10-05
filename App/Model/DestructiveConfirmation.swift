import Foundation

/// Two-step confirmation for irreversible deletes (event, task, field, goal record).
///
/// Chosen over a timed "Undo" banner so every screen shares one pattern that works the same
/// on iPhone and Mac, matching the existing entity-type delete dialog.
struct DestructiveConfirmation<Target: Equatable>: Equatable {
    private(set) var pending: Target?

    var isPending: Bool { pending != nil }

    mutating func request(_ target: Target) {
        pending = target
    }

    mutating func cancel() {
        pending = nil
    }

    /// Clears pending and returns the confirmed target, or `nil` if nothing was pending.
    mutating func confirm() -> Target? {
        defer { pending = nil }
        return pending
    }
}

/// Token when the pending action needs no payload (single delete control on a screen).
enum DestructiveConfirmationToken: Equatable {
    case pending
}
