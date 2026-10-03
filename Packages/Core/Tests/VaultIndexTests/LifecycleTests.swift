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
        #expect(try db.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == IndexSchema.version)
        #expect(try db.read { try $0.tableExists("obsolete") } == false)
        #expect(
            try db.read {
                try String.fetchAll(
                    $0,
                    sql:
                        "SELECT name FROM sqlite_master WHERE type='index' AND name IN ('file_dates','link_targets','goal_keys') ORDER BY name"
                )
            } == ["file_dates", "goal_keys", "link_targets"])
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
        #expect(throws: (any Error).self) { try index.rebuild(vaultRoot: root.appendingPathComponent("absent")) }
        #expect(try index.snapshot() == before)
        try write(root, "Su.md", "Kitap")
        try index.rebuild(vaultRoot: root)
        #expect(try index.search("Su").isEmpty)
        #expect(try index.unresolvedLinks().isEmpty)
        #expect(try index.search("Kitap").count == 1)
    }
}

@Test func corruptDatabaseIsRecreatedAndOtherOpenErrorsPropagate() throws {
    try withVault { root in
        let url = root.appendingPathComponent("index.sqlite")
        try Data([0xff, 0x00, 0x01, 0x02]).write(to: url)
        try Data("Su".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("Kitap".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))
        let index = try VaultIndex(databaseURL: url)
        #expect(try index.files().isEmpty)
        let vault = root.appendingPathComponent("vault")
        try write(vault, "Su.md", "Su")
        try index.rebuild(vaultRoot: vault)
        #expect(try index.files().map(\.path) == ["Su.md"])
        #expect(throws: (any Error).self) {
            _ = try VaultIndex(databaseURL: root.appendingPathComponent("absent/index.sqlite"))
        }
    }
}
