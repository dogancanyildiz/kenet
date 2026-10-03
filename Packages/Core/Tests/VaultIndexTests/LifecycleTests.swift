import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex

@Test func staleSchemaIsErasedAndCurrentSchemaPersists() throws {
    try withVault { root in
        let url = root.appendingPathComponent("index.sqlite")
        do {
            let db = try DatabaseQueue(path: url.path)
            try db.write {
                try $0.execute(
                    sql:
                        "CREATE TABLE obsolete (value TEXT); INSERT INTO obsolete VALUES ('Su'); PRAGMA user_version=999"
                )
            }
        }
        let index = try VaultIndex(databaseURL: url)
        #expect(try index.files().isEmpty)
        let db = try DatabaseQueue(path: url.path)
        #expect(try db.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 1)
        #expect(try db.read { try $0.tableExists("obsolete") } == false)
        let vault = root.appendingPathComponent("vault")
        try write(vault, "Su.md", "Su")
        try index.rebuild(vaultRoot: vault)
        #expect(try VaultIndex(databaseURL: url).snapshot() == index.snapshot())
        #expect(throws: VaultIndexError.self) { try index.rebuild(vaultRoot: root) }
    }
}

@Test func failedRebuildRollsBackAndSuccessfulRebuildRemovesOldRows() throws {
    try withVault { root in
        try write(root, "Su.md", "Su [[Kitap]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let before = try index.snapshot()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Kitap.md"),
            withDestinationURL: root.appendingPathComponent("absent"))
        #expect(throws: VaultIndexError.self) { try index.rebuild(vaultRoot: root) }
        #expect(try index.snapshot() == before)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Kitap.md"))
        try write(root, "Su.md", "Kitap")
        try index.rebuild(vaultRoot: root)
        #expect(try index.search("Su").isEmpty)
        #expect(try index.unresolvedLinks().isEmpty)
        #expect(try index.search("Kitap").count == 1)
    }
}
