import Foundation

/// The complete access intent, including both endpoints of a move.
public enum FileCoordinationOperation: Sendable, Equatable {
    case read(URL)
    case modify(URL)
    case move(source: URL, destination: URL)
    /// Folds `source` into the existing file `into` and removes `source`: the target's presenters
    /// save first, the source's presenters give way to its deletion.
    case merge(source: URL, into: URL)
    case delete(URL)
}

/// What the accessor reports to the host while it still holds the boundary.
///
/// Only the accessor knows whether a move really happened; a host such as `NSFileCoordinator`
/// must announce it to file presenters from inside the same coordinated block.
public struct FileCoordinationAccess {
    private let willMove: (URL, URL) -> Void
    private let didMove: (URL, URL) -> Void

    public init(
        itemWillMove: @escaping (URL, URL) -> Void = { _, _ in },
        itemDidMove: @escaping (URL, URL) -> Void = { _, _ in }
    ) {
        willMove = itemWillMove
        didMove = itemDidMove
    }

    /// Called immediately before the move is attempted.
    public func itemWillMove(from source: URL, to destination: URL) { willMove(source, destination) }

    /// Called only after the move succeeded, never after a failed or restored one.
    public func itemDidMove(from source: URL, to destination: URL) { didMove(source, destination) }
}

/// A synchronous access boundary implemented by the host platform.
///
/// Implementations must invoke the accessor exactly once, on the calling thread, before returning,
/// or throw without invoking it when access is denied. Accessor errors must propagate unchanged.
/// The accessor holds the entire read/transform/write chain and the index update that follows the
/// write; it must not escape or start nested coordination. Readers injected into `VaultIndex` or
/// `VaultStore` therefore never coordinate. Core keeps using the URLs it requested.
public protocol FileCoordination: Sendable {
    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T
}

/// Preserves local filesystem behavior when the host supplies no coordinator.
public struct DirectFileCoordination: FileCoordination {
    public init() {}

    public func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        try accessor(FileCoordinationAccess())
    }
}
