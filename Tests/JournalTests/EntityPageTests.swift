import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct EntityPageTests {
    @Test func sampleFieldsAndRawNotesComeFromDisk() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(model.fields.map(\.key) == ["tanışma", "doğum günü"])
        if case .scalar(let scalar) = model.fields[0].value {
            #expect(scalar.kind == .text)
        } else {
            Issue.record("Expected text")
        }
        if case .scalar(let scalar) = model.fields[1].value {
            #expect(scalar.kind == .date(CalendarDate("1990-05-14")!))
        } else {
            Issue.record("Expected date")
        }
        #expect(model.aliases == ["Deniz", "Deniz abi"])
        #expect(model.body.contains("Lise ve üniversiteden arkadaşım."))
    }

    @Test func parsedTypesRawFieldAndBodyArePreserved() async throws {
        let context = try EntityPageTestContext(extendedFields: true)
        defer { context.clean() }
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(model.fields.count == 8)
        let fields = Dictionary(uniqueKeysWithValues: model.fields.map { ($0.key, $0.value) })
        if case .scalar(let value) = fields["weight"] {
            #expect(value.kind == .number)
        } else {
            Issue.record("Expected number")
        }
        if case .scalar(let value) = fields["active"] {
            #expect(value.kind == .boolean(false))
        } else {
            Issue.record("Expected boolean")
        }
        if case .scalar(let value) = fields["empty"] {
            #expect(value.kind == .empty)
        } else {
            Issue.record("Expected empty")
        }
        if case .raw = fields["raw"] {} else { Issue.record("Expected raw") }
        #expect(model.body == "\n# Notes\nRaw **Markdown** and [[Liman Ofis]].\n")
        let bytes = try Data(contentsOf: context.file)
        #expect(await !model.set("raw", to: .text("Changed")))
        #expect(await !model.remove("raw"))
        #expect(try Data(contentsOf: context.file) == bytes)
    }

    @Test func editsOnlySelectedFieldBytesAndNoOpPreservesFile() async throws {
        let context = try EntityPageTestContext(extendedFields: true)
        defer { context.clean() }
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(await model.set("weight", to: .number("30.5000")))
        #expect(try Data(contentsOf: context.file) == Data(contentsOf: context.fixture("value.md")))
        let modified = try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(await model.set("weight", to: .number("30.5")))
        #expect(
            try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(try Data(contentsOf: context.file) == Data(contentsOf: context.fixture("value.md")))
    }

    @Test func aliasesKeepBlockStyleCommentsAndRefreshRecognition() async throws {
        let context = try EntityPageTestContext(extendedFields: true)
        defer { context.clean() }
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(await model.saveAliases(["Deniz", "D.", "Yeni", ""]))
        #expect(try Data(contentsOf: context.file) == Data(contentsOf: context.fixture("aliases.md")))
        #expect(context.store.knownEntities.first { $0.file == context.path }?.aliases == ["Deniz", "D.", "Yeni"])
    }

    @Test func booleanDateListMappingEmptyAdditionAndRemoval() async throws {
        let context = try EntityPageTestContext(extendedFields: true)
        defer { context.clean() }
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(await model.set("active", to: .boolean(true)))
        #expect(await model.set("doğum günü", to: .date(CalendarDate("1991-04-12")!)))
        #expect(await model.setList("coordinates", values: [.number("1"), .number("3.25")]))
        #expect(await model.setEntry("details", entry: "language", value: .text("en")))
        #expect(await model.set("weight", to: .text("")))
        #expect(await model.addField(key: "New field", text: ""))
        #expect(await !model.addField(key: "name", text: "Unsafe"))
        #expect(await !model.addField(key: "New field", text: "Overwrite"))
        #expect(await model.remove("New field"))
        let document = try await context.store.document(at: context.path)
        if case .parsed(let fields) = document.frontmatter {
            #expect(fields.field(named: "New field") == nil)
            if case .scalar(let value) = fields.field(named: "weight")?.value { #expect(value.text.isEmpty) }
        }
        let written = try String(contentsOf: context.file, encoding: .utf8)
        #expect(written.contains("weight: \"\" # precise"))
        #expect(written.contains("coordinates: [1, 3.25]"))
        #expect(written.contains("  language: en\n  level: 2"))
        #expect(written.hasSuffix("\n# Notes\nRaw **Markdown** and [[Liman Ofis]].\n"))
    }

    @Test func canonicallyEquivalentKeysKeepSeparateByteIdentities() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        let original = "---\ntype: person\nname: Deniz Arıkan\né: composed\ne\u{301}: decomposed\n---\nNotes\n"
        try Data(original.utf8).write(to: context.file)
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(model.fields.count == 2)
        #expect(Set(model.fields.map(\.id)).count == 2)
        #expect(await model.set("e\u{301}", to: .text("Changed")))
        #expect(
            try Data(contentsOf: context.file)
                == Data(original.replacingOccurrences(of: "decomposed", with: "Changed").utf8))
    }

    @Test func unreadableFrontmatterIsReadOnlyAndStillShowsBody() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        let data = Data("---\ntype: person\nname: Deniz Arıkan\nname: duplicate\n---\nBody\n".utf8)
        try data.write(to: context.file)
        await context.start()
        let model = EntityDetailModel(store: context.store, path: context.path)
        await model.load()
        #expect(model.unreadableFrontmatter)
        #expect(model.fields.isEmpty)
        #expect(model.body == "Body\n")
        #expect(!model.canEdit)
        #expect(await !model.set("new", to: .text("Value")))
        #expect(try Data(contentsOf: context.file) == data)
    }
}
