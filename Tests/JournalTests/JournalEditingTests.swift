import Foundation
import SQLite3
import Testing
import VaultFormat
import VaultStore

@testable import Journal

@MainActor
struct JournalEditingTests {
    @Test func readsRawBodyAndWritesOnlyJournalWithChangedLineRecognition() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        #expect(model.isLoaded)
        #expect(model.text == "Deniz eski satır.\n[[Liman Ofis]] burada.\n### Notlar\n```swift\nDeniz\n```\n\n")
        model.text = model.text.replacingOccurrences(of: "### Notlar", with: "Deniz yeni satır.\n### Notlar")
        #expect(await model.save())
        #expect(try Data(contentsOf: context.file) == Data(contentsOf: context.fixture("expected.md")))
        #expect(!model.isDirty)
        #expect(
            context.store.content.day(on: context.day).journal.contains {
                $0.text.plainText.contains("Deniz yeni satır.")
            })
    }

    @Test func unchangedTextDoesNotWriteOrReindex() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try Data(contentsOf: context.file)
        let modified = try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let updated = context.store.lastUpdated
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        #expect(await model.save())
        #expect(try Data(contentsOf: context.file) == before)
        #expect(
            try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(context.store.lastUpdated == updated)
    }

    @Test(arguments: ["## New section\nDeniz", "```swift\nDeniz"])
    func invalidStructureKeepsDraftAndOriginalBytes(_ draft: String) async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try Data(contentsOf: context.file)
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = draft
        #expect(await !model.save())
        #expect(model.text == draft)
        #expect(model.isDirty)
        #expect(model.errorText == DayEditError.message(for: EditError.sectionNotWritable))
        #expect(try Data(contentsOf: context.file) == before)
    }

    @Test func changedLinesRespectFencesCaseAmbiguityAndExistingLinks() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let entities = context.store.knownEntities
        let text = "---\nDeniz\n```\nDeniz\n```\n[[Deniz Arıkan|Deniz]]\ndeniz\nMert Aksu\n"
        let linked = try JournalRecognition.linkingChanges(in: text, from: "", entities: entities)
        #expect(linked == "---\n[[Deniz Arıkan|Deniz]]\n```\nDeniz\n```\n[[Deniz Arıkan|Deniz]]\ndeniz\nMert Aksu\n")
        let original = "```\nDeniz\n```\nUnchanged\n"
        let changed = "```\nDeniz Arıkan\n```\nUnchanged\nDeniz\n"
        #expect(
            try JournalRecognition.linkingChanges(in: changed, from: original, entities: entities)
                == "```\nDeniz Arıkan\n```\nUnchanged\n[[Deniz Arıkan|Deniz]]\n")
    }

    @Test func shiftedUnchangedLinesRemainPlain() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let original = "Deniz\nOther\n"
        let draft = "Added\nDeniz\nOther\n"
        #expect(
            try JournalRecognition.linkingChanges(in: draft, from: original, entities: context.store.knownEntities)
                == draft)
    }

    @Test func emptyMissingJournalDoesNotCreateDayAndNewJournalDoes() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let day = try #require(CalendarDate("2026-09-11"))
        let file = context.root.appendingPathComponent("journal/\(day).md")
        let model = JournalEditorModel(store: context.store, day: day)
        await model.load()
        #expect(model.text.isEmpty)
        #expect(await model.save())
        #expect(!FileManager.default.fileExists(atPath: file.path))
        model.text = "Deniz ile gün."
        #expect(await model.save())
        #expect(
            try String(contentsOf: file, encoding: .utf8)
                == "---\ntype: journal\ndate: \(day)\n---\n\n## Journal\n[[Deniz Arıkan|Deniz]] ile gün.\n")
        #expect(context.store.content.day(on: day).preview == "Deniz ile gün.")
    }

    @Test func savedButUnindexedJournalIsNotWrittenAgain() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let database = try #require(
            FileManager.default.contentsOfDirectory(
                at: context.directory.appendingPathComponent("indexes"), includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "sqlite" })
        var connection: OpaquePointer?
        #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        let sql =
            "CREATE TRIGGER reject_journal BEFORE INSERT ON blocks BEGIN SELECT RAISE(ABORT, 'test failure'); END;"
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        model.text = "Deniz yeni günlük."
        #expect(await model.save())
        #expect(!model.isDirty)
        #expect(model.errorText != nil)
        #expect(model.text.contains("[[Deniz Arıkan|Deniz]]"))
        let saved = try Data(contentsOf: context.file)
        let modified = try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(await model.save())
        #expect(try Data(contentsOf: context.file) == saved)
        #expect(
            try context.file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
        #expect(sqlite3_exec(handle, "DROP TRIGGER reject_journal", nil, nil, nil) == SQLITE_OK)
        await context.store.refresh(rebuild: true)
        #expect(context.store.content.day(on: context.day).preview == "Deniz yeni günlük.")
    }

    @Test func externalJournalChangesAreNotOverwritten() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let changed = try String(contentsOf: context.file, encoding: .utf8).replacingOccurrences(
            of: "Deniz eski satır.", with: "External edit.")
        try Data(changed.utf8).write(to: context.file)
        model.text = "My draft"
        #expect(await !model.save())
        #expect(model.text == "My draft")
        #expect(model.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == Data(changed.utf8))
    }
}
