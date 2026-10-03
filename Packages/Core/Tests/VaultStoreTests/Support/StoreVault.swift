import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

let storeDate = CalendarDate("2026-09-27")!
let storePath = "journal/2026-09-27.md"

struct StoreVault: Sendable {
    let root: URL
    let index: VaultIndex
    let store: VaultStore

    init(sample: Bool = false, random: @escaping @Sendable () -> UInt64 = { 0 }) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if sample {
            try FileManager.default.copyItem(at: Fixtures.root().appendingPathComponent("vaults/sample"), to: root)
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        index = try VaultIndex()
        store = VaultStore(vaultRoot: root, index: index, randomValue: random)
        try index.rebuild(vaultRoot: root)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func bytes(_ path: String = storePath) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    func check() throws { try equivalent(index, root) }
}

/// Locked deterministic random state can be shared with a Sendable store closure.
final class CountingRandom: @unchecked Sendable {
    private let lock = NSLock()
    private var count: UInt64 = 0
    func next() -> UInt64 {
        lock.withLock {
            defer { count += 1 }
            return count / 6
        }
    }
}
