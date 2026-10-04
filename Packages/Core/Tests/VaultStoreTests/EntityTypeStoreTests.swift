import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

struct EntityTypeStoreTests {
    private func book() throws -> EntityTypeDefinition {
        try #require(
            EntityTypeReader.read(vaultRoot: Fixtures.root().appendingPathComponent("vaults/typed")).types.first)
    }

    @Test func createsFromFolderAndTemplateWithExactExpectedBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let definition = try book()
        try await vault.store.savingEntityType(definition)
        try vault.write(
            "templates/book.md",
            String(
                contentsOf: Fixtures.root().appendingPathComponent("vaults/typed/templates/book.md"), encoding: .utf8))
        let path = try await vault.store.creatingEntity(kind: .custom("book"), name: "Yeni Kitap")
        #expect(path == "books/Yeni Kitap.md")
        #expect(
            try vault.bytes(path)
                == Data(contentsOf: Fixtures.root().appendingPathComponent("entity-types/create/expected.md")))
        #expect(try vault.index.entities(named: "Yeni Kitap").first?.kind == "book")
        try vault.check()
    }

    @Test func minimalTemplateAndUnknownTypeRejection() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        var definition = try book()
        definition.template = nil
        definition.folder = "library/books"
        try await vault.store.savingEntityType(definition)
        let path = try await vault.store.creatingEntity(kind: .custom("book"), name: "Kitap")
        #expect(path == "library/books/Kitap.md")
        #expect(try vault.bytes(path) == Data("---\ntype: book\nname: Kitap\n---\n".utf8))
        await #expect(throws: EntityTypeError.unknownType) {
            try await vault.store.creatingEntity(kind: .custom("unknown"), name: "Başka")
        }
    }

    @Test func oneTypeEditPreservesAllUntargetedJSONBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let fixture = try Fixtures.root().appendingPathComponent("entity-types/preserve")
        try vault.write(
            ".app/types.json", String(contentsOf: fixture.appendingPathComponent("input.json"), encoding: .utf8))
        let original = try #require(await vault.store.entityTypes().types.first)
        var changed = original
        changed.name.tr = "Eser"
        try await vault.store.savingEntityType(changed, replacing: original)
        #expect(try vault.bytes(".app/types.json") == Data(contentsOf: fixture.appendingPathComponent("expected.json")))
        let bytes = try vault.bytes(".app/types.json")
        try await vault.store.savingEntityType(changed, replacing: changed)
        #expect(try vault.bytes(".app/types.json") == bytes)
    }

    @Test func deletingDefinitionRetainsMarkdownAndOtherTypeBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let first = try book()
        try await vault.store.savingEntityType(first)
        let second = EntityTypeDefinition(
            id: "album", folder: "albums", name: .init(tr: "Albüm", en: "Album"),
            plural: .init(tr: "Albümler", en: "Albums"), icon: "opticaldisc")
        try await vault.store.savingEntityType(second)
        let path = try await vault.store.creatingEntity(kind: .custom("book"), name: "Kitap")
        let bytes = try vault.bytes(path)
        try await vault.store.deletingEntityType(first)
        #expect(try vault.bytes(path) == bytes)
        #expect(await vault.store.entityTypes().types == [second])
        #expect(try vault.index.files().first?.kind == "note")
        try await vault.store.deletingEntityType(second)
        #expect(await vault.store.entityTypes().types.isEmpty)
        try vault.check()
    }

    @Test func damagedAndStaleSchemasAreNeverOverwritten() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let definition = try book()
        try vault.write(".app/types.json", "{broken")
        await #expect(throws: EntityTypeError.invalidFile) { try await vault.store.savingEntityType(definition) }
        #expect(try vault.bytes(".app/types.json") == Data("{broken".utf8))
        // Only this test's own temporary damaged fixture is removed.
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent(".app/types.json"))
        try await vault.store.savingEntityType(definition)
        var changed = definition
        changed.icon = "books.vertical"
        try await vault.store.savingEntityType(changed, replacing: definition)
        await #expect(throws: EntityTypeError.staleDefinition) {
            try await vault.store.savingEntityType(definition, replacing: definition)
        }
        await #expect(throws: EntityTypeError.staleDefinition) { try await vault.store.deletingEntityType(definition) }
        #expect(await vault.store.entityTypes().types == [changed])
    }

    @Test func symlinkedSchemaFolderAndTemplateCannotEscapeVault() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            atPath: vault.root.appendingPathComponent(".app").path, withDestinationPath: outside.path)
        await #expect(throws: (any Error).self) { try await vault.store.savingEntityType(try book()) }
        #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("types.json").path))
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent(".app"))
        var definition = try book()
        definition.template = nil
        try await vault.store.savingEntityType(definition)
        try FileManager.default.createSymbolicLink(
            atPath: vault.root.appendingPathComponent("books").path, withDestinationPath: outside.path)
        await #expect(throws: VaultStoreError.invalidPath) {
            try await vault.store.creatingEntity(kind: .custom("book"), name: "Kitap")
        }
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("books"))
        var withTemplate = definition
        withTemplate.template = "templates/book.md"
        try await vault.store.savingEntityType(withTemplate, replacing: definition)
        try FileManager.default.createSymbolicLink(
            atPath: vault.root.appendingPathComponent("templates").path, withDestinationPath: outside.path)
        await #expect(throws: VaultStoreError.invalidPath) {
            try await vault.store.creatingEntity(kind: .custom("book"), name: "Başka Kitap")
        }
    }

    @Test func customTemplateTypeIsCorrectedButBodyAndUnknownFieldsRemain() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.savingEntityType(try book())
        try vault.write("templates/book.md", "---\ntype: person # comment\nunknown: 20.0290\n---\nBody\n")
        let path = try await vault.store.creatingEntity(kind: .custom("book"), name: "Kitap")
        #expect(
            try vault.bytes(path) == Data("---\ntype: book # comment\nunknown: 20.0290\nname: Kitap\n---\nBody\n".utf8))
        let result = try await vault.store.renamingEntity(at: path, to: "Yeni Kitap", qualifier: nil)
        #expect(result.path == "books/Yeni Kitap.md")
        #expect(try vault.index.entities(named: "Yeni Kitap").first?.kind == "book")
    }

    @Test func concurrentDefinitionAddsLoseNoTypes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let first = try book()
        let second = EntityTypeDefinition(
            id: "album", folder: "albums", name: .init(tr: "Albüm", en: "Album"),
            plural: .init(tr: "Albümler", en: "Albums"), icon: "opticaldisc")
        async let saveBook: Void = vault.store.savingEntityType(first)
        async let saveAlbum: Void = vault.store.savingEntityType(second)
        _ = try await (saveBook, saveAlbum)
        #expect(Set(await vault.store.entityTypes().types.map(\.id)) == ["book", "album"])
        try vault.check()
    }

    @Test func knownFieldEditRetainsUnknownJSONInsideFieldDefinition() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let fixture = try Fixtures.root().appendingPathComponent("entity-types/preserve")
        let input = try String(contentsOf: fixture.appendingPathComponent("input.json"), encoding: .utf8)
            .replacingOccurrences(
                of: "\"fields\":[]", with: "\"fields\":[{\"key\":\"author\", \"kind\":\"text\", \"future\":20.0290}]",
                range: nil)
        try vault.write(".app/types.json", input)
        let original = try #require(await vault.store.entityTypes().types.first)
        var changed = original
        changed.fields[0].kind = .link
        try await vault.store.savingEntityType(changed, replacing: original)
        let result = try String(contentsOf: vault.root.appendingPathComponent(".app/types.json"), encoding: .utf8)
        #expect(result.contains("\"future\":20.0290"))
        #expect(result.contains("\"kind\":\"link\""))
        #expect(result.contains("\"unknown\" : [1,  2]"))
    }

    @Test func malformedTemplateFailsWithoutCreatingEntity() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.savingEntityType(try book())
        try vault.write("templates/book.md", "---\ntype: book\ntype: person\n---\n")
        await #expect(throws: EntityTypeError.invalidFile) {
            try await vault.store.creatingEntity(kind: .custom("book"), name: "Kitap")
        }
        #expect(try vault.index.files().isEmpty)
    }
}
