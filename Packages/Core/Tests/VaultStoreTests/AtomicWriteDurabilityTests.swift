import Foundation
import Testing

@testable import VaultStore

/// The temporary sibling is flushed to disk before any name points at it, and that flushed file is the one
/// published, so an interrupted write leaves either the old bytes or the complete new bytes.
struct AtomicWriteDurabilityTests {
    private static let path = "people/Deniz Arıkan.md"
    private static let newBytes = Data("---\ntype: person\nname: Deniz Arıkan\n---\nSu\n".utf8)

    /// `replace` overwrites an existing file; `link` creates by hard link; `rename` creates on a volume
    /// without hard links, where an exclusive rename publishes the file.
    @Test(arguments: ["replace", "link", "rename"])
    func publishedFileIsTheSynchronizedTemporary(publishing: String) throws {
        let vault = try Self.vault(hardLinks: publishing != "rename")
        defer { vault.remove() }
        if publishing == "replace" { try vault.write(Self.path, "Kitap") }
        let url = vault.root.appendingPathComponent(Self.path)
        var synchronized: [FileSnapshot] = []
        try vault.store.atomicWrite(
            Self.newBytes, to: url, exclusive: publishing != "replace",
            synchronize: { handle in
                synchronized.append(try FileSnapshot(directory: url.deletingLastPathComponent(), destination: url))
                try handle.synchronize()
            })
        try #require(synchronized.count == 1)
        let snapshot = synchronized[0]
        #expect(snapshot.temporaries.count == 1)
        #expect(snapshot.temporaries.first?.bytes == Self.newBytes)
        #expect(snapshot.destination == (publishing == "replace" ? Data("Kitap".utf8) : nil))
        #expect(try vault.bytes(Self.path) == Self.newBytes)
        #if canImport(Darwin)
            // The destination is the very inode that was flushed, not a second, unsynchronized copy.
            #expect(try fileNumber(url) == snapshot.temporaries.first?.fileNumber)
        #endif
        #expect(try temporaries(in: vault.root).isEmpty)
    }

    @Test(arguments: ["replace", "link", "rename"])
    func failedSynchronizationPublishesNothing(publishing: String) throws {
        let links = Attempts()
        let vault = try Self.vault(hardLinks: publishing != "rename", links: links)
        defer { vault.remove() }
        if publishing == "replace" { try vault.write(Self.path, "Kitap") }
        let url = vault.root.appendingPathComponent(Self.path)
        let renames = Attempts()
        #expect(throws: CocoaError(.fileWriteUnknown)) {
            try vault.store.atomicWrite(
                Self.newBytes, to: url, exclusive: publishing != "replace",
                synchronize: { _ in throw CocoaError(.fileWriteUnknown) },
                renameExclusively: { source, destination in
                    renames.tick()
                    try renameWithoutReplacing(source, destination)
                })
        }
        #expect(links.count == 0)
        #expect(renames.count == 0)
        if publishing == "replace" {
            #expect(try vault.bytes(Self.path) == Data("Kitap".utf8))
        } else {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(try temporaries(in: vault.root).isEmpty)
    }

    @Test func exclusiveRenameNeverReplacesAFileThatAppearedFirst() throws {
        let vault = try Self.vault(hardLinks: false)
        defer { vault.remove() }
        let url = vault.root.appendingPathComponent(Self.path)
        #expect(throws: VaultStoreError.nameTaken) {
            try vault.store.atomicWrite(
                Self.newBytes, to: url, exclusive: true,
                renameExclusively: { source, destination in
                    try Data("Kitap".utf8).write(to: destination, options: .withoutOverwriting)
                    try renameExclusivelyOrReportExisting(source, destination)
                })
        }
        #expect(try vault.bytes(Self.path) == Data("Kitap".utf8))
        #expect(try temporaries(in: vault.root).isEmpty)
    }

    @Test func volumesWithoutExclusiveRenameStillCreateExclusively() throws {
        let vault = try Self.vault(hardLinks: false)
        defer { vault.remove() }
        let url = vault.root.appendingPathComponent(Self.path)
        let unsupported: (URL, URL) throws -> Void = { _, _ in throw CocoaError(.featureUnsupported) }
        try vault.store.atomicWrite(Self.newBytes, to: url, exclusive: true, renameExclusively: unsupported)
        #expect(try vault.bytes(Self.path) == Self.newBytes)
        #expect(throws: VaultStoreError.nameTaken) {
            try vault.store.atomicWrite(Data("Kitap".utf8), to: url, exclusive: true, renameExclusively: unsupported)
        }
        #expect(try vault.bytes(Self.path) == Self.newBytes)
        #expect(try temporaries(in: vault.root).isEmpty)
    }

    private static func vault(hardLinks: Bool, links: Attempts = Attempts()) throws -> StoreVault {
        try StoreVault(linkFile: { source, destination in
            links.tick()
            guard hardLinks else { throw CocoaError(.fileWriteUnknown) }
            try FileManager.default.linkItem(at: source, to: destination)
        })
    }
}

/// On Linux the production rename reports no support; the race test then needs an existing-file error.
private func renameExclusivelyOrReportExisting(_ source: URL, _ destination: URL) throws {
    #if canImport(Darwin)
        try renameWithoutReplacing(source, destination)
    #else
        if FileManager.default.fileExists(atPath: destination.path) { throw POSIXError(.EEXIST) }
        try renameWithoutReplacing(source, destination)
    #endif
}

private struct FileSnapshot {
    struct Temporary {
        let bytes: Data
        let fileNumber: Int?
    }

    let temporaries: [Temporary]
    let destination: Data?

    init(directory: URL, destination url: URL) throws {
        temporaries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".vault-store-") }
            .map { name in
                let file = directory.appendingPathComponent(name)
                return Temporary(bytes: try Data(contentsOf: file), fileNumber: try fileNumber(file))
            }
        destination = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }
}

private func fileNumber(_ url: URL) throws -> Int? {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber)?.intValue
}

private func temporaries(in root: URL) throws -> [String] {
    try FileManager.default.subpathsOfDirectory(atPath: root.path).filter {
        URL(fileURLWithPath: $0).lastPathComponent.hasPrefix(".vault-store-")
    }
}

private final class Attempts: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func tick() { lock.withLock { value += 1 } }
}
