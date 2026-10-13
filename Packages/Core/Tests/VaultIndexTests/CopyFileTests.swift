import Foundation
import Testing

@testable import VaultIndex

/// `Fixtures/vaults/copy-files`: entity copies from the index, day copies from `journal/` on disk.
struct CopyFileTests {
    private struct Expected: Decodable {
        struct Name: Decodable {
            let path: String
            let original: String?
        }
        struct Copy: Decodable {
            let folder: String
            let copy: String
            let original: String
        }
        let names: [Name]
        let entityCopies: [Copy]
        let dayCopies: [Copy]
    }

    private static func fixture() throws -> (source: URL, expected: Expected) {
        let directory = try Fixtures.root().appendingPathComponent("vaults/copy-files")
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: directory.appendingPathComponent("expected.json")))
        return (directory.appendingPathComponent("source"), expected)
    }

    private static func files(_ copies: [Expected.Copy]) -> [CopyFile] {
        copies.map { CopyFile(folder: $0.folder, copy: $0.copy, original: $0.original) }
    }

    @Test func copyNamesFollowTheTable() throws {
        for name in try Self.fixture().expected.names {
            #expect(EntityCopyName.originalPath(ofCopy: name.path) == name.original, "\(name.path)")
        }
    }

    @Test func fixtureListsEntityCopiesAndKeepsThemIndexed() throws {
        let (source, expected) = try Self.fixture()
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: source)
        #expect(try index.entityCopies() == Self.files(expected.entityCopies))
        // Listing changes nothing: every copy is still indexed as its own file.
        let indexed = Set(try index.files().map(\.path))
        for copy in expected.entityCopies { #expect(indexed.contains(copy.copy), "\(copy.copy)") }
        #expect(indexed.contains("people/Deniz 1.md") && indexed.contains("people/Kaan 2.md"))
    }

    @Test func fixtureListsDayCopiesFromDisk() throws {
        let (source, expected) = try Self.fixture()
        #expect(try VaultIndex.dayCopies(vaultRoot: source) == Self.files(expected.dayCopies))
    }

    @Test func orderDoesNotDependOnInputOrder() throws {
        let expected = Self.files(try Self.fixture().expected.entityCopies)
        let originals = expected.map(\.original)
        let paths = expected.map(\.copy) + ["people/Deniz 1.md", "people/Kaan 2.md", "notes/Plan 2.md"]
        #expect(EntityCopyName.copies(in: paths, originals: originals) == expected)
        #expect(EntityCopyName.copies(in: paths.reversed(), originals: originals.reversed()) == expected)
    }

    /// A folder spelled `Journal/` is not the day folder, even on a volume that ignores case.
    @Test func dayCopiesNeedTheExactJournalFolder() throws {
        try withVault { root in
            try write(root, "Journal/2026-10-02.md", "- Gün\n")
            try write(root, "Journal/2026-10-02 2.md", "- Kopya\n")
            #expect(try VaultIndex.dayCopies(vaultRoot: root).isEmpty)
        }
        try withVault { root in
            let copies = try VaultIndex.dayCopies(vaultRoot: root)
            #expect(copies.isEmpty)
        }
    }
}
