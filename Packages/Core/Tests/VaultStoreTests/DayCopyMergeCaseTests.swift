import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// Every hand-written `Fixtures/merge` case, run through the store as a day file and its iCloud copy.
///
/// The expectations come from the fixture files alone, never from `ConflictMerge`: the day file must
/// end as `expected.md`, each preserved version must sit byte for byte under its `conflicts/` name,
/// and nothing else may be left on disk. Either version may be the one on the day file, as on two devices.
struct DayCopyMergeCaseTests {
    private static let day = "journal/2026-10-02.md"
    private static let copy = "journal/2026-10-02 2.md"

    private struct Case {
        let bytes: [String: [UInt8]]
        let times: [String: Int]
        let expected: [UInt8]
        let preserved: [String]

        init(_ name: String) throws {
            let directory = try Fixtures.root().appendingPathComponent("merge/" + name)
            struct Description: Decodable {
                let times: [String: Int]
                let preserved: [String]
            }
            let description = try JSONDecoder().decode(
                Description.self, from: Data(contentsOf: directory.appendingPathComponent("case.json")))
            bytes = try ["a", "b"].reduce(into: [:]) {
                $0[$1] = Array(try Data(contentsOf: directory.appendingPathComponent($1 + ".md")))
            }
            times = description.times
            expected = Array(try Data(contentsOf: directory.appendingPathComponent("expected.md")))
            preserved = description.preserved
        }

        /// Preserved names in the merge's order: older first, ties broken by bytes as `vault-format.md` says.
        var preservedInOrder: [String] {
            preserved.sorted { lhs, rhs in
                times[lhs]! != times[rhs]!
                    ? times[lhs]! < times[rhs]! : bytes[lhs]!.lexicographicallyPrecedes(bytes[rhs]!)
            }
        }
    }

    static func caseNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: Fixtures.root().appendingPathComponent("merge").path)
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    /// `19700101T0000SSZ`: fixture times are seconds after 1970, so the stamp is written out by hand.
    private static func stamp(_ seconds: Int) -> String {
        precondition((0..<60).contains(seconds))
        return "19700101T0000" + (seconds < 10 ? "0" : "") + String(seconds) + "Z"
    }

    private static func setTime(_ url: URL, _ seconds: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: seconds)], ofItemAtPath: url.path)
    }

    @Test(arguments: try caseNames(), ["a", "b"])
    func mergeCaseThroughTheStore(name: String, onDay: String) async throws {
        let fixture = try Case(name)
        let onCopy = onDay == "a" ? "b" : "a"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)
        let dayURL = root.appendingPathComponent(Self.day)
        let copyURL = root.appendingPathComponent(Self.copy)
        try Data(fixture.bytes[onDay]!).write(to: dayURL)
        try Data(fixture.bytes[onCopy]!).write(to: copyURL)
        // A fraction of a second must not change the order or the conflict name: times are whole seconds.
        try Self.setTime(dayURL, Double(fixture.times[onDay]!) + 0.75)
        try Self.setTime(copyURL, Double(fixture.times[onCopy]!) + 0.75)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let store = VaultStore(vaultRoot: root, index: index)

        let outcome = try await store.mergingDayCopy(Self.copy)

        var names: [String] = []
        for version in fixture.preservedInOrder {
            let stem = "conflicts/2026-10-02 (conflict " + Self.stamp(fixture.times[version]!)
            var number = 1
            while names.contains(stem + (number == 1 ? "" : " " + String(number)) + ").md") { number += 1 }
            names.append(stem + (number == 1 ? "" : " " + String(number)) + ").md")
        }
        let identical = fixture.bytes["a"]! == fixture.bytes["b"]!
        #expect(outcome.kind == (identical ? .identical : .merged))
        #expect(outcome.dayPath == Self.day)
        #expect(outcome.conflictPaths == names)
        #expect(outcome.fellBack == name.contains("falls-back"))
        var expectedTree: [String: Data?] = ["journal": nil, Self.day: Data(fixture.expected)]
        if !names.isEmpty { expectedTree["conflicts"] = .some(nil) }
        for (path, version) in zip(names, fixture.preservedInOrder) {
            expectedTree[path] = Data(fixture.bytes[version]!)
        }
        let merged = try DayCopyVault.tree(root)
        #expect(merged == expectedTree)
        try equivalent(index, root)

        // The other device, or a retry after a failed removal, meets the same copy again. The merged
        // file was written later than both versions; merging again changes nothing on disk.
        try Data(fixture.bytes[onCopy]!).write(to: copyURL)
        try Self.setTime(copyURL, Double(fixture.times[onCopy]!) + 0.75)
        try Self.setTime(dayURL, 1_000)
        let again = try await store.mergingDayCopy(Self.copy)
        #expect(Set(again.conflictPaths).isSubset(of: Set(names)))
        #expect(try DayCopyVault.tree(root) == merged)
        try equivalent(index, root)
    }

    /// Another process creating the chosen conflict name between the existence check and the write
    /// loses nothing: the write is exclusive and the version takes the next number.
    @Test func conflictCopiesAreCreatedExclusively() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let racer = "conflicts/2026-10-05 (conflict 20261005T060000Z).md"
        let racerURL = vault.url(racer)
        let store = vault.store(dayCopyStep: { step in
            if step == .conflictCopy(racer), !FileManager.default.fileExists(atPath: racerURL.path) {
                try Data("Eşzamanlı yazılan not.\n".utf8).write(to: racerURL)
            }
        })
        let preserved = try Data(contentsOf: vault.url("journal/2026-10-05 2.md"))
        let outcome = try await store.mergingDayCopy("journal/2026-10-05 2.md")
        #expect(outcome.conflictPaths == ["conflicts/2026-10-05 (conflict 20261005T060000Z 2).md"])
        #expect(try Data(contentsOf: racerURL) == Data("Eşzamanlı yazılan not.\n".utf8))
        #expect(try Data(contentsOf: vault.url(outcome.conflictPaths[0])) == preserved)
    }

    /// An index built before copies were excluded holds the copy as a note, and the copy sorts before
    /// its day (` ` < `.`), so it owned the identifiers both share. Refreshing removes its rows and
    /// hands ownership back to the day file.
    @Test(arguments: [false, true])
    func copyRowsOfAnOlderIndexAreRemoved(notified: Bool) throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let copy = "journal/2026-10-02 2.md"
        let shared = "- 09:00 Proje toplantısı ^e2a001\n"
        try Data(("---\ntype: journal\n---\n\n## Events\n" + shared).utf8).write(to: vault.url(copy))
        try vault.index.database.write { db in
            let data = try Data(contentsOf: vault.url(copy))
            let document = RawDocument(bytes: data)
            var owners: Set<String> = ["e2a001"]
            try IndexBuilder.insert(file: copy, data: data, document: document, modified: 0, db: db, owners: &owners)
            try IndexBuilder.insertLinks(document: document, file: copy, db: db)
            // A full build assigned ownership in path order, where the copy came first.
            try db.execute(sql: "UPDATE blocks SET ownsIdentifier=0 WHERE identifier='e2a001'")
            try db.execute(
                sql: "UPDATE blocks SET ownsIdentifier=1 WHERE identifier='e2a001' AND file=?", arguments: [copy])
        }
        #expect(try vault.index.owner(of: "e2a001")?.file == copy)
        #expect(try vault.index.files().contains { $0.path == copy && $0.kind == "note" })

        let result =
            notified
            ? try vault.index.update(paths: [copy], vaultRoot: vault.root)
            : try vault.index.refresh(vaultRoot: vault.root)

        #expect(result.deletedPaths == [copy])
        #expect(result.dayCopies.contains(copy))
        #expect(try vault.index.owner(of: "e2a001")?.file == "journal/2026-10-02.md")
        #expect(try !vault.index.files().contains { $0.path == copy })
        try equivalent(vault.index, vault.root)
    }

    /// A copy that is still a placeholder is a pending download, not a copy to merge; a copy whose
    /// day is still a placeholder is reported, and merging it waits for the day.
    @Test func placeholdersAndCopiesTogether() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        try Data("bplist00".utf8).write(to: vault.url("journal/.2026-10-06 2.md.icloud"))
        try Data("bplist00".utf8).write(to: vault.url("journal/.2026-10-07.md.icloud"))
        try Data("---\ntype: journal\n---\n\n## Events\n- Yağmur ^e7b001\n".utf8)
            .write(to: vault.url("journal/2026-10-07 2.md"))
        // A downloaded copy beside its own stale placeholder is a copy, not a pending download.
        try Data("bplist00".utf8).write(to: vault.url("journal/.2026-10-02 2.md.icloud"))
        let result = try vault.index.refresh(vaultRoot: vault.root)
        #expect(result.pendingDownloads == ["journal/2026-10-06 2.md", "journal/2026-10-07.md"])
        #expect(result.dayCopies == vault.cases.dayCopies + ["journal/2026-10-07 2.md"])
        #expect(try !vault.index.blockIdentifiers().contains("e7b001"))
        let before = try vault.tree()
        await #expect(throws: VaultStoreError.awaitingDownload(path: "journal/2026-10-07.md")) {
            try await vault.store().mergingDayCopy("journal/2026-10-07 2.md")
        }
        await #expect(throws: VaultStoreError.awaitingDownload(path: "journal/2026-10-06 2.md")) {
            try await vault.store().mergingDayCopy("journal/2026-10-06 2.md")
        }
        #expect(try vault.tree() == before)
    }
}

/// Fails the index's reads of one file while switched on.
private final class FailingIndexReads: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    let fileName: String

    init(fileName: String) { self.fileName = fileName }

    func set(_ value: Bool) { lock.withLock { failing = value } }

    func read(_ url: URL) throws -> Data {
        if lock.withLock({ failing }), url.lastPathComponent == fileName { throw InjectedFailure.failed }
        return try Data(contentsOf: url)
    }
}

struct DayCopyIndexFailureTests {
    /// The files are written first: when only the index update fails, the merge is complete on disk,
    /// the error names the day file, and the next refresh catches the index up.
    @Test func indexFailureAfterTheMergeKeepsTheMergedFiles() async throws {
        let vault = try DayCopyVault()
        defer { vault.remove() }
        let copy = "journal/2026-10-01 2.md"
        let dayPath = "journal/2026-10-01.md"
        let merge = ConflictMerge.merge(try vault.version(dayPath), try vault.version(copy))
        let reads = FailingIndexReads(fileName: "2026-10-01.md")
        let index = try VaultIndex(readFile: reads.read)
        try index.rebuild(vaultRoot: vault.root)
        let store = VaultStore(
            vaultRoot: vault.root, index: index, linkFile: { try FileManager.default.linkItem(at: $0, to: $1) })
        reads.set(true)
        await #expect {
            try await store.mergingDayCopy(copy)
        } throws: { error in
            guard case VaultStoreError.indexUpdateFailed(let path, let underlying) = error else { return false }
            return path == dayPath && underlying as? InjectedFailure == .failed
        }
        #expect(Array(try Data(contentsOf: vault.url(dayPath))) == merge.bytes)
        #expect(!FileManager.default.fileExists(atPath: vault.url(copy).path))
        #expect(
            Array(try Data(contentsOf: vault.url("conflicts/2026-10-01 (conflict 20261001T090000Z 2).md")))
                == merge.preserved.first?.bytes)
        reads.set(false)
        try index.refresh(vaultRoot: vault.root)
        try equivalent(index, vault.root)
    }
}
