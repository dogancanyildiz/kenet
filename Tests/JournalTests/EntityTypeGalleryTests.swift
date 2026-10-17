import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The type gallery and "Yeni <tip>" through the app layer, on copies of
/// `Fixtures/vaults/typed/` (a book type with a template) and an empty vault.
@MainActor struct EntityTypeGalleryTests {
    private static func item(_ id: String) throws -> EntityTypeGalleryItem {
        try #require(EntityTypeGallery.items.first { $0.definition.id == id })
    }

    // MARK: - Gallery rows

    @Test func rowsMarkTypesWhoseIDOrFolderIsTaken() throws {
        let movie = EntityTypeDefinition(
            id: "movie", folder: "Films", name: .init(tr: "Sinema", en: "Movie"),
            plural: .init(tr: "Sinema", en: "Movies"), icon: "film")
        let book = try Self.item("book").definition
        let rows = EntityTypeGalleryRows.rows(EntityTypeCatalog(types: [book, movie]), language: "en")
        #expect(rows.map(\.id) == EntityTypeGallery.items.map(\.definition.id))
        #expect(rows.filter(\.isTaken).map(\.id) == ["book", "film"])
        #expect(rows.first?.name == "Book")
        #expect(rows.first?.fieldSummary == "yazar, sayfa, puan, bitirme")
        #expect(EntityTypeGalleryRows.rows(EntityTypeCatalog(), language: "tr").allSatisfy { !$0.isTaken })
        #expect(EntityTypeGalleryRows.rows(EntityTypeCatalog(), language: "tr").last?.name == "Araç")
    }

    @Test func entryIsOffWhileTheSchemaIsUnreadable() async throws {
        let context = try GalleryVaultContext(fixture: "typed")
        defer { context.clean() }
        await context.store.select(context.root)
        #expect(EntityTypeGalleryEntry.isEnabled(context.store))
        try Data("{broken".utf8).write(to: context.root.appendingPathComponent(".app/types.json"))
        await context.store.refresh(rebuild: true)
        #expect(context.store.entityTypes.issue != nil)
        #expect(!EntityTypeGalleryEntry.isEnabled(context.store))
    }

    // MARK: - "Yeni <tip>"

    @Test func customTypeListGetsItsOwnCreateRow() throws {
        let book = try Self.item("book").definition
        let types = EntityTypeCatalog(types: [book])
        #expect(EntityCreateEntry.kind(forList: "book", types: types) == .custom("book"))
        #expect(EntityCreateEntry.kind(forList: "film", types: types) == nil)
        #expect(EntityCreateEntry.kind(forList: "person", types: types) == .person)
        #expect(EntityCreateEntry.identifier(.custom("book")) == "button.entities.create.book")
        #expect(EntityCreateEntry.identifier(.person) == "button.entities.createPerson")
        #expect(EntityCreateEntry.systemImage(.custom("book"), types: types) == "book.closed.fill")
        // "Yeni kitap" / "New book": the singular name, lowercased, in the second slot.
        #expect(EntityCreateEntry.title(.custom("book"), types: types, language: "tr").hasSuffix(" kitap"))
        #expect(EntityCreateEntry.title(.custom("book"), types: types, language: "en").hasSuffix(" book"))
        #expect(EntityCreateEntry.title(.person, types: types) == String(localized: "Yeni kişi"))
    }

    @Test func phraseLowercasesOnlyAnOrdinaryFirstLetter() {
        #expect(EntityCreateEntry.inPhrase("Evcil hayvan", language: "tr") == "evcil hayvan")
        #expect(EntityCreateEntry.inPhrase("İlaç", language: "tr") == "ilaç")
        #expect(EntityCreateEntry.inPhrase("Ilık su", language: "tr") == "ılık su")
        #expect(EntityCreateEntry.inPhrase("Book", language: "en") == "book")
        #expect(EntityCreateEntry.inPhrase("BMW", language: "en") == "BMW")
        #expect(EntityCreateEntry.inPhrase("", language: "tr") == "")
    }

    /// The custom kind is written from the type's template (`Fixtures/entity-types/create/`),
    /// and a second entity of that name asks for a qualifier, as people and places do.
    @Test func createsACustomEntityFromItsTemplate() async throws {
        let context = try GalleryVaultContext(fixture: "typed")
        defer { context.clean() }
        await context.store.select(context.root)
        let model = EntityCreationModel(store: context.store, kind: .custom("book"))
        #expect(model.title.hasSuffix(" kitap") || model.title.hasSuffix(" book"))
        model.name = "Yeni Kitap"
        let entity = try #require(await model.save())
        #expect(entity.id == "books/Yeni Kitap.md")
        #expect(entity.kind == "book")
        #expect(
            try Data(contentsOf: context.root.appendingPathComponent(entity.id))
                == Data(
                    contentsOf: GalleryVaultContext.fixtures.appendingPathComponent("entity-types/create/expected.md")))
        #expect(context.store.content.entities.contains { $0.id == entity.id && $0.kind == "book" })

        let again = EntityCreationModel(store: context.store, kind: .custom("book"))
        again.name = "Yeni Kitap"
        #expect(again.needsQualifier && !again.canSave)
        again.qualifier = "Kurgusal kulüp"
        let second = try #require(await again.save())
        #expect(second.id == "books/Yeni Kitap (Kurgusal kulüp).md")
    }

    // MARK: - Saving a gallery type

    /// The editor opens filled with the item as a new type; saving writes the definition and the
    /// template, the picker can select the type, and its first entity matches the fixture.
    @Test func galleryDraftSavesTypeAndTemplate() async throws {
        let context = try GalleryVaultContext(fixture: nil)
        defer { context.clean() }
        await context.store.select(context.root)
        let film = try Self.item("film").definition
        let editor = EntityTypeEditorModel(store: context.store, draft: film)
        #expect(editor.original == nil)
        #expect(editor.definition == film)
        #expect(!EntityTypeDraftSnapshot(editor).isDirty(since: EntityTypeDraftSnapshot(editor)))
        #expect(editor.canSave)
        #expect(await editor.save())
        #expect(context.store.entityTypes.types == [film])
        #expect(EntityTypeChoices.selection("film", in: context.store.entityTypes) == "film")
        #expect(
            try context.bytes("templates/film.md")
                == Data(
                    contentsOf: GalleryVaultContext.fixtures.appendingPathComponent("vaults/gallery/templates/film.md"))
        )
        #expect(
            EntityTypeGalleryRows.rows(context.store.entityTypes, language: "tr").filter(\.isTaken).map(\.id) == [
                "film"
            ])

        let create = EntityCreationModel(store: context.store, kind: .custom("film"))
        create.name = "Örnek Film"
        let entity = try #require(await create.save())
        #expect(
            try context.bytes(entity.id)
                == Data(
                    contentsOf: GalleryVaultContext.fixtures.appendingPathComponent(
                        "vaults/gallery/films/Örnek Film.md")))
    }

    /// An existing template is the user's: it stays, and the type uses it.
    @Test func galleryDraftKeepsAnExistingTemplate() async throws {
        let context = try GalleryVaultContext(fixture: "typed")
        defer { context.clean() }
        try FileManager.default.removeItem(at: context.root.appendingPathComponent(".app/types.json"))
        await context.store.select(context.root)
        let before = try context.bytes("templates/book.md")
        let editor = EntityTypeEditorModel(store: context.store, draft: try Self.item("book").definition)
        #expect(await editor.save())
        #expect(try context.bytes("templates/book.md") == before)
    }

    /// The definition is saved and published even when its template cannot be written; the
    /// sheet stays open with the reason, and saving again only edits the type.
    @Test func unwrittenTemplateKeepsTheSavedTypeAndSaysSo() async throws {
        let context = try GalleryVaultContext(fixture: "typed")
        defer { context.clean() }
        try FileManager.default.createSymbolicLink(
            atPath: context.root.appendingPathComponent("templates/film.md").path,
            withDestinationPath: context.directory.appendingPathComponent("outside.md").path)
        await context.store.select(context.root)
        let film = try Self.item("film").definition
        let editor = EntityTypeEditorModel(store: context.store, draft: film)
        #expect(!(await editor.save()))
        #expect(editor.errorText == String(localized: "Tip kaydedildi, şablon dosyası yazılamadı."))
        #expect(editor.original == film)
        #expect(context.store.entityTypes.types.map(\.id) == ["book", "film"])
        #expect(!FileManager.default.fileExists(atPath: context.directory.appendingPathComponent("outside.md").path))
        #expect(await editor.save())
    }

    /// A path outside `templates/` is flagged in the form before saving, and saving says the
    /// template was not written while the type is saved.
    @Test func templatePathOutsideTemplatesIsFlaggedAndReported() async throws {
        let context = try GalleryVaultContext(fixture: nil)
        defer { context.clean() }
        await context.store.select(context.root)
        let editor = EntityTypeEditorModel(store: context.store, draft: try Self.item("film").definition)
        #expect(!editor.templateIsNotWritten)
        editor.template = "sablonlar/film.md"
        #expect(editor.templateIsNotWritten)
        editor.template = ""
        #expect(!editor.templateIsNotWritten)
        editor.template = "Templates/film.md"
        #expect(editor.templateIsNotWritten)
        #expect(!(await editor.save()))
        #expect(editor.errorText == String(localized: "Tip kaydedildi, şablon dosyası yazılamadı."))
        #expect(context.store.entityTypes.types.map(\.id) == ["film"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: context.root.path).sorted() == [".app"])
        // An existing type is only edited; its template path is never written, so nothing to flag.
        #expect(!EntityTypeEditorModel(store: context.store, original: editor.definition).templateIsNotWritten)
    }

    /// A gallery draft's template follows its id until the user names the template.
    @Test func galleryTemplatePathFollowsTheIDUntilEdited() throws {
        let context = try GalleryVaultContext(fixture: nil)
        defer { context.clean() }
        let editor = EntityTypeEditorModel(store: context.store, draft: try Self.item("book").definition)
        editor.id = "kitap"
        #expect(editor.template == "templates/kitap.md")
        editor.id = " roman "
        #expect(editor.definition.template == "templates/roman.md")
        editor.template = "templates/okuma.md"
        editor.id = "okuma-listesi"
        #expect(editor.template == "templates/okuma.md")

        let blank = EntityTypeEditorModel(store: context.store, draft: nil)
        blank.template = "templates/x.md"
        blank.id = "y"
        #expect(blank.template == "templates/x.md")
    }

    /// The phrase and the name come from the same language, whatever the process language.
    @Test func createTitleUsesOneLanguage() throws {
        let types = EntityTypeCatalog(types: [try Self.item("book").definition])
        #expect(EntityCreateEntry.title(.custom("book"), types: types, language: "tr") == "Yeni kitap")
        #expect(EntityCreateEntry.title(.custom("book"), types: types, language: "en") == "New book")
        #expect(EntityCreateEntry.title(.person, types: types, language: "en") == "New person")
        #expect(EntityCreateEntry.title(.place, types: types, language: "tr") == "Yeni konum")
    }

    /// "Boş tip…" keeps today's blank editor: nothing filled, no template path.
    @Test func blankDraftOpensAnEmptyNewType() throws {
        let context = try GalleryVaultContext(fixture: nil)
        defer { context.clean() }
        let editor = EntityTypeEditorModel(store: context.store, draft: nil)
        #expect(editor.original == nil && editor.id.isEmpty && editor.template.isEmpty && editor.fields.isEmpty)
        #expect(editor.icon == "square.stack")
    }
}

/// A copy of one `Fixtures/vaults/<name>/` vault (or an empty one) with its own store.
@MainActor private struct GalleryVaultContext {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures")
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore

    init(fixture: String?) throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("gallery-vault")
        defaults = try TestDefaults()
        if let fixture {
            try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("vaults/" + fixture), to: root)
        } else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func bytes(_ path: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(path)) }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
