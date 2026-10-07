import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct DayEventMentionTests {
    @Test func eventEditorSuggestionsMatchQuickEntry() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@De"
        #expect(model.composer.suggestions().map(\.name) == ["Deniz Arıkan"])
        model.text = "name@De"
        #expect(model.composer.suggestions().isEmpty)
    }

    @Test func eventEditorSelectSuggestionLinksOnSaveAndPreservesOtherBytes() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try String(contentsOf: context.file, encoding: .utf8)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Mert ile"
        let offset = "@Mert".utf8.count
        let entity = try #require(model.composer.suggestions(at: offset).first { $0.qualifier == "iş" })
        model.composer.selectSuggestion(entity, at: offset)
        #expect(model.text == "Mert Aksu ile")
        #expect(await model.save())
        let after = try String(contentsOf: context.file, encoding: .utf8)
        #expect(after.contains("[[Mert Aksu (iş)|Mert Aksu]] ile"))
        #expect(after.contains("Untouched continuation"))
        #expect(after.contains("## Journal"))
        #expect(after.contains("Untouched section"))
        #expect(!after.contains("@Mert"))
        let expected = before.replacingOccurrences(
            of: "Existing event", with: "[[Mert Aksu (iş)|Mert Aksu]] ile")
        #expect(after == expected)
    }

    @Test func eventEditorBlocksSaveOnAmbiguousMentionUntilChosen() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try Data(contentsOf: context.file)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Mert Aksu ile"
        #expect(await !model.save())
        #expect(model.composer.pendingAmbiguity != nil)
        #expect(try Data(contentsOf: context.file) == before)
        let entity = try #require(model.composer.pendingAmbiguity?.candidates.first { $0.qualifier == "iş" })
        model.composer.choose(entity, for: try #require(model.composer.pendingAmbiguity))
        #expect(await model.save())
        #expect(
            RawDocument(bytes: try Data(contentsOf: context.file)).bodyLines.events.first?.block.text
                == "[[Mert Aksu (iş)|Mert Aksu]] ile")
    }
}
