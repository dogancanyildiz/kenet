import Foundation
import GRDB
import Testing

@testable import VaultIndex

private func entityFieldFixture() throws -> URL {
    try Fixtures.root().appendingPathComponent("index/entity-fields")
}

private func entityFieldVault() throws -> URL {
    try Fixtures.root().appendingPathComponent("vaults/entity-fields")
}

private func expectedEntityFields() throws -> [IndexedEntityField] {
    try JSONDecoder().decode(
        [IndexedEntityField].self,
        from: Data(contentsOf: entityFieldFixture().appendingPathComponent("expected.json")))
}

/// The rows of one file as `key=kind:value`, in key order.
private func fields(_ index: VaultIndex, _ file: String) throws -> [String] {
    try index.entityFields().filter { $0.file == file }.map { $0.key + "=" + $0.kind + ":" + $0.value }
}

@Test func entityFieldsMatchFixtureAndQueries() throws {
    let expected = try expectedEntityFields()
    let index = try VaultIndex()
    try index.rebuild(vaultRoot: entityFieldVault())
    #expect(try index.entityFields() == expected)
    #expect(try index.snapshot().entityFields == expected)
    for kinds: Set<String> in [[], ["date"], ["number", "boolean"], ["unknown"], ["date", "unknown"]] {
        #expect(try index.entityFields(kinds: kinds) == expected.filter { kinds.contains($0.kind) })
    }
    for file in try index.files() {
        #expect(try index.contents(ofFile: file.path)?.entityFields == expected.filter { $0.file == file.path })
    }
    // A second full build starts from a populated table.
    try index.rebuild(vaultRoot: entityFieldVault())
    #expect(try index.entityFields() == expected)
}

@Test func entityFieldsIncrementalEquivalence() throws {
    let fixture = try entityFieldFixture()
    let expected = try expectedEntityFields()
    try withVault { temporary in
        let root = temporary.appendingPathComponent("vault")
        try FileManager.default.copyItem(at: entityFieldVault(), to: root)
        let index = try VaultIndex()
        try index.refresh(vaultRoot: root)
        try equivalent(index, root)
        let person = "people/Lora.md"
        let rows = [
            "added.md": ["amount=number:+5", "birthday=date:2026-03-04", "met=date:2024-06-07"],
            "changed.md": ["amount=number:+5", "birthday=date:2026-03-04"],
            "removed.md": [],
        ]
        for replacement in ["changed.md", "added.md", "changed.md", "removed.md"] {
            try Data(contentsOf: fixture.appendingPathComponent(replacement))
                .write(to: root.appendingPathComponent(person))
            try index.update(paths: [person], vaultRoot: root)
            #expect(try fields(index, person) == rows[replacement])
            try equivalent(index, root)
        }
        try Data(contentsOf: entityFieldVault().appendingPathComponent(person))
            .write(to: root.appendingPathComponent(person))
        try index.refresh(vaultRoot: root)
        #expect(try index.entityFields() == expected)
        try equivalent(index, root)
        try FileManager.default.removeItem(at: root.appendingPathComponent(person))
        try index.update(paths: [person], vaultRoot: root)
        try equivalent(index, root)
        #expect(try index.contents(ofFile: person) == nil)
        #expect(try index.entityFields() == expected.filter { $0.file != person })
        try FileManager.default.removeItem(at: root.appendingPathComponent(".app/types.json"))
        try index.refresh(vaultRoot: root)
        try equivalent(index, root)
        #expect(try index.entityFields() == expected.filter { $0.file != person && $0.file != "books/Fable.md" })
    }
}

@Test func entityFieldsFollowFileIdentityAndClassification() throws {
    try withVault { root in
        let index = try VaultIndex()
        let path = "people/Lora.md"
        let body = "since: 2020-01-31\nvisits: 4\n---\nKurgusal kişi.\n"
        func step(_ paths: Set<String>?, _ file: String, _ expected: [String]) throws {
            if let paths { try index.update(paths: paths, vaultRoot: root) } else { try index.refresh(vaultRoot: root) }
            #expect(try fields(index, file) == expected)
            #expect(try index.entityFields().count == expected.count)
            try equivalent(index, root)
        }
        let rows = ["since=date:2020-01-31", "visits=number:4"]
        try write(root, path, "---\ntype: person\n" + body)
        try step(nil, path, rows)
        // Entity to note and back.
        try write(root, path, "---\n" + body)
        try step([path], path, [])
        try write(root, path, "---\ntype: person\n" + body)
        try step([path], path, rows)
        // A duplicate key makes the block unreadable: nothing is read from it.
        try write(root, path, "---\ntype: person\nvisits: 9\n" + body)
        try step([path], path, [])
        try write(root, path, "---\ntype: person\n" + body)
        try step([path], path, rows)
        // Goals keep their own columns and produce no rows.
        try write(root, path, "---\ntype: goal\n" + body)
        try step([path], path, [])
        // Bytes that are not UTF-8 leave only the file row.
        try Data([0xFF, 0xFE] + Array(("---\ntype: person\n" + body).utf8)).write(to: root.appendingPathComponent(path))
        try step([path], path, [])
        try write(root, path, "---\ntype: person\n" + body)
        try step([path], path, rows)
        // Rename: rows move with the file.
        let renamed = "people/Lora Vale.md"
        try FileManager.default.moveItem(
            at: root.appendingPathComponent(path), to: root.appendingPathComponent(renamed))
        try step([path, renamed], renamed, rows)
        #expect(try fields(index, path).isEmpty)
        // A day path is a day whatever its `type` says.
        let day = "journal/2026-01-02.md"
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appendingPathComponent(renamed), to: root.appendingPathComponent(day))
        try step(nil, day, [])
        try FileManager.default.moveItem(at: root.appendingPathComponent(day), to: root.appendingPathComponent(path))
        try step(nil, path, rows)
        // A custom type exists only while its definition does; field kinds come from the spelling.
        let book = "books/Fable.md"
        try write(root, book, "---\ntype: book\ndate: 2026-04-05\npages: 320\n---\n")
        try index.update(paths: [book], vaultRoot: root)
        #expect(try index.entityFields().map(\.file) == [path, path])
        try equivalent(index, root)
        let types = try String(
            contentsOf: entityFieldVault().appendingPathComponent(".app/types.json"), encoding: .utf8)
        try write(root, ".app/types.json", types)
        try index.update(paths: ["absent.md"], vaultRoot: root)
        #expect(try fields(index, book) == ["date=date:2026-04-05", "pages=number:320"])
        try equivalent(index, root)
        try write(
            root, ".app/types.json", types.replacingOccurrences(of: "\"kind\": \"date\"", with: "\"kind\": \"text\""))
        try index.refresh(vaultRoot: root)
        #expect(try fields(index, book) == ["date=date:2026-04-05", "pages=number:320"])
        try equivalent(index, root)
        try write(root, ".app/types.json", "{")
        try index.refresh(vaultRoot: root)
        #expect(try fields(index, book).isEmpty)
        #expect(try fields(index, path) == rows)
        try equivalent(index, root)
    }
}

@Test func versionSixEntityFieldsAreErasedAndRebuilt() throws {
    let root = try entityFieldVault()
    let expected = try expectedEntityFields()
    try withVault { temporary in
        let url = temporary.appendingPathComponent("index.sqlite")
        do {
            let old = try DatabaseQueue(path: url.path)
            try old.write {
                try $0.execute(
                    sql:
                        "CREATE TABLE obsolete (value TEXT); INSERT INTO obsolete VALUES ('old'); PRAGMA user_version=6"
                )
            }
        }
        let index = try VaultIndex(databaseURL: url)
        #expect(try index.files().isEmpty)
        #expect(try index.entityFields().isEmpty)
        #expect(try index.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 8)
        #expect(try index.database.read { try $0.tableExists("obsolete") } == false)
        try index.refresh(vaultRoot: root)
        #expect(try index.entityFields() == expected)
        try equivalent(index, root)
    }
}
