import Foundation

/// NSLock protects the registry; each root owns one serial Foundation operation queue.
final class VaultWriteQueues: @unchecked Sendable {
    static let shared = VaultWriteQueues()
    private let registryLock = NSLock()
    private var roots: [String: OperationQueue] = [:]

    func queue(for root: URL) -> OperationQueue {
        registryLock.withLock {
            let key = root.resolvingSymlinksInPath().standardizedFileURL.path
            if let queue = roots[key] { return queue }
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            roots[key] = queue
            return queue
        }
    }
}

/// Coordinated reads run here, never on the `VaultStore` actor or the write queue: a read the host
/// coordinator holds (an iCloud download can take long) blocks only one of these threads, while
/// writes and the other reads of the vault go on. Reads need no order among themselves, so each
/// root's queue runs a few at once; the bound keeps a run of blocked downloads from taking a
/// thread each.
final class VaultReadQueues: @unchecked Sendable {
    static let shared = VaultReadQueues()
    static let width = 4
    private let registryLock = NSLock()
    private var roots: [String: OperationQueue] = [:]

    func queue(for root: URL) -> OperationQueue {
        registryLock.withLock {
            let key = root.resolvingSymlinksInPath().standardizedFileURL.path
            if let queue = roots[key] { return queue }
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = Self.width
            roots[key] = queue
            return queue
        }
    }
}

struct StoreRandom: RandomNumberGenerator {
    let nextValue: @Sendable () -> UInt64
    mutating func next() -> UInt64 { nextValue() }
}
