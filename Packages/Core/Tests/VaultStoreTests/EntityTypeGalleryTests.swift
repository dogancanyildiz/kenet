import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// The ready-made type gallery against `Fixtures/vaults/gallery/`: the definitions, the
/// template files and one entity created from each template, all written by hand.
struct EntityTypeGalleryTests {
    /// The entity name created per type; the fixture file is `<folder>/<name>.md`.
    private static let names = [
        "book": "Örnek Kitap", "film": "Örnek Film", "organization": "Örnek Kurum", "project": "Örnek Proje",
        "event": "Örnek Etkinlik", "trip": "Örnek Seyahat", "recipe": "Örnek Tarif", "product": "Örnek Ürün",
        "pet": "Örnek Evcil Hayvan", "vehicle": "Örnek Araç",
    ]

    private static func vault() throws -> URL { try Fixtures.root().appendingPathComponent("vaults/gallery") }

    @Test func galleryMatchesTheFixtureDefinitionsAndTemplates() throws {
        let catalog = EntityTypeReader.read(vaultRoot: try Self.vault())
        #expect(catalog.issue == nil)
        #expect(catalog.types == EntityTypeGallery.items.map(\.definition))
        for item in EntityTypeGallery.items {
            let template = try Data(
                contentsOf: Self.vault().appendingPathComponent("templates/\(item.definition.id).md"))
            #expect(Data(item.template.utf8) == template, "\(item.definition.id)")
        }
    }

    @Test func galleryTypesAreValidUniqueAndOutsideTheReservedIDs() throws {
        let definitions = EntityTypeGallery.items.map(\.definition)
        #expect(definitions.count == 10)
        try EntityTypesFile(types: definitions).validate()
        #expect(Set(definitions.map(\.id)).count == 10)
        #expect(Set(definitions.map { $0.folder.lowercased() }).count == 10)
        for item in EntityTypeGallery.items {
            #expect(!item.isTaken(by: EntityTypeDefinition.builtIns), "\(item.definition.id)")
            #expect((3...5).contains(item.definition.fields.count), "\(item.definition.id)")
            #expect(item.definition.fields.allSatisfy { $0.key.utf8.allSatisfy { $0 < 128 } })
            #expect(item.definition.template == "templates/\(item.definition.id).md")
        }
    }

    @Test(arguments: EntityTypeGallery.items)
    func templateParsesAndRoundTripsByteForByte(_ item: EntityTypeGalleryItem) throws {
        let bytes = Array(item.template.utf8)
        let document = RawDocument(bytes: bytes)
        #expect(document.serialized() == bytes)
        guard case .parsed(let frontmatter) = document.frontmatter else {
            Issue.record("\(item.definition.id): frontmatter not parsed")
            return
        }
        #expect(frontmatter.fields.map(\.key) == ["type", "name"] + item.definition.fields.map(\.key))
        guard case .scalar(let type) = frontmatter.field(named: "type")?.value else {
            Issue.record("\(item.definition.id): no type")
            return
        }
        #expect(type.text == item.definition.id)
    }

    @Test func takenByTheSameIDOrFolderIgnoringCase() throws {
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" })
        let sameID = EntityTypeDefinition(
            id: "book", folder: "library", name: .init(tr: "A", en: "A"), plural: .init(tr: "A", en: "A"), icon: "a")
        let sameFolder = EntityTypeDefinition(
            id: "novel", folder: "Books", name: .init(tr: "A", en: "A"), plural: .init(tr: "A", en: "A"), icon: "a")
        let other = EntityTypeDefinition(
            id: "novel", folder: "library/books", name: .init(tr: "A", en: "A"), plural: .init(tr: "A", en: "A"),
            icon: "a")
        #expect(book.isTaken(by: [sameID]))
        #expect(book.isTaken(by: [sameFolder]))
        #expect(!book.isTaken(by: [other]))
        #expect(!book.isTaken(by: []))
    }

    @Test(arguments: EntityTypeGallery.items)
    func createsTheTypeTemplateAndAnEntityWithExactBytes(_ item: EntityTypeGalleryItem) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let id = item.definition.id
        try await vault.store.creatingEntityType(item.definition)
        #expect(await vault.store.entityTypes().types == [item.definition])
        let templatePath = "templates/\(id).md"
        #expect(try vault.bytes(templatePath) == Data(contentsOf: Self.vault().appendingPathComponent(templatePath)))
        let name = try #require(Self.names[id])
        let path = try await vault.store.creatingEntity(kind: .custom(id), name: name)
        #expect(path == "\(item.definition.folder)/\(name).md")
        #expect(try vault.bytes(path) == Data(contentsOf: Self.vault().appendingPathComponent(path)))
        #expect(try vault.index.entities(named: name).map(\.kind) == [id])
        #expect(try !vault.index.files().contains { $0.path.hasPrefix("templates/") })
        try vault.check()
    }

    @Test func theUsersTemplateIsKeptAndNoFileIsWrittenOutsideTemplates() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" })
        try vault.write("templates/book.md", "---\ntype: book\nname:\nkendi:\n---\nKendi şablonum.\n")
        try await vault.store.creatingEntityType(book.definition)
        #expect(
            try vault.bytes("templates/book.md") == Data("---\ntype: book\nname:\nkendi:\n---\nKendi şablonum.\n".utf8))

    }

    /// A template path the app does not write (outside `templates/`, or the `Templates/` spelling)
    /// keeps the saved definition but is reported, never silently skipped.
    @Test(arguments: ["films/_sablon.md", "Templates/film.md"])
    func aTemplatePathOutsideTemplatesIsReportedAndNotWritten(_ path: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        var outside = try #require(EntityTypeGallery.items.first { $0.definition.id == "film" }).definition
        outside.template = path
        await #expect {
            try await vault.store.creatingEntityType(outside)
        } throws: { error in
            (error as? EntityTypeTemplateError)?.path == path
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: vault.root.path).sorted() == [".app"])
        #expect(await vault.store.entityTypes().types == [outside])
    }

    /// A template still downloading is the user's: nothing is written beside it, and the caller
    /// learns that the template was not created.
    @Test func aDownloadingTemplateIsKeptAndReported() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" }).definition
        try vault.write("templates/.book.md.icloud", "placeholder")
        await #expect(throws: EntityTypeTemplateError.self) { try await vault.store.creatingEntityType(book) }
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent("templates/book.md").path))
        #expect(try vault.bytes("templates/.book.md.icloud") == Data("placeholder".utf8))
        #expect(await vault.store.entityTypes().types == [book])
    }

    /// When both the definition's index update and the template fail, the index failure wins:
    /// it is the one the app must repair (rebuild).
    @Test func anIndexFailureTakesPrecedenceOverATemplateFailure() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("notes/Not.md", "Not.\n")
        try vault.index.refresh(vaultRoot: vault.root)
        try await vault.index.database.write {
            for event in ["INSERT", "UPDATE", "DELETE"] {
                try $0.execute(
                    sql: "CREATE TRIGGER fail_\(event) BEFORE \(event) ON files BEGIN SELECT RAISE(FAIL, 'test'); END")
            }
        }
        var film = try #require(EntityTypeGallery.items.first { $0.definition.id == "film" }).definition
        film.template = "films/_sablon.md"
        await #expect {
            try await vault.store.creatingEntityType(film)
        } throws: { error in
            guard case VaultStoreError.indexUpdateFailed = error else { return false }
            return true
        }
        #expect(await vault.store.entityTypes().types == [film])
    }

    /// An item edited before saving (id, fields) gets a template of the edited definition.
    @Test func theStarterTemplateFollowsTheSavedDefinition() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" }).definition
        let edited = EntityTypeDefinition(
            id: "kitap", folder: "kitaplar", name: book.name, plural: book.plural, icon: book.icon,
            fields: [EntityTypeField(key: "yazar", kind: .link), EntityTypeField(key: "okundu", kind: .boolean)],
            template: "templates/sub/kitap.md")
        try await vault.store.creatingEntityType(edited)
        #expect(
            try vault.bytes("templates/sub/kitap.md") == Data("---\ntype: kitap\nname:\nyazar:\nokundu:\n---\n".utf8))
    }

    @Test func aRefusedDefinitionWritesNoTemplate() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" })
        try vault.write(".app/types.json", "{broken")
        await #expect(throws: EntityTypeError.invalidFile) {
            try await vault.store.creatingEntityType(book.definition)
        }
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent("templates").path))
        #expect(try vault.bytes(".app/types.json") == Data("{broken".utf8))
    }

    @Test func aCaseVariantTemplatesFolderIsRefusedAfterTheDefinitionIsSaved() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let book = try #require(EntityTypeGallery.items.first { $0.definition.id == "book" })
        try FileManager.default.createDirectory(
            at: vault.root.appendingPathComponent("Templates"), withIntermediateDirectories: true)
        await #expect(throws: EntityTypeTemplateError.self) {
            try await vault.store.creatingEntityType(book.definition)
        }
        #expect(await vault.store.entityTypes().types == [book.definition])
        let names = try FileManager.default.contentsOfDirectory(
            atPath: vault.root.appendingPathComponent("Templates").path)
        #expect(names.isEmpty)
    }
}
