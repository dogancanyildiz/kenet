import EntityRecognition
import Foundation
import SwiftUI
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

    @Test func bareAmbiguityDoesNotHideLaterExplicitUnknown() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "Mert Aksu dün geldi.\n@Zeynep Yeni bugün geldi.\n"
        #expect(await !model.save())
        #expect(model.composer.pendingAmbiguity == nil)
        #expect(model.composer.pendingUnknown?.spelling == "Zeynep Yeni")
        model.composer.dismissUnknown(try #require(model.composer.pendingUnknown))
        #expect(await model.save())
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        #expect(body.contains("Zeynep Yeni bugün geldi."))
        #expect(!body.contains("@"))
    }

    @Test func bareAmbiguityDoesNotHideLaterExplicitAmbiguity() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "Mert Aksu dün.\n@Mert Aksu bugün.\n"
        #expect(await !model.save())
        #expect(model.composer.pendingAmbiguity?.isExplicit == true)
        #expect(model.composer.pendingAmbiguity?.spelling == "Mert Aksu")
        model.composer.skip(try #require(model.composer.pendingAmbiguity))
        #expect(await model.save())
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        #expect(body.contains("Mert Aksu bugün."))
        #expect(!body.contains("@"))
    }

    @Test func unchangedExplicitLineKeepsAtSignWhenAnotherLineIsAdded() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        var file = try String(contentsOf: context.file, encoding: .utf8)
        file = file.replacingOccurrences(
            of: "Deniz eski satır.", with: "@Deniz Arıkan eski satır.")
        try file.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let loaded = model.text
        #expect(loaded.contains("@Deniz Arıkan eski satır."))
        let edited = loaded.replacingOccurrences(of: "### Notlar", with: "Yeni satır.\n### Notlar")
        model.text = edited
        #expect(await model.save())
        #expect(model.composer.pendingAmbiguity == nil && model.composer.pendingUnknown == nil)
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        // Every untouched line is byte-identical; only the new line was appended.
        #expect(body.utf8.elementsEqual(edited.utf8))
        #expect(body.contains("Yeni satır.\n### Notlar"))
    }

    @Test func unchangedExplicitUnknownDoesNotBlockUnrelatedEdit() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        var file = try String(contentsOf: context.file, encoding: .utf8)
        file = file.replacingOccurrences(
            of: "Deniz eski satır.", with: "@Zeynep Yeni eski satır.")
        try file.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let loaded = model.text
        #expect(loaded.contains("@Zeynep Yeni eski satır."))
        let edited = loaded.replacingOccurrences(of: "### Notlar", with: "Yeni satır.\n### Notlar")
        model.text = edited
        #expect(await model.save())
        #expect(model.composer.pendingAmbiguity == nil && model.composer.pendingUnknown == nil)
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        // Every untouched line is byte-identical; only the new line was appended.
        #expect(body.utf8.elementsEqual(edited.utf8))
        #expect(body.contains("Yeni satır.\n### Notlar"))
    }

    @Test func unchangedExplicitAmbiguityDoesNotBlockUnrelatedEdit() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        var file = try String(contentsOf: context.file, encoding: .utf8)
        file = file.replacingOccurrences(
            of: "Deniz eski satır.", with: "@Mert Aksu eski satır.")
        try file.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let loaded = model.text
        #expect(loaded.contains("@Mert Aksu eski satır."))
        let edited = loaded.replacingOccurrences(of: "### Notlar", with: "Yeni satır.\n### Notlar")
        model.text = edited
        #expect(await model.save())
        #expect(model.composer.pendingAmbiguity == nil && model.composer.pendingUnknown == nil)
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        // Every untouched line is byte-identical; only the new line was appended.
        #expect(body.utf8.elementsEqual(edited.utf8))
        #expect(body.contains("Yeni satır.\n### Notlar"))
    }

    @Test func journalUnknownCreateAndDismissFlow() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "@Ad ile.\n"
        #expect(await !model.save())
        #expect(model.composer.pendingUnknown?.spelling == "Ad")
        await model.composer.create(.person)
        #expect(await model.save())
        var body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        #expect(body.contains("[[Ad]] ile."))

        let day = try #require(CalendarDate("2026-09-11"))
        let fresh = JournalEditorModel(store: context.store, day: day)
        await fresh.load()
        // Distinct spelling so the newly created "Ad" is not auto-linked after dismiss.
        fresh.text = "@Cansu Demir ile.\n"
        #expect(await !fresh.save())
        fresh.composer.dismissUnknown(try #require(fresh.composer.pendingUnknown))
        #expect(await fresh.save())
        body = try JournalRecognition.body(
            of: RawDocument(
                bytes: try Data(contentsOf: context.root.appendingPathComponent("journal/\(day).md"))))
        #expect(body.contains("Cansu Demir ile."))
        #expect(!body.contains("@"))
        #expect(!body.contains("[[Cansu"))
    }

    @Test func caretOffsetAfterSuggestionIsEndOfInsertedName() throws {
        let range = 0..<5  // "@Mert"
        let name = "Mert Aksu"
        #expect(MentionComposer.caretOffset(afterReplacing: range, with: name) == name.utf8.count)
        let text = name + " ile"
        let caret = name.utf8.count
        let selection = try #require(MentionComposer.textSelection(atByteOffset: caret, in: text))
        guard case .selection(let indices) = selection.indices else {
            Issue.record("expected selection indices")
            return
        }
        #expect(indices.lowerBound == indices.upperBound)
        #expect(String(text[indices.lowerBound...]) == " ile")
    }

    @Test func resolutionClearsWhenTextChangesAndHidesSuggestionsWhileAwaiting() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "@Mert Aksu"
        #expect(!model.composer.suggestions().isEmpty)
        #expect(await !model.save())
        #expect(model.composer.awaitingResolution)
        #expect(model.composer.pendingAmbiguity != nil)
        #expect(model.composer.suggestions().isEmpty)
        model.text = "@Mert Aks"
        #expect(!model.composer.awaitingResolution)
        #expect(model.composer.pendingAmbiguity == nil)
        #expect(!model.composer.suggestions().isEmpty)
    }
}

#if os(iOS)
    @MainActor
    struct MentionAssistStripLayoutTests {
        @Test func emptyStripOccupiesNoLayoutSpaceInSpacedStack() async throws {
            let context = try DayEditingTestContext()
            defer { context.clean() }
            await context.start()
            let composer = MentionComposer(store: context.store)
            let strip = MentionAssistStrip(composer: composer, store: context.store)
            #expect(!strip.hasContent)

            let stacked = VStack(spacing: 8) {
                Color.red.frame(width: 40, height: 10)
                strip
                Color.blue.frame(width: 40, height: 10)
            }
            .frame(width: 200)

            let host = UIHostingController(rootView: stacked)
            host.view.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // Two 10 pt rows + one 8 pt gap; an empty VStack child would add a second gap (36).
            #expect(host.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height == 28)
        }
    }
#endif
