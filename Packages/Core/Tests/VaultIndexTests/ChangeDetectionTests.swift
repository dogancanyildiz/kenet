import Foundation
import Testing

@testable import VaultIndex

/// Counts Markdown reads and serves a controllable stamp and clock to the index seams.
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    private var currentStamp: FileStamp
    private var currentTime: Double

    init(stamp: FileStamp, time: Double) {
        currentStamp = stamp
        currentTime = time
    }

    var stamp: FileStamp {
        get { lock.withLock { currentStamp } }
        set { lock.withLock { currentStamp = newValue } }
    }
    var time: Double {
        get { lock.withLock { currentTime } }
        set { lock.withLock { currentTime = newValue } }
    }
    var readCount: Int { lock.withLock { reads } }

    func read(_ url: URL) throws -> Data {
        lock.withLock { reads += 1 }
        return try Data(contentsOf: url)
    }

    func run<T>(_ body: () throws -> T) throws -> T {
        let reader: @Sendable (URL) throws -> FileStamp = { _ in self.stamp }
        let clock: @Sendable () -> Double = { self.time }
        return try FileStamp.$reader.withValue(reader) {
            try FileStamp.$clock.withValue(clock) { try body() }
        }
    }
}

struct ChangeDetectionTests {
    /// An editor replaces a file with same-size content and the volume keeps the old modification time.
    @Test func sameSizeEditWithRestoredModificationTimeIsIndexed() throws {
        try withVault { root in
            let url = root.appendingPathComponent("Su.md")
            let past = Date(timeIntervalSince1970: 1_759_622_400)
            try write(root, "Su.md", "- [ ] Kitap")
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let before = try FileStamp(url: url)

            try Data("- [x] Kitap".utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
            let after = try FileStamp(url: url)
            try #require(after.modified == before.modified && after.size == before.size)

            #expect(try index.refresh(vaultRoot: root).updatedPaths == ["Su.md"])
            #expect(try index.snapshot().blocks.map(\.status) == ["done"])
            try equivalent(index, root)
        }
    }

    /// On a coarse volume only one stamp field may move, or none when the edit lands in the same tick
    /// as the last check. Each case must still read the file once, and a settled stamp no more.
    @Test(arguments: ["changed", "inode", "racy"])
    func sameSizeEditIsReadWhenOneSignalMoves(signal: String) throws {
        try withVault { root in
            try write(root, "Su.md", "- [ ] Kitap")
            let original = FileStamp(modified: 1_000, changed: 1_000, inode: 7, size: 11)
            // A racy stamp was verified within the 2 s window after its modification time.
            let probe = Probe(stamp: original, time: signal == "racy" ? 1_001 : 1_100)
            let index = try VaultIndex(readFile: probe.read)
            try probe.run { _ = try index.rebuild(vaultRoot: root) }

            try write(root, "Su.md", "- [x] Kitap")
            probe.stamp = FileStamp(
                modified: original.modified, changed: original.changed + (signal == "changed" ? 1 : 0),
                inode: original.inode + (signal == "inode" ? 1 : 0), size: original.size)
            probe.time = 1_200
            let reads = probe.readCount
            #expect(try probe.run { try index.refresh(vaultRoot: root) }.updatedPaths == ["Su.md"])
            #expect(probe.readCount == reads + 1)
            #expect(try index.snapshot().blocks.map(\.status) == ["done"])
            try equivalent(index, root)

            probe.time = 1_300
            let settled = probe.readCount
            #expect(try probe.run { try index.refresh(vaultRoot: root) }.updatedPaths.isEmpty)
            #expect(probe.readCount == settled)
        }
    }

    /// A racy file whose bytes did not change keeps its rows and settles after one check.
    @Test func racyUnchangedFileIsReadOnceThenSettles() throws {
        try withVault { root in
            try write(root, "Su.md", "- [ ] Kitap")
            let probe = Probe(stamp: FileStamp(modified: 1_000, changed: 1_000, inode: 7, size: 11), time: 1_000.5)
            let index = try VaultIndex(readFile: probe.read)
            try probe.run { _ = try index.rebuild(vaultRoot: root) }
            let snapshot = try index.snapshot()

            probe.time = 1_001
            var reads = probe.readCount
            #expect(try probe.run { try index.refresh(vaultRoot: root) }.updatedPaths.isEmpty)
            #expect(probe.readCount == reads + 1)
            probe.time = 1_010
            reads = probe.readCount
            #expect(try probe.run { try index.refresh(vaultRoot: root) }.updatedPaths.isEmpty)
            #expect(probe.readCount == reads + 1)
            reads = probe.readCount
            #expect(try probe.run { try index.refresh(vaultRoot: root) }.updatedPaths.isEmpty)
            #expect(probe.readCount == reads)
            #expect(try index.snapshot() == snapshot)
        }
    }

    /// A notification on an empty index (first launch, erased schema) builds the whole vault.
    @Test func notificationOnEmptyIndexBuildsTheWholeVault() throws {
        try withVault { root in
            try write(root, "journal/2026-10-01.md", "## Events\n- 09:00 Su [[Kitap]]")
            try write(root, "notes/Kitap.md", "Kitap")
            try write(root, "notes/Spor.md", "Spor")
            let index = try VaultIndex()

            let result = try index.update(paths: ["notes/Spor.md"], vaultRoot: root)

            #expect(result.addedPaths.sorted() == ["journal/2026-10-01.md", "notes/Kitap.md", "notes/Spor.md"])
            #expect(try index.files().map(\.path) == ["journal/2026-10-01.md", "notes/Kitap.md", "notes/Spor.md"])
            #expect(try index.links(to: "notes/Kitap.md").map(\.file) == ["journal/2026-10-01.md"])
            try equivalent(index, root)
        }
    }
}

/// Decomposed (NFD) file names and link texts, as macOS input methods and some sync tools produce them.
struct DecomposedNameTests {
    private struct Expected: Decodable {
        struct Entity: Decodable {
            let file: String
            let comparisonKey: String
        }
        struct Link: Decodable {
            let file: String
            let line: Int
            let targetKey: String
            let resolvedFile: String?
        }
        let files: [String]
        let entities: [Entity]
        let aliases: [Entity]
        let links: [Link]
    }

    private static let fixture = "vaults/nfd-names"

    /// Copies the fixture vault with every path component written in NFD.
    private func materialize(into root: URL) throws -> [String] {
        let source = try Fixtures.root().appendingPathComponent(Self.fixture)
        let paths = try Fixtures.markdownPaths(in: Self.fixture).map { String($0.dropFirst(Self.fixture.count + 1)) }
        for path in paths {
            let target = root.appendingPathComponent(path.decomposedStringWithCanonicalMapping)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: source.appendingPathComponent(path)).write(to: target)
        }
        return paths
    }

    private func bytes(_ text: String?) -> [UInt8]? { text.map { Array($0.utf8) } }

    private func check(_ index: VaultIndex) throws {
        let expected = try JSONDecoder().decode(
            Expected.self,
            from: Data(contentsOf: Fixtures.root().appendingPathComponent(Self.fixture + "/expected.json")))
        let snapshot = try index.snapshot()
        // Swift `==` treats NFC and NFD as equal; compare the stored bytes.
        #expect(snapshot.files.map { bytes($0.path) } == expected.files.map { bytes($0) })
        #expect(
            snapshot.entities.map { [bytes($0.file), bytes($0.comparisonKey)] }
                == expected.entities.map { [bytes($0.file), bytes($0.comparisonKey)] })
        #expect(
            snapshot.aliases.map { [bytes($0.file), bytes($0.comparisonKey)] }
                == expected.aliases.map { [bytes($0.file), bytes($0.comparisonKey)] })
        #expect(snapshot.links.map(\.line) == expected.links.map(\.line))
        #expect(
            snapshot.links.map { [bytes($0.file), bytes($0.targetKey), bytes($0.resolvedFile)] }
                == expected.links.map { [bytes($0.file), bytes($0.targetKey), bytes($0.resolvedFile)] })
    }

    @Test func decomposedNamesAndLinksIndexAsNFC() throws {
        try withVault { root in
            let paths = try materialize(into: root)
            let person = "people/Baran Tunç.md"
            #expect(paths.contains(person))
            // The volume must keep the NFD spelling, or this test would not exercise normalization.
            let onDisk = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("people").path)
            try #require(
                onDisk.map { Array($0.utf8) } == [Array("Baran Tunç.md".decomposedStringWithCanonicalMapping.utf8)])

            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            try check(index)
            #expect(try index.entities(named: "Tunç".decomposedStringWithCanonicalMapping).map(\.file) == [person])
            #expect(try index.links(to: person.decomposedStringWithCanonicalMapping).count == 2)
        }
    }

    /// Deleting the NFD-named file and notifying its NFD path re-resolves incoming links both ways.
    @Test func decomposedNotificationsRepairIncomingLinks() throws {
        try withVault { root in
            _ = try materialize(into: root)
            let physical = "people/Baran Tunç.md".decomposedStringWithCanonicalMapping
            let url = root.appendingPathComponent(physical)
            let bytes = try Data(contentsOf: url)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)

            try FileManager.default.removeItem(at: url)
            #expect(try index.update(paths: [physical], vaultRoot: root).deletedPaths == ["people/Baran Tunç.md"])
            #expect(try index.unresolvedLinks().count == 2)
            try equivalent(index, root)

            try bytes.write(to: url)
            #expect(try index.update(paths: [physical], vaultRoot: root).addedPaths == ["people/Baran Tunç.md"])
            #expect(try index.unresolvedLinks().isEmpty)
            try check(index)
            try equivalent(index, root)
        }
    }
}
