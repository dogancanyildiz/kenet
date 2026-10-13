import Foundation
import VaultStore

/// Hosts Core's coordination boundary on `NSFileCoordinator`, so iCloud Drive and other file
/// presenters see each read, read-transform-write chain and rename as one claim.
///
/// Every call is synchronous and runs the accessor on the calling thread (the vault write queue).
/// The asynchronous `coordinate(with:queue:byAccessor:)` is never used: waiting for it from the
/// write queue deadlocks. No file presenter is attached yet; a future one must not use the vault
/// write queue as its `presentedItemOperationQueue`, and the index never gets a coordinating reader
/// because its update already runs inside the write's claim.
struct SystemFileCoordination: FileCoordination {
    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        // Presenters learn of a move only from the coordinator holding the claim.
        let access = FileCoordinationAccess(
            itemWillMove: { coordinator.item(at: $0, willMoveTo: $1) },
            itemDidMove: { coordinator.item(at: $0, didMoveTo: $1) })
        var outcome: Result<T, any Error>?
        var denied: NSError?
        // The coordinator's `newURL` is ignored: Core keeps using the URLs it requested.
        switch operation {
        case .read(let url):
            coordinator.coordinate(readingItemAt: url, options: [], error: &denied) { _ in
                outcome = Result { try accessor(access) }
            }
        case .modify(let url):
            // Presenters save first: the accessor reads the current bytes and merges into them.
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &denied) { _ in
                outcome = Result { try accessor(access) }
            }
        case .move(let source, let destination):
            // The source is a plain file whose bytes are rewritten before the move: `.forMoving`
            // has no effect on a plain file and the options are exclusive, so `.forMerging` lets its
            // presenters save first. The destination is a new item that replaces anything in its way,
            // unless it already is the source (a case-only rename on a case-insensitive volume):
            // replacing would ask the source's own presenters to accommodate its deletion.
            let replacing: NSFileCoordinator.WritingOptions = Self.isSameItem(source, destination) ? [] : .forReplacing
            coordinator.coordinate(
                writingItemAt: source, options: .forMerging, writingItemAt: destination, options: replacing,
                error: &denied
            ) { _, _ in
                outcome = Result { try accessor(access) }
            }
        case .merge(let source, let target):
            // The source is read and then removed: its presenters give way to the deletion. The
            // target is rewritten from its current bytes: its presenters save first.
            coordinator.coordinate(
                writingItemAt: source, options: .forDeleting, writingItemAt: target, options: .forMerging,
                error: &denied
            ) { _, _ in
                outcome = Result { try accessor(access) }
            }
        case .delete(let url):
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &denied) { _ in
                outcome = Result { try accessor(access) }
            }
        }
        if let outcome { return try outcome.get() }
        throw denied ?? CocoaError(.fileWriteUnknown)
    }

    /// Whether both URLs name one existing file system item.
    private static func isSameItem(_ first: URL, _ second: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let one = try? first.resourceValues(forKeys: key).fileResourceIdentifier,
            let other = try? second.resourceValues(forKeys: key).fileResourceIdentifier
        else { return false }
        return one.isEqual(other)
    }
}
