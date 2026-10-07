import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct JournalMentionTests {
    @Test func journalEditorSuggestionsMatchQuickEntry() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = model.text + "@De"
        #expect(model.composer.suggestions().map(\.name) == ["Deniz Arıkan"])
        model.text = "prefix name@De"
        #expect(model.composer.suggestions().isEmpty)
    }

    @Test func journalEditorSelectSuggestionLinksOnlyChangedLine() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let original = model.text
        model.text = original.replacingOccurrences(of: "### Notlar", with: "@Mert konuştuk.\n### Notlar")
        let offset = model.text.range(of: "@Mert")!.upperBound
        let byteOffset = model.text[..<offset].utf8.count
        let entity = try #require(
            model.composer.suggestions(at: byteOffset).first { $0.qualifier == "iş" })
        model.composer.selectSuggestion(entity, at: byteOffset)
        #expect(model.text.contains("Mert Aksu konuştuk."))
        #expect(await model.save())
        let bytes = try Data(contentsOf: context.file)
        let body = try JournalRecognition.body(of: RawDocument(bytes: bytes))
        #expect(body.contains("[[Mert Aksu (iş)|Mert Aksu]] konuştuk."))
        #expect(body.contains("Deniz eski satır."))
        #expect(body.contains("[[Liman Ofis]] burada."))
        #expect(body.contains("```swift\nDeniz\n```"))
        #expect(!body.contains("@Mert"))
        #expect(try String(contentsOf: context.file, encoding: .utf8).contains("Untouched section"))
    }

    @Test func journalEditorBlocksExplicitAmbiguityButLeavesBareAmbiguityPlain() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "@Mert Aksu yeni.\n"
        #expect(await !model.save())
        #expect(model.composer.pendingAmbiguity?.isExplicit == true)
        model.composer.skip(try #require(model.composer.pendingAmbiguity))
        #expect(await model.save())
        let resolved = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        #expect(resolved.contains("Mert Aksu yeni."))
        #expect(!resolved.contains("@"))
        #expect(!resolved.contains("[[Mert"))

        let day = try #require(CalendarDate("2026-09-11"))
        let fresh = JournalEditorModel(store: context.store, day: day)
        await fresh.load()
        fresh.text = "Mert Aksu yeni.\n"
        #expect(await fresh.save())
        let saved = try String(
            contentsOf: context.root.appendingPathComponent("journal/\(day).md"), encoding: .utf8)
        #expect(saved.contains("Mert Aksu yeni."))
        #expect(!saved.contains("[[Mert"))
    }
}
