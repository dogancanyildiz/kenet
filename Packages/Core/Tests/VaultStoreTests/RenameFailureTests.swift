import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

struct RenameFailureTests {
    let path = "people/Deniz Arıkan.md"
    let renamed = "people/Deniz Arıkan Yılmaz.md"

    private func prepare(_ vault: StoreVault) throws {
        try vault.write(path, "---\ntype: person\nname: Deniz Arıkan # keep\n---\nNotes\n")
        try vault.write("notes/Su.md", "[[Deniz Arıkan|Deniz]]\n")
        try vault.write("other/Kitap.md", "[[Deniz Arıkan]]\n")
        try vault.index.refresh(vaultRoot: vault.root)
    }

    @Test func moveRaceRestoresOriginalMetadataAndNeverOverwritesTarget() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        let original = try vault.bytes(path)
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            moveFile: { source, target in
                try Data("External file".utf8).write(to: target, options: .withoutOverwriting)
                try FileManager.default.moveItem(at: source, to: target)
            })
        await #expect(throws: VaultStoreError.nameTaken) {
            try await store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz", qualifier: "iş")
        }
        #expect(try vault.bytes(path) == original)
        #expect(try vault.bytes("people/Deniz Arıkan Yılmaz (iş).md") == Data("External file".utf8))
        #expect(try vault.bytes("notes/Su.md") == Data("[[Deniz Arıkan|Deniz]]\n".utf8))
        #expect(try vault.index.entities(named: "Deniz Arıkan").first?.qualifier == nil)
        try vault.check()
    }

    @Test func restoreFailureReturnsOldPathAndExplicitPartialChange() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            moveFile: { source, target in
                try Data("External file".utf8).write(to: target, options: .withoutOverwriting)
                try FileManager.default.moveItem(at: source, to: target)
            }, restoreRenameFile: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let result = try await store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz")
        #expect(result.path == path)
        #expect(result.updatedFiles == [path])
        #expect(result.hasPartialChange)
        #expect(result.failures.count == 1)
        let failure = try #require(result.failures.first)
        #expect(failure.path == path)
        guard case .partialChange(let reason) = failure.reason else {
            Issue.record("Expected partial change")
            return
        }
        #expect(reason.contains("move:") && reason.contains("restore:"))
        #expect(try vault.bytes(path) == Data("---\ntype: person\nname: Deniz Arıkan Yılmaz # keep\n---\nNotes\n".utf8))
        #expect(try vault.bytes(renamed) == Data("External file".utf8))
        #expect(try vault.bytes("notes/Su.md") == Data("[[Deniz Arıkan|Deniz]]\n".utf8))
        #expect(try vault.index.entities(named: "Deniz Arıkan Yılmaz").first?.file == path)
        try vault.check()
    }

    @Test func missingSourceReadReportsFileAndOtherSourcesContinue() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        let missing = vault.root.appendingPathComponent("notes/Su.md")
        let store = VaultStore(
            vaultRoot: vault.root, index: vault.index,
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            moveFile: { source, target in
                try FileManager.default.moveItem(at: source, to: target)
                try FileManager.default.removeItem(at: missing)
            })
        let result = try await store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz")
        #expect(result.path == renamed)
        #expect(result.updatedFiles == ["other/Kitap.md", renamed])
        let failure = try #require(result.failures.first)
        #expect(result.failures.count == 1 && failure.path == "notes/Su.md")
        guard case .file(let reason) = failure.reason else {
            Issue.record("Expected source read failure")
            return
        }
        #expect(reason.contains("NSCocoaErrorDomain") && reason.contains("260"))
        #expect(try vault.bytes("other/Kitap.md") == Data("[[Deniz Arıkan Yılmaz]]\n".utf8))
        try vault.check()
    }

    @Test(.enabled(if: geteuid() != 0)) func sourceWriteFailureReportsFileAndOtherSourcesContinue() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        let blocked = vault.root.appendingPathComponent("notes")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: blocked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path) }
        let result = try await vault.store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz")
        #expect(result.path == renamed)
        #expect(result.updatedFiles == ["other/Kitap.md", renamed])
        let failure = try #require(result.failures.first)
        #expect(result.failures.count == 1 && failure.path == "notes/Su.md")
        guard case .file(let reason) = failure.reason else {
            Issue.record("Expected source write failure")
            return
        }
        #expect(!reason.isEmpty)
        #expect(try vault.bytes("notes/Su.md") == Data("[[Deniz Arıkan|Deniz]]\n".utf8))
        #expect(try vault.bytes("other/Kitap.md") == Data("[[Deniz Arıkan Yılmaz]]\n".utf8))
        try vault.check()
    }

    @Test func indexFailureKeepsNewPathAndSavedFiles() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        try await vault.index.database.write {
            try $0.execute(
                sql:
                    "CREATE TRIGGER fail_rename BEFORE INSERT ON files BEGIN SELECT RAISE(FAIL, 'rename index test'); END"
            )
        }
        let result = try await vault.store.renamingEntity(at: path, to: "Deniz Arıkan Yılmaz")
        #expect(result.path == renamed)
        #expect(result.updatedFiles == ["notes/Su.md", "other/Kitap.md", renamed])
        let failure = try #require(result.failures.first)
        #expect(result.failures.count == 1 && failure.path == renamed)
        guard case .index(let reason) = failure.reason else {
            Issue.record("Expected index failure")
            return
        }
        #expect(reason.contains("rename index test"))
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(path).path))
        #expect(try vault.bytes("notes/Su.md") == Data("[[Deniz Arıkan Yılmaz|Deniz]]\n".utf8))
        #expect(try vault.bytes(renamed).count > 0)
        try await vault.index.database.write { try $0.execute(sql: "DROP TRIGGER fail_rename") }
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.check()
    }

    @Test func decomposedDiskNameCollidesWithNFCEquivalentName() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try prepare(vault)
        let duplicate = "notes/" + "Baran Tunç".decomposedStringWithCanonicalMapping + ".md"
        try vault.write(duplicate, "External file")
        let original = try vault.bytes(path)
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.renamingEntity(at: path, to: "Baran Tunç")
        }
        #expect(try vault.bytes(path) == original)
        #expect(try vault.bytes(duplicate) == Data("External file".utf8))
    }
}
