import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct CustomEntityTypeTests {
    @Test func selectorModelIncludesLocalizedCustomTypesAndFallsBackAfterRemoval() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        await context.store.select(context.root)
        #expect(context.store.errorText == nil)
        let choices = EntityTypeChoices.choices(context.store.entityTypes, language: "en")
        #expect(choices.map(\.id) == ["person", "place", "book"])
        #expect(choices.last?.name == "Book" && choices.last?.plural == "Books")
        #expect(choices.last?.kind == .custom("book"))
        #expect(EntityTypeChoices.choices(context.store.entityTypes, language: "tr").last?.plural == "Kitaplar")
        #expect(EntityTypeChoices.selection("book", in: context.store.entityTypes) == "book")
        #expect(EntityTypeChoices.selection("removed", in: context.store.entityTypes) == "person")
        #expect(context.store.content.entities.count == 2)
        #expect(context.store.content.graphInput.entities.isEmpty)
        #expect(
            EntityListQuery.entities(in: context.store.content, usage: [], kind: "book", search: "orman", order: .name)
                .count == 1)
    }

    @Test func suggestionsRecognitionAndCreationIncludeCustomTypes() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        await context.store.select(context.root)
        let entry = QuickEntryModel(store: context.store)
        entry.text = "@Cam"
        #expect(entry.suggestions().first?.kind == .custom("book"))
        let mentions = EntityRecognizer.recognize("@Cam Ormanı", entities: context.store.knownEntities)
        #expect(mentions.first?.candidates.first?.kind == .custom("book"))
        entry.text = "@Yeni Kitap"
        await entry.beginCreation(.custom("book"))
        #expect(context.store.content.entities.contains { $0.kind == "book" && $0.name == "Yeni Kitap" })
        #expect(entry.mentions.first?.isCertain == true)
    }

    @Test func editorSavesSchemaAndDeletingNeverDeletesMarkdown() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        await context.store.select(context.root)
        let editor = EntityTypeEditorModel(store: context.store)
        editor.id = "album"
        editor.folder = "albums"
        editor.nameTR = "Albüm"
        editor.nameEN = "Album"
        editor.pluralTR = "Albümler"
        editor.pluralEN = "Albums"
        editor.fields = [EntityTypeFieldDraft(key: "sanatçı", kind: .text)]
        #expect(editor.canSave)
        #expect(await editor.save())
        struct File: Decodable {
            let formatVersion: Int
            let types: [EntityTypeDefinition]
        }
        let disk = try JSONDecoder().decode(
            File.self, from: Data(contentsOf: context.root.appendingPathComponent(".app/types.json")))
        #expect(disk.formatVersion == 1 && disk.types.map(\.id) == ["book", "album"])
        let book = try #require(context.store.entityTypes.types.first)
        let before = try Data(contentsOf: context.root.appendingPathComponent("books/Cam Ormanı.md"))
        try await context.store.deleteEntityType(book)
        #expect(try Data(contentsOf: context.root.appendingPathComponent("books/Cam Ormanı.md")) == before)
        #expect(context.store.knownEntities.isEmpty && context.store.content.entities.isEmpty)
        #expect(EntityTypeChoices.selection("book", in: context.store.entityTypes) == "person")
    }

    @Test func typedFieldValuesAndMismatchesAreHandledWithoutCoercion() throws {
        #expect(try EntityTypedField.literal("240", kind: .number) == .number("240"))
        #expect(throws: EntityTypeError.self) { try EntityTypedField.literal("NaN", kind: .number) }
        #expect(try EntityTypedField.literal("2026-09-20", kind: .date) == .date(CalendarDate("2026-09-20")!))
        #expect(throws: EntityTypeError.self) { try EntityTypedField.literal("2026-02-30", kind: .date) }
        #expect(try EntityTypedField.literal("false", kind: .boolean) == .boolean(false))
        #expect(try EntityTypedField.literal("Cam Ormanı", kind: .link) == .text("[[Cam Ormanı]]"))
        #expect(throws: EntityTypeError.self) { try EntityTypedField.literal("[[One]] [[Two]]", kind: .link) }
        #expect(EntityTypedField.supports(nil, kind: .date))
        let document = RawDocument(bytes: Array("---\nyazar: Ada Merin\n---\n".utf8))
        guard case .parsed(let fields) = document.frontmatter else {
            Issue.record("Missing frontmatter")
            return
        }
        #expect(!EntityTypedField.supports(fields.field(named: "yazar")?.value, kind: .date))
        #expect(EntityTypedField.supports(fields.field(named: "yazar")?.value, kind: .text))
    }

    @Test func detailEditKeepsUnknownFieldsAndCustomSearchRoutesToEntity() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        await context.store.select(context.root)
        let path = "books/Cam Ormanı.md"
        let detail = EntityDetailModel(store: context.store, path: path)
        await detail.load()
        #expect(detail.canEdit)
        #expect(await detail.set("sayfa", to: .number("250")))
        let after = try String(contentsOf: context.root.appendingPathComponent(path), encoding: .utf8)
        #expect(after.contains("unknown: 20.0290 # korunur") && after.contains("sayfa: 250"))
        let matches = try await context.store.search("Cam")
        let results = SearchResults.build(query: "Cam", entities: context.store.content.entities, matches: matches)
        #expect(results.first?.group == .entities)
        #expect(results.first?.destination == .entity(path))
    }

    @Test func editorCannotSaveIntoAChangedVault() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        await context.store.select(context.root)
        let definition = try #require(context.store.entityTypes.types.first)
        let editor = EntityTypeEditorModel(store: context.store, original: definition)
        #expect(editor.canSave)
        let other = context.directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(context.store.canAddEvent)
        #expect(!editor.canSave)
        #expect(!(await editor.save()))
        #expect(!FileManager.default.fileExists(atPath: other.appendingPathComponent(".app/types.json").path))
    }

    @Test func brokenSchemaIsVisibleAndBuiltinsRemainAvailable() async throws {
        let context = try TypedEntityContext()
        defer { context.clean() }
        try Data("{broken".utf8).write(to: context.root.appendingPathComponent(".app/types.json"))
        await context.store.select(context.root)
        #expect(context.store.entityTypes.issue != nil)
        #expect(EntityTypeChoices.choices(context.store.entityTypes).map(\.id) == ["person", "place"])
        #expect(context.store.knownEntities.isEmpty)
    }
}

@MainActor private struct TypedEntityContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    init() throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("typed")
        defaults = try TestDefaults()
        var ancestor = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: ancestor.appendingPathComponent("Fixtures/vaults/typed").path) {
            guard ancestor.path != "/" else { throw CocoaError(.fileNoSuchFile) }
            ancestor.deleteLastPathComponent()
        }
        try FileManager.default.copyItem(at: ancestor.appendingPathComponent("Fixtures/vaults/typed"), to: root)
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }
    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
