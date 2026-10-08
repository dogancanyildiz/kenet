import EntityRecognition
import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@MainActor
struct QuickEntryMentionTests {
    @Test func suggestionsFilterAliasesAndDisambiguate() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@De"
        #expect(context.model.suggestions().map(\.name) == ["Deniz Arıkan"])
        context.model.text = "@Mert"
        #expect(context.model.suggestions().count == 2)
        #expect(context.model.suggestions().contains { $0.qualifier == "iş" })
        context.model.text = "name@De"
        #expect(context.model.suggestions().isEmpty)
        context.model.text = "(@arı"
        #expect(context.model.suggestions().map(\.name) == ["Deniz Arıkan"])
    }

    @Test func suggestionsSortByDateThenNameAndLimitToSix() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@"
        #expect(context.model.suggestions().count == 6)
        #expect(await context.store.addEvent(text: "[[Deniz Arıkan]]", time: nil))
        #expect(context.model.suggestions().first?.name == "Deniz Arıkan")
        context.model.text = "@Mert"
        #expect(context.model.suggestions().map(\.file) == ["people/Mert Aksu (iş).md", "people/Mert Aksu.md"])

    }

    @Test func certainMentionsPreserveFileBytesAndShowLinks() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "Deniz ile Liman Ofis'te"
        #expect(await context.model.submit(time: try LineClock(hour: 13, minute: 0)))
        let bytes = try context.eventBytes()
        let document = RawDocument(bytes: bytes)
        let event = try #require(document.bodyLines.events.last)
        let id = try #require(event.block.id)
        let expected =
            "---\ntype: journal\ndate: \(LocalDay.today())\n---\n\n## Events\n- 13:00 [[Deniz Arıkan|Deniz]] ile [[Liman Ofis]]'te ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
        #expect(
            context.store.content.day(on: LocalDay.today()).events.last?.text.plainText
                == "Deniz ile Liman Ofis'te")
        #expect(context.model.text.isEmpty)
    }

    @Test func ambiguityCanRemainPlainOrBeChosen() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Mert Aksu ile"
        #expect(await !context.model.submit(time: nil))
        let first = try #require(context.model.pendingAmbiguity)
        context.model.skip(first)
        #expect(await context.model.submit(time: nil))
        context.model.text = "Mert Aksu ile"
        #expect(await !context.model.submit(time: nil))
        let second = try #require(context.model.pendingAmbiguity)
        let entity = try #require(second.candidates.first { $0.qualifier == "iş" })
        context.model.choose(entity, for: second)
        #expect(await context.model.submit(time: nil))
        let events = RawDocument(bytes: try context.eventBytes()).bodyLines.events
        #expect(events.map(\.block.text) == ["Mert Aksu ile", "[[Mert Aksu (iş)|Mert Aksu]] ile"])
    }

    @Test func unknownCreatesPersonAndLinksImmediately() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Ad ile"
        #expect(await !context.model.submit(time: nil))
        await context.model.create(.person)
        #expect(context.store.knownEntities.contains { $0.file == "people/Ad.md" })
        #expect(await context.model.submit(time: nil))
        #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent("people/Ad.md").path))
        #expect(RawDocument(bytes: try context.eventBytes()).bodyLines.events.last?.block.text == "[[Ad]] ile")
        await context.store.refresh(rebuild: true)
        #expect(context.store.knownEntities.contains { $0.file == "people/Ad.md" })
    }

    @Test func sameNameRequestsQualifierAndProducesDistinctFile() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Ad"
        await context.model.beginCreation(.person)
        #expect(await context.model.submit(time: nil))
        context.model.text = "@Ad"
        await context.model.beginCreation(.person)
        #expect(context.model.needsQualifier)
        context.model.qualifier = "iş"
        await context.model.create(.person)
        #expect(await context.model.submit(time: nil))
        #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent("people/Ad (iş).md").path))
        #expect(RawDocument(bytes: try context.eventBytes()).bodyLines.events.last?.block.text == "[[Ad (iş)|Ad]]")
    }

    @Test func lowercaseSuggestionRemainsPlainAndUnknownCanBeDismissed() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "deniz ile"
        #expect(await context.model.submit(time: nil))
        context.model.text = "@Yeni Ad ile"
        #expect(await !context.model.submit(time: nil))
        context.model.dismissUnknown(try #require(context.model.pendingUnknown))
        #expect(await context.model.submit(time: nil))
        #expect(
            RawDocument(bytes: try context.eventBytes()).bodyLines.events.map(\.block.text) == [
                "deniz ile", "Yeni Ad ile",
            ])
    }

    @Test func comparisonUsesCanonicalUnicodeAndCaseInsensitiveAliases() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        _ = try await context.store.createEntity(kind: .place, name: "Élan", qualifier: nil)
        context.model.text = "@E\u{301}L"
        #expect(context.model.suggestions().map(\.name) == ["Élan"])
        context.model.text = "@DENIZ AB"
        #expect(context.model.suggestions().map(\.name) == ["Deniz Arıkan"])
    }

    @Test func onDiskCollisionRequestsQualifierWithoutReplacingFile() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("people/Ad.md")
        let original = Data("---\ntype: person\nname: Ad\n---\n\nUntouched\n".utf8)
        try original.write(to: file)
        context.model.text = "@Ad"
        #expect(await !context.model.submit(time: nil))
        await context.model.create(.person)
        #expect(context.model.needsQualifier)
        context.model.qualifier = "iş"
        await context.model.create(.person)
        #expect(await context.model.submit(time: nil))
        #expect(try Data(contentsOf: file) == original)
        #expect(RawDocument(bytes: try context.eventBytes()).bodyLines.events.last?.block.text == "[[Ad (iş)|Ad]]")
    }

    @Test func unknownPlaceIsCreatedAndRecognizedOnLaterEntry() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Yeni Liman'da"
        #expect(await !context.model.submit(time: nil))
        await context.model.create(.place)
        #expect(await context.model.submit(time: nil))
        context.model.text = "Yeni Liman'da"
        #expect(await context.model.submit(time: nil))
        #expect(
            RawDocument(bytes: try context.eventBytes()).bodyLines.events.map(\.block.text) == [
                "[[Yeni Liman]]'da", "[[Yeni Liman]]'da",
            ])
    }

    @Test func selectionAtCursorPreservesTrailingText() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Mert ile konuştum"
        let offset = "@Mert".utf8.count
        let entity = try #require(context.model.suggestions(at: offset).first { $0.qualifier == "iş" })
        context.model.selectSuggestion(entity, at: offset)
        #expect(context.model.text == "Mert Aksu ile konuştum")
        #expect(await context.model.submit(time: nil))
        #expect(
            RawDocument(bytes: try context.eventBytes()).bodyLines.events.last?.block.text
                == "[[Mert Aksu (iş)|Mert Aksu]] ile konuştum")
    }

    @Test func failedEventWriteRetainsDraftAndPinnedChoice() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Mert"
        let entity = try #require(context.model.suggestions().first { $0.qualifier == "iş" })
        context.model.selectSuggestion(entity)
        let original = Data([0xFF, 0xFE])
        try original.write(to: context.root.appendingPathComponent("journal/\(LocalDay.today()).md"))
        #expect(await !context.model.submit(time: nil))
        #expect(context.model.text == "Mert Aksu")
        #expect(context.model.choices.values.contains(entity.file))
        #expect(try context.eventBytes() == original)
        #expect(context.store.entryErrorText != nil)
    }

    @Test func externalIndexRefreshUpdatesKnownEntities() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        let file = context.root.appendingPathComponent("people/Yeni Ad.md")
        try Data("---\ntype: person\nname: Yeni Ad\naliases: [Yeni]\n---\n".utf8).write(to: file)
        await context.store.refresh()
        context.model.text = "@Yeni"
        #expect(context.model.suggestions().map(\.name) == ["Yeni Ad"])
        #expect(context.store.entityUsage.contains { $0.file == "people/Yeni Ad.md" })
    }

    @Test func pinnedChoiceSurvivesPrefixEditButNotNameEdit() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.text = "@Mert"
        let entity = try #require(context.model.suggestions().first { $0.qualifier == "iş" })
        context.model.selectSuggestion(entity)
        context.model.text = "Bugün " + context.model.text
        #expect(context.model.choices.values.contains(entity.file))
        context.model.text = "Bugün Mert Aksu ve Mert Aksu"
        #expect(context.model.choices.count == 1)
        context.model.text = "Bugün Mert Aks ve Mert Aksu"
        #expect(context.model.choices.isEmpty)
    }

    @Test func dismissUnknownResetsManualTaskDateOverride() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.mode = .task
        context.model.text = "@Yarın toplantı"
        context.model.overridesDate = true
        context.model.manualDueDate = LocalDay.today()
        #expect(await !context.model.submit(time: nil))
        // The strip edits through the composer, as the "Vazgeç" button does.
        context.model.composer.dismissUnknown(try #require(context.model.pendingUnknown))
        #expect(!context.model.overridesDate)
        #expect(context.model.manualDueDate == nil)
        #expect(context.model.text == "Yarın toplantı")
    }

    @Test func suggestionThatChangesTheDateResetsManualTaskDateOverride() async throws {
        let context = try MentionTestContext()
        defer { context.clean() }
        await context.start()
        context.model.mode = .task
        context.model.text = "yarın @De"
        context.model.overridesDate = true
        context.model.manualDueDate = LocalDay.today()
        let entity = try #require(context.model.composer.suggestions().first)
        // The date expression is unchanged by the suggestion: the manual date stays.
        context.model.composer.selectSuggestion(entity)
        #expect(context.model.overridesDate)
        context.model.composer.replace(0..<"yarın".utf8.count, with: "bugün")
        #expect(!context.model.overridesDate)
        #expect(context.model.manualDueDate == nil)
    }
}

@MainActor
private struct MentionTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    let model: QuickEntryModel

    init() throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("sample")
        defaults = try TestDefaults()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/sample")
        try FileManager.default.copyItem(at: fixture, to: root)
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
        model = QuickEntryModel(store: store)
    }

    func start() async { await store.select(root) }
    func eventBytes() throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("journal/\(LocalDay.today()).md"))
    }
    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
