import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import VaultIndex

struct EntityTypeTests {
    @Test(arguments: ["valid", "invalid", "collision", "duplicate"])
    func schemaFixtures(_ name: String) throws {
        struct Expectation: Decodable {
            let ids: [String]
            let issue: Bool
        }
        let root = try Fixtures.root().appendingPathComponent("entity-types/" + name)
        let expected = try JSONDecoder().decode(
            Expectation.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let catalog = EntityTypeReader.decode(try Data(contentsOf: root.appendingPathComponent("input.json")))
        #expect(catalog.types.map(\.id) == expected.ids)
        #expect((catalog.issue != nil) == expected.issue)
    }

    @Test func missingUnreadableAndDuplicateJSONKeysFallBack() throws {
        try withVault { root in
            #expect(EntityTypeReader.read(vaultRoot: root).types.isEmpty)
            #expect(EntityTypeReader.read(vaultRoot: root).issue == nil)
            try write(root, ".app/types.json", "{\"formatVersion\":1,\"formatVersion\":1,\"types\":[]}")
            #expect(EntityTypeReader.read(vaultRoot: root).issue != nil)
            try FileManager.default.removeItem(at: root.appendingPathComponent(".app/types.json"))
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent(".app/types.json").path, withDestinationPath: "/absent/types.json")
            #expect(EntityTypeReader.read(vaultRoot: root).issue != nil)
        }
    }

    @Test func typedVaultIndexesTwoBooksAndTemplateIsExcluded() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/typed")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.files.count == 2)
        #expect(snapshot.files.allSatisfy { $0.kind == "book" })
        #expect(snapshot.entities.map(\.kind) == ["book", "book"])
        #expect(try index.knownEntities().isEmpty)
        let books = try index.knownEntities(kinds: ["book"])
        #expect(books.count == 2 && books.allSatisfy { $0.kind == .custom("book") })
        #expect(books.first?.aliases == ["Orman"])
        #expect(try index.knownEntities(kinds: ["goal"]).isEmpty)
        #expect(try index.knownEntities(kinds: []).isEmpty)
        for path in snapshot.files.map(\.path) + ["templates/book.md"] {
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            #expect(RawDocument(bytes: data).serialized() == Array(data))
        }
    }

    @Test func externalSchemaRemovalAndRestorationReclassifiesUnchangedFiles() throws {
        try withVault { root in
            let fixture = try Fixtures.root().appendingPathComponent("vaults/typed")
            let schema = try String(contentsOf: fixture.appendingPathComponent(".app/types.json"), encoding: .utf8)
            try write(root, ".app/types.json", schema)
            try write(root, "books/Kitap.md", "---\ntype: book\nname: Kitap\n---\nNotlar")
            let bytes = try Data(contentsOf: root.appendingPathComponent("books/Kitap.md"))
            let db = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".sqlite")
            defer { try? FileManager.default.removeItem(at: db) }
            let index = try VaultIndex(databaseURL: db)
            try index.refresh(vaultRoot: root)
            #expect(try index.snapshot().entities.first?.kind == "book")
            try write(root, ".app/types.json", "{\"formatVersion\":1,\"types\":[]}")
            // Even a scoped Markdown notification must apply a changed registry to every file.
            try VaultIndex(databaseURL: db).update(paths: ["not-present.md"], vaultRoot: root)
            #expect(try index.snapshot().entities.isEmpty)
            #expect(try index.files().first?.kind == "note")
            try write(root, ".app/types.json", schema)
            try index.refresh(vaultRoot: root)
            #expect(try index.snapshot().entities.first?.kind == "book")
            #expect(try Data(contentsOf: root.appendingPathComponent("books/Kitap.md")) == bytes)
            #expect(try index.snapshot() == rebuiltSnapshot(root))
        }
    }

    @Test func idsPathsReservedFieldsAndInvalidKindsAreRejected() throws {
        let valid = try #require(
            EntityTypeReader.read(vaultRoot: Fixtures.root().appendingPathComponent("vaults/typed")).types.first)
        for id in ["person", "place", "goal", "journal", "day", "note", "Book", "kitap türü", "1book", ""] {
            let value = EntityTypeDefinition(
                id: id, folder: valid.folder, name: valid.name, plural: valid.plural, icon: valid.icon)
            #expect(throws: EntityTypeError.self) { try value.validate() }
        }
        for path in [
            "../books", "/books", "books//sub", "books/.hidden", "books/../outside", "templates", "conflicts/other",
            "journal", "books\\outside",
        ] {
            var value = valid
            value.folder = path
            #expect(throws: EntityTypeError.self) { try value.validate() }
        }
        for field in ["type", "name", "qualifier", "aliases", "", "<<"] {
            var value = valid
            value.fields = [.init(key: field, kind: .text)]
            #expect(throws: EntityTypeError.self) { try value.validate() }
        }
        var duplicate = valid
        duplicate.fields = [.init(key: "author", kind: .text), .init(key: "author", kind: .date)]
        #expect(throws: EntityTypeError.self) { try duplicate.validate() }
    }

    @Test func customAndBuiltinRecognitionKindsRetainStringCodableShape() throws {
        for kind in [KnownEntity.Kind.person, .place, .custom("book")] {
            let data = try JSONEncoder().encode(kind)
            #expect(try JSONDecoder().decode(String.self, from: data) == kind.rawValue)
            #expect(try JSONDecoder().decode(KnownEntity.Kind.self, from: data) == kind)
        }
    }

    private func rebuiltSnapshot(_ root: URL) throws -> IndexSnapshot {
        let fresh = try VaultIndex()
        try fresh.rebuild(vaultRoot: root)
        return try fresh.snapshot()
    }
}
