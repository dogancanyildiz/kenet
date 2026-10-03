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

struct StoreRandom: RandomNumberGenerator {
    let nextValue: @Sendable () -> UInt64
    mutating func next() -> UInt64 { nextValue() }
}
