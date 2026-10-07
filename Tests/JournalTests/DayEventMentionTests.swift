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

    @Test func eventEditorUnchangedTextDoesNotAskOrRewrite() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        var file = try String(contentsOf: context.file, encoding: .utf8)
        file = file.replacingOccurrences(of: "Existing event", with: "Mert Aksu ile Deniz Arıkan")
        try file.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let prepared = try Data(contentsOf: context.file)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        #expect(model.text == "Mert Aksu ile Deniz Arıkan")
        #expect(await model.save())
        #expect(model.composer.pendingAmbiguity == nil)
        #expect(!model.composer.awaitingResolution)
        #expect(try Data(contentsOf: context.file) == prepared)
    }

    @Test func eventEditorCreateFailureKeepsSaveBlocked() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try Data(contentsOf: context.file)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Yeni Ad ile"
        #expect(await !model.save())
        #expect(model.composer.pendingUnknown != nil)
        // people/ read-only → createEntity fails; save must stay blocked and the event untouched.
        let people = context.root.appendingPathComponent("people")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: people.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: people.path)
        }
        await model.composer.create(.person)
        #expect(model.composer.errorText != nil)
        #expect(model.composer.pendingUnknown != nil)
        #expect(model.composer.pins.isEmpty)
        #expect(await !model.save())
        #expect(try Data(contentsOf: context.file) == before)
    }

    @Test func eventEditorCannotSaveWhileEntityIsBeingCreated() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try Data(contentsOf: context.file)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Yeni Ad ile"
        #expect(await !model.save())
        let creating = Task { await model.composer.create(.person) }
        for _ in 0..<1000 where !model.composer.isCreating { await Task.yield() }
        #expect(model.composer.isCreating)
        #expect(!model.canSave)
        #expect(await !model.save())
        #expect(try Data(contentsOf: context.file) == before)
        await creating.value
        #expect(model.canSave)
        #expect(await model.save())
        #expect(
            RawDocument(bytes: try Data(contentsOf: context.file)).bodyLines.events.first?.block.text
                == "[[Yeni Ad]] ile")
    }

    @Test func overlappingPinIsDroppedWhenNameIsEdited() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Mert"
        let entity = try #require(model.composer.suggestions().first { $0.qualifier == "iş" })
        model.composer.selectSuggestion(entity)
        #expect(model.composer.choices.values.contains(entity.file))
        model.text = "Mert Aks"
        #expect(model.composer.pins.isEmpty)
        // Typing the name back does not revive the choice: the mention is ambiguous again.
        model.text = "Mert Aksu"
        #expect(model.composer.choices.isEmpty)
        #expect(model.composer.mentions.first?.isAmbiguous == true)
    }

    @Test func awaitingResolutionHidesSuggestions() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = "@Mert Aksu"
        #expect(!model.composer.suggestions().isEmpty)
        #expect(await !model.save())
        #expect(model.composer.awaitingResolution)
        #expect(model.composer.suggestions().isEmpty)
        // Editing the text drops the pending question and brings suggestions back.
        model.text = "@Mert Aks"
        #expect(!model.composer.awaitingResolution)
        #expect(!model.composer.suggestions().isEmpty)
    }
}
