import Foundation
import GRDB
import Testing

@testable import VaultIndex

private func sample(_ root: URL) throws -> URL {
    let vault = root.appendingPathComponent("sample")
    try FileManager.default.copyItem(at: Fixtures.root().appendingPathComponent("vaults/sample"), to: vault)
    return vault
}

@Test func refreshSampleEditSequenceMatchesRebuild() throws {
    try withVault { temporary in
        let root = try sample(temporary)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        func put(_ path: String, _ text: String) throws {
            try write(root, path, text)
            let result = try index.refresh(vaultRoot: root)
            #expect(result.addedPaths.contains(path) || result.updatedPaths.contains(path))
            try equivalent(index, root)
        }
        func delete(_ path: String) throws {
            try FileManager.default.removeItem(at: root.appendingPathComponent(path))
            let result = try index.refresh(vaultRoot: root)
            #expect(result.deletedPaths == [path])
            try equivalent(index, root)
        }
        try put("journal/2026-10-01.md", "---\ngoals:\n  su: 8\n---\n## Events\n- Su ^new\n## Tasks\n- [ ] Kitap ^task")
        try put("people/Ece Yalın (iş).md", "---\ntype: person\nname: Ece Yalın\naliases: [Ece]\n---\n")
        try delete("people/Deniz Arıkan.md")
        #expect(try index.unresolvedLinks().contains { $0.target == "Deniz Arıkan" })
        try put(
            "journal/2026-10-01.md",
            "---\ngoals:\n  su: 9\n---\n## Events\n- Spor ^new\n- Kitap ^added\n## Tasks\n- [x] Kitap ^task")
        try put("people/Ece Yalın (iş).md", "---\ntype: person\nname: Selin Korkmaz\naliases: [Selin]\n---\n")
        try put("notes/Su.md", "[[Kitap]] [[Su]] [[people/Ece Yalın (iş)]]")
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("notes/Su.md"), to: root.appendingPathComponent("notes/Kitap.md"))
        let rename = try index.refresh(vaultRoot: root)
        #expect(rename.addedPaths == ["notes/Kitap.md"] && rename.deletedPaths == ["notes/Su.md"])
        try equivalent(index, root)
        try put("a/Kitap.md", "- [ ] Su ^task\n- [ ] Kitap ^task")
        #expect(
            try index.snapshot().blocks.first { $0.identifier == "task" && $0.ownsIdentifier }?.file == "a/Kitap.md")
        #expect(try index.links(to: "a/Kitap.md").contains { $0.target == "Kitap" })
        try delete("a/Kitap.md")
        #expect(
            try index.snapshot().blocks.first { $0.identifier == "task" && $0.ownsIdentifier }?.file
                == "journal/2026-10-01.md")
        try Data([0xff]).write(to: root.appendingPathComponent("notes/Kitap.md"))
        #expect(try index.refresh(vaultRoot: root).updatedPaths == ["notes/Kitap.md"])
        try equivalent(index, root)
        try write(root, "conflicts/Su.md", "- [ ] Su ^task")
        #expect(try index.refresh(vaultRoot: root).addedPaths.isEmpty)
        try equivalent(index, root)
    }
}

@Test func metadataOnlyDoesNotRewriteContentAndEqualSizeChangesAreDetected() throws {
    try withVault { root in
        try write(root, "Su.md", "Su")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        // A trigger makes any attempted content replacement observable, even if the snapshot is equal.
        try index.database.write {
            try $0.execute(
                sql: "CREATE TRIGGER preserve_blocks BEFORE DELETE ON blocks BEGIN SELECT RAISE(ABORT,'rewritten'); END"
            )
        }
        let before = try index.files()[0]
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: before.modified + 10)],
            ofItemAtPath: root.appendingPathComponent("Su.md").path)
        #expect(try index.refresh(vaultRoot: root).updatedPaths.isEmpty)
        #expect(try index.files()[0].digest == before.digest)
        try equivalent(index, root)
        try index.database.write { try $0.execute(sql: "DROP TRIGGER preserve_blocks") }
        try write(root, "Su.md", "su")
        #expect(try index.refresh(vaultRoot: root).updatedPaths == ["Su.md"])
        #expect(try index.files()[0].size == before.size)
        try equivalent(index, root)
        #expect(try index.refresh(vaultRoot: root).updatedPaths.isEmpty)
    }
}

@Test func notifiedFilesDirectoriesDeletionAndOutsidePaths() throws {
    try withVault { temporary in
        let root = try sample(temporary)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try write(root, "notes/Çınaraltı Kafe.md", "[[Su]]")
        #expect(
            try index.update(paths: ["notes/Çınaraltı Kafe.md".decomposedStringWithCanonicalMapping], vaultRoot: root)
                .addedPaths == ["notes/Çınaraltı Kafe.md"])
        try equivalent(index, root)
        try write(root, "notes/Çınaraltı Kafe.md", "[[Kitap]]")
        try write(root, "notes/Su.md", "Su")
        #expect(
            try index.update(paths: [root.appendingPathComponent("notes").path], vaultRoot: root).addedPaths == [
                "notes/Su.md"
            ])
        try equivalent(index, root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/Su.md"))
        #expect(try index.update(paths: ["notes/Su.md"], vaultRoot: root).deletedPaths == ["notes/Su.md"])
        try equivalent(index, root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes"))
        #expect(try index.update(paths: ["notes"], vaultRoot: root).deletedPaths.count == 4)
        try equivalent(index, root)
        try write(temporary, "Su.md", "Su")
        try write(root, "journal/2026-10-01.md", "Su")
        let before = try index.snapshot()
        let ignored = try index.update(
            paths: ["../Su.md", temporary.appendingPathComponent("Su.md").path, "conflicts", ".app", "templates"],
            vaultRoot: root)
        #expect(ignored.addedPaths.isEmpty && ignored.updatedPaths.isEmpty && ignored.deletedPaths.isEmpty)
        #expect(try index.snapshot() == before)
        try index.update(paths: ["journal"], vaultRoot: root)
        try equivalent(index, root)
    }
}

@Test func incrementalFailureAfterWritesRollsBack() throws {
    try withVault { temporary in
        let root = temporary.appendingPathComponent("sample")
        try write(root, "Su.md", "Su [[Kitap]]")
        try write(root, "Kitap.md", "Kitap")
        let index = try VaultIndex(databaseURL: temporary.appendingPathComponent("index.sqlite"))
        try index.rebuild(vaultRoot: root)
        let before = try index.snapshot()
        let files = try index.files()
        let search = try index.search("Su")
        try index.database.write {
            try $0.execute(
                sql:
                    "CREATE TRIGGER fail_insert BEFORE INSERT ON blocks WHEN new.file='Spor.md' BEGIN SELECT RAISE(ABORT,'failure'); END"
            )
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("Kitap.md"))
        try write(root, "Spor.md", "Spor")
        for notified in [false, true] {
            #expect(throws: (any Error).self) {
                if notified {
                    try index.update(paths: [""], vaultRoot: root)
                } else {
                    try index.refresh(vaultRoot: root)
                }
            }
            #expect(try index.snapshot() == before)
            #expect(try index.files() == files)
            #expect(try index.search("Su") == search)
        }
        #expect(throws: VaultIndexError.self) { try index.refresh(vaultRoot: temporary) }
        #expect(throws: VaultIndexError.self) { try index.update(paths: [], vaultRoot: temporary) }
        try index.database.write { try $0.execute(sql: "DROP TRIGGER fail_insert") }
        try index.refresh(vaultRoot: root)
        try equivalent(index, root)
    }
}

@Test func continuationHeadingsAndIrrelevantSymlinksAreExcluded() throws {
    try withVault { root in
        try write(root, "Su.md", "- [ ] Su ^x\n  ## Kitap\n  devam")
        for path in ["Su.txt", ".hidden", "conflicts", "templates"] {
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent(path),
                withDestinationURL: path == "Su.txt" ? root.appendingPathComponent("Su.md") : root)
        }
        let index = try VaultIndex()
        #expect(try index.rebuild(vaultRoot: root).skippedPaths.isEmpty)
        #expect(try index.snapshot().blocks.map(\.kind) == ["task"])
        #expect(try index.snapshot().blocks[0].lastLine == 3)
        try write(root, "Su.md", "## Events\n- Su ^x\n  ## Kitap\n  devam")
        try index.refresh(vaultRoot: root)
        #expect(try index.snapshot().blocks.map(\.kind) == ["event"])
        try equivalent(index, root)
    }
}

@Test func continuationIndexFixture() throws {
    let root = try Fixtures.root().appendingPathComponent("index/continuation")
    let index = try VaultIndex()
    try index.rebuild(vaultRoot: root)
    let expected = try JSONDecoder().decode(
        IndexSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
    #expect(try index.snapshot() == expected)
}
