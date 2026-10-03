import Foundation
import GRDB
import GRDBSQLite
import Testing

@testable import VaultIndex

@Test func largeRefreshAndNotifiedUpdateRespectSQLiteVariableLimit() throws {
    try withVault { root in
        let index = try VaultIndex()
        try index.database.write { db in
            _ = sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_VARIABLE_NUMBER, 999)
            #expect(sqlite3_limit(db.sqliteConnection, SQLITE_LIMIT_VARIABLE_NUMBER, -1) == 999)
        }
        var paths: Set<String> = []
        for number in 0..<1001 {
            let path = "notes/Su \(number).md"
            paths.insert(path)
            try write(root, path, "Su [[notes/Su 0]]")
        }
        #expect(try index.refresh(vaultRoot: root).addedPaths.count == 1001)
        try equivalent(index, root)
        for path in paths { try write(root, path, "Kitap [[notes/Su 1]]") }
        #expect(try index.update(paths: paths, vaultRoot: root).updatedPaths.count == 1001)
        try equivalent(index, root)
        // Successful repair removes its temporary tables before the next operation.
        #expect(
            try index.database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_temp_master WHERE name LIKE 'affected_link_%'")
            } == 0)
    }
}

@Test func caseChangedRenameNotificationRemovesPreviousSpelling() throws {
    try withVault { root in
        try write(root, "notes/b.md", "Su")
        try write(root, "notes/Kitap.md", "[[b]] [[notes/b]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("notes/b.md"), to: root.appendingPathComponent("notes/B.md"))
        let result = try index.update(paths: ["notes/B.md"], vaultRoot: root)
        #expect(result.deletedPaths == ["notes/b.md"])
        #expect(result.addedPaths == ["notes/B.md"])
        #expect(try index.files().map(\.path) == ["notes/B.md", "notes/Kitap.md"])
        try equivalent(index, root)
    }
}

@Test func differentlyCasedFileAndDirectoryNotificationsUpdatePhysicalPaths() throws {
    try withVault { root in
        try write(root, "notes/a.md", "Su")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try write(root, "notes/a.md", "Kitap")
        #expect(try index.update(paths: ["Notes/A.md"], vaultRoot: root).updatedPaths == ["notes/a.md"])
        try equivalent(index, root)
        try write(root, "notes/a.md", "Spor")
        #expect(try index.update(paths: ["NOTES"], vaultRoot: root).updatedPaths == ["notes/a.md"])
        try equivalent(index, root)
    }
}

@Test func pathTargetLinksFollowCreationDeletionAndRename() throws {
    try withVault { root in
        try write(root, "notes/Kitap.md", "[[notes/X]] [[notes/Su]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try write(root, "notes/X.md", "Su")
        try index.refresh(vaultRoot: root)
        #expect(try index.links(to: "notes/X.md").count == 1)
        try equivalent(index, root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("notes/X.md"))
        try index.refresh(vaultRoot: root)
        #expect(try index.unresolvedLinks().count == 2)
        try equivalent(index, root)
        try write(root, "notes/X.md", "Su")
        try index.update(paths: ["notes/X.md"], vaultRoot: root)
        try equivalent(index, root)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("notes/X.md"), to: root.appendingPathComponent("notes/Su.md"))
        let result = try index.update(paths: ["notes/X.md", "notes/Su.md"], vaultRoot: root)
        #expect(result.deletedPaths == ["notes/X.md"] && result.addedPaths == ["notes/Su.md"])
        #expect(try index.links(to: "notes/Su.md").count == 1)
        #expect(try index.unresolvedLinks().map(\.target) == ["notes/X"])
        try equivalent(index, root)
    }
}

@Test func disposableDatabaseRemovalDeletesRollbackJournalDirectly() throws {
    try withVault { root in
        let url = root.appendingPathComponent("index.sqlite")
        // Check the application's deletion routine without SQLite opening (and discarding) the journal.
        let magic = Data([0xd9, 0xd5, 0x05, 0xf9, 0x20, 0xa1, 0x63, 0xd7])
        let suffixes = ["", "-wal", "-shm", "-journal"]
        for suffix in suffixes {
            try (magic + Data(repeating: 0, count: 504)).write(to: URL(fileURLWithPath: url.path + suffix))
        }
        try write(root, "Su.md", "Su")
        try IndexDatabase.removeFiles(at: url)
        for suffix in suffixes {
            #expect(!FileManager.default.fileExists(atPath: url.path + suffix))
        }
        #expect(try Data(contentsOf: root.appendingPathComponent("Su.md")) == Data("Su".utf8))
    }
}
