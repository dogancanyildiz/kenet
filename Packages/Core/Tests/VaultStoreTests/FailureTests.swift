import Foundation
import GRDB
import Testing
import VaultFormat
import VaultStore

@testable import VaultIndex

struct FailureTests {
    // A read-only directory does not stop root (the Linux CI container), so the test needs a real user.
    @Test(.enabled(if: geteuid() != 0)) func failedAtomicWritePreservesOldBytesAndIndex() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n- Kitap ^old\n")
        try vault.index.refresh(vaultRoot: vault.root)
        let original = try vault.bytes()
        let snapshot = try vault.index.snapshot()
        let directory = vault.root.appendingPathComponent("journal")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: (any Error).self) { try await vault.store.addingEvent(on: storeDate, text: "Su") }
        #expect(try vault.bytes() == original)
        #expect(try vault.index.snapshot() == snapshot)
    }

    @Test func indexFailureLeavesWrittenFileAndRefreshRepairsIt() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.index.database.write {
            try $0.execute(
                sql: "CREATE TRIGGER fail_store BEFORE INSERT ON files BEGIN SELECT RAISE(FAIL, 'test'); END")
        }
        await #expect {
            try await vault.store.addingEvent(on: storeDate, text: "Su")
        } throws: { error in
            guard case VaultStoreError.indexUpdateFailed(let path, let underlying) = error else { return false }
            return path == storePath && underlying is DatabaseError
        }
        #expect(
            try vault.bytes() == Data("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Events\n- Su ^aaaaaa\n".utf8))
        #expect(try vault.index.files().isEmpty)
        try await vault.index.database.write { try $0.execute(sql: "DROP TRIGGER fail_store") }
        try vault.index.refresh(vaultRoot: vault.root)
        try vault.check()
    }

    @Test func invalidUTF8DoesNotWrite() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Events\n")
        let bytes = Data([0xFF])
        try bytes.write(to: vault.root.appendingPathComponent(storePath))
        await #expect(throws: EditError.readOnlyDocument) {
            try await vault.store.addingEvent(on: storeDate, text: "Su")
        }
        #expect(try vault.bytes() == bytes)
    }

    @Test func escapingAndSymbolicPathsAreRejected() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        for path in ["../Kitap.md", "/Kitap.md", "notes/../Kitap.md", ".app/Kitap.md", "notes//Kitap.md"] {
            await #expect(throws: VaultStoreError.invalidPath) { try await vault.store.document(at: path) }
        }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: vault.root.appendingPathComponent("journal"), withDestinationURL: outside)
        await #expect(throws: VaultStoreError.invalidPath) {
            try await vault.store.addingEvent(on: storeDate, text: "Su")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
