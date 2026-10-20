import Foundation
import Testing

@testable import VaultIndex

/// `Fixtures/vaults/conflict-copies`: the versions a day copy merge saved under `conflicts/`,
/// listed from disk with the day file each belongs to.
struct ConflictCopyTests {
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
        let conflictCopies: [Copy]
    }

    private static func fixture() throws -> (source: URL, expected: Expected) {
        let directory = try Fixtures.root().appendingPathComponent("vaults/conflict-copies")
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: directory.appendingPathComponent("expected.json")))
        return (directory.appendingPathComponent("source"), expected)
    }

    private static func files(_ copies: [Expected.Copy]) -> [CopyFile] {
        copies.map { CopyFile(folder: $0.folder, copy: $0.copy, original: $0.original) }
    }

    @Test func copyNamesFollowTheTable() throws {
        for name in try Self.fixture().expected.names {
            #expect(ConflictCopyName.dayPath(ofCopy: name.path) == name.original, "\(name.path)")
            #expect(ConflictCopyName.isConflictCopy(path: name.path) == (name.original != nil), "\(name.path)")
        }
    }

    /// Only names under the rule, directly under `conflicts/`: no placeholder, no subfolder, no root file.
    @Test func fixtureListsConflictCopiesFromDisk() throws {
        let (source, expected) = try Self.fixture()
        #expect(try VaultIndex.conflictCopies(vaultRoot: source) == Self.files(expected.conflictCopies))
    }

    /// Listing reads names only: every file in the vault keeps its bytes and the index never holds a copy.
    @Test func listingChangesNothingAndStaysOutOfTheIndex() throws {
        let (source, expected) = try Self.fixture()
        func snapshot() throws -> [String: Data] {
            var bytes: [String: Data] = [:]
            for path in try FileManager.default.subpathsOfDirectory(atPath: source.path) {
                let url = source.appendingPathComponent(path)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                    !isDirectory.boolValue
                else { continue }
                bytes[path] = try Data(contentsOf: url)
            }
            return bytes
        }
        let before = try snapshot()
        _ = try VaultIndex.conflictCopies(vaultRoot: source)
        #expect(try snapshot() == before)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: source)
        let indexed = Set(try index.files().map(\.path))
        for copy in expected.conflictCopies { #expect(!indexed.contains(copy.copy), "\(copy.copy)") }
    }

    /// Day, then saved time, then the series number; the input order never matters.
    @Test func orderDoesNotDependOnInputOrder() throws {
        let expected = try Self.fixture().expected.conflictCopies.map(\.copy)
        let noise = ["conflicts/Notlar.md", "conflicts/2026-10-02 (conflict 20261002T110533Z 1).md"]
        #expect(ConflictCopyName.copies(in: expected + noise) == expected)
        #expect(ConflictCopyName.copies(in: (expected + noise).reversed()) == expected)
        #expect(ConflictCopyName.copies(in: expected.shuffled()) == expected)
    }

    @Test func missingFolderListsNothing() throws {
        try withVault { root in
            try write(root, "journal/2026-10-02.md", "- Gün\n")
            #expect(try VaultIndex.conflictCopies(vaultRoot: root).isEmpty)
        }
    }

    /// `Conflicts/` is not the reserved folder, even on a volume that ignores case.
    @Test func conflictCopiesNeedTheExactFolder() throws {
        try withVault { root in
            try write(root, "Conflicts/2026-10-02 (conflict 20261002T110533Z).md", "- Sürüm\n")
            #expect(try VaultIndex.conflictCopies(vaultRoot: root).isEmpty)
        }
    }

    /// A linked folder or a folder spelled like a copy is never listed; a linked file is not either.
    @Test func linksAndFoldersAreLeftOut() throws {
        try withVault { root in
            let name = "2026-10-02 (conflict 20261002T110533Z).md"
            try write(root, "elsewhere/" + name, "- Sürüm\n")
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("conflicts"),
                withDestinationURL: root.appendingPathComponent("elsewhere"))
            #expect(try VaultIndex.conflictCopies(vaultRoot: root).isEmpty)
        }
        try withVault { root in
            try write(root, "elsewhere.md", "- Sürüm\n")
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("conflicts/2026-10-03 (conflict 20261003T090000Z).md"),
                withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("conflicts/2026-10-02 (conflict 20261002T110533Z).md"),
                withDestinationURL: root.appendingPathComponent("elsewhere.md"))
            try write(root, "conflicts/2026-10-01 (conflict 20261001T090000Z).md", "- Sürüm\n")
            #expect(
                try VaultIndex.conflictCopies(vaultRoot: root) == [
                    CopyFile(
                        folder: "conflicts", copy: "conflicts/2026-10-01 (conflict 20261001T090000Z).md",
                        original: "journal/2026-10-01.md")
                ])
        }
    }
}
