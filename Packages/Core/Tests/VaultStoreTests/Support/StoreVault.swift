import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

let storeDate = CalendarDate("2026-09-27")!
let storePath = "journal/2026-09-27.md"

struct StoreVault: Sendable {
    let root: URL
    let index: VaultIndex
    let store: VaultStore

    init(
        sample: Bool = false, random: @escaping @Sendable () -> UInt64 = { 0 },
        linkFile: (@Sendable (URL, URL) throws -> Void)? = nil,
        readFile: (@Sendable (URL) throws -> Data)? = nil
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        if sample {
            try FileManager.default.copyItem(at: Fixtures.root().appendingPathComponent("vaults/sample"), to: root)
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        index = try VaultIndex()
        let reader = readFile ?? { try Data(contentsOf: $0) }
        if let linkFile {
            store = VaultStore(
                vaultRoot: root, index: index, randomValue: random, linkFile: linkFile, readFile: reader)
        } else if readFile != nil {
            store = VaultStore(
                vaultRoot: root, index: index, randomValue: random,
                linkFile: { try FileManager.default.linkItem(at: $0, to: $1) }, readFile: reader)
        } else {
            store = VaultStore(vaultRoot: root, index: index, randomValue: random)
        }
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

/// Counts Markdown reads through VaultStore's injectable file reader.
final class CountingReader: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func read(_ url: URL) throws -> Data {
        lock.withLock { urls.append(url) }
        return try Data(contentsOf: url)
    }

    func reset() {
        lock.withLock { urls = [] }
    }

    var count: Int {
        lock.withLock { urls.count }
    }

    func markdownPaths(under root: URL) -> [String] {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        return lock.withLock {
            urls.compactMap { url in
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/"), path.hasSuffix(".md") else { return nil }
                return String(path.dropFirst(rootPath.count + 1))
            }
        }
    }

    func markdownCount(under root: URL) -> Int {
        markdownPaths(under: root).count
    }
}

/// Collects SQL statements observed through GRDB's connection trace.
final class StatementLog: @unchecked Sendable {
    private let lock = NSLock()
    private var statements: [String] = []

    func append(_ text: String) {
        lock.withLock { statements.append(text) }
    }

    func reset() {
        lock.withLock { statements = [] }
    }

    var all: [String] {
        lock.withLock { statements }
    }

    /// INSERT / UPDATE / DELETE that touch source-derived index tables (not type-state bookkeeping).
    var contentMutations: [String] {
        all.filter { statement in
            let upper = statement.uppercased()
            let isMutation =
                upper.contains("INSERT") || upper.contains("UPDATE") || upper.contains("DELETE")
            guard isMutation else { return false }
            if upper.contains("ENTITY_TYPE_STATE") { return false }
            if upper.contains("TEMP.") || upper.contains("TEMP ") { return false }
            return true
        }
    }
}
