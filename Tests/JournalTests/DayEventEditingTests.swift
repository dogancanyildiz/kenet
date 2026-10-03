import Foundation
import SQLite3
import Testing
import VaultFormat
import VaultStore

@testable import Journal

@MainActor
struct DayEventEditingTests {
    @Test func historicalQuickEntryDefaultsUntimedAndAcceptsChosenClock() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let day = try #require(CalendarDate("2026-09-11"))
        let model = QuickEntryModel(store: context.store, day: day)
        #expect(model.isHistorical)
        #expect(!model.includesTime)
        #expect(model.entryTime == nil)
        model.text = "Untimed"
        #expect(await model.submit(time: model.entryTime))
        model.includesTime = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        model.selectedTime = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 13, minute: 5)))
        #expect(model.entryTime == (try LineClock(hour: 13, minute: 5)))
        model.text = "Timed"
        #expect(await model.submit(time: model.entryTime))
        let events = context.store.content.day(on: day).events
        #expect(events.map(\.time?.hour) == [nil, 13])
        #expect(events.map(\.text.plainText) == ["Untimed", "Timed"])
        let document = try await context.store.dayDocument(for: day)
        #expect(document.bodyLines.events.last?.time?.minute == 5)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.root.appendingPathComponent("journal/\(LocalDay.today()).md").path))
        let today = QuickEntryModel(store: context.store)
        #expect(today.includesTime)
        #expect(!today.isHistorical)
    }

    @Test func editsEventTextPreservingClockIdentifierContinuationsAndOtherSections() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try String(contentsOf: context.file, encoding: .utf8)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        #expect(model.text == "Existing event")
        model.text = "Edited event"
        #expect(await model.save())
        #expect(
            try Data(contentsOf: context.file)
                == Data(before.replacingOccurrences(of: "Existing event", with: "Edited event").utf8))
        #expect(context.store.content.day(on: context.day).events.first?.text.plainText == "Edited event")
        #expect(context.store.content.day(on: context.day).events.first?.time?.hour == 9)
    }

    @Test func deletesCompleteEventBlockPreservingJournalAndSectionHeading() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let before = try String(contentsOf: context.file, encoding: .utf8)
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        #expect(await model.delete())
        let expected = before.replacingOccurrences(
            of: "- 09:00 Existing event ^evt123\n  Untouched continuation\n", with: "")
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
        #expect(context.store.content.day(on: context.day).events.isEmpty)
    }

    @Test func staleEventTargetRefreshesScreenAndKeepsDraft() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        let external = try String(contentsOf: context.file, encoding: .utf8).replacingOccurrences(
            of: "Existing event", with: "External event")
        try Data(external.utf8).write(to: context.file)
        model.text = "My draft"
        #expect(await !model.save())
        #expect(model.text == "My draft")
        #expect(model.target == nil)
        #expect(model.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == Data(external.utf8))
        #expect(context.store.content.day(on: context.day).events.first?.text.plainText == "External event")
    }

    @Test func staleDisplayedRowCannotLoadOrDeleteDifferentEvent() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let external = try String(contentsOf: context.file, encoding: .utf8).replacingOccurrences(
            of: "Existing event", with: "Replacement event")
        try Data(external.utf8).write(to: context.file)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        #expect(model.target == nil)
        #expect(await !model.delete())
        #expect(model.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == Data(external.utf8))
        #expect(context.store.content.day(on: context.day).events.first?.text.plainText == "Replacement event")
    }

    @Test func savedButUnindexedEventDoesNotRetryStaleTarget() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        let database = try #require(
            FileManager.default.contentsOfDirectory(
                at: context.directory.appendingPathComponent("indexes"), includingPropertiesForKeys: nil
            ).first { $0.pathExtension == "sqlite" })
        var connection: OpaquePointer?
        #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        #expect(
            sqlite3_exec(
                handle,
                "CREATE TRIGGER reject_edit BEFORE INSERT ON blocks BEGIN SELECT RAISE(ABORT, 'test failure'); END;",
                nil, nil, nil) == SQLITE_OK)
        model.text = "Saved edit"
        #expect(await model.save())
        #expect(model.isSaved)
        #expect(model.errorText != nil)
        let saved = try Data(contentsOf: context.file)
        #expect(await model.save())
        #expect(model.errorText == nil)
        #expect(try Data(contentsOf: context.file) == saved)
        #expect(sqlite3_exec(handle, "DROP TRIGGER reject_edit", nil, nil, nil) == SQLITE_OK)
        await context.store.refresh(rebuild: true)
        #expect(context.store.content.day(on: context.day).events.first?.text.plainText == "Saved edit")
    }

    @Test func eventEditorRejectsMultipleLinesBeforeWriting() async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        let before = try Data(contentsOf: context.file)
        model.text = "First\nSecond"
        #expect(!model.canSave)
        #expect(await !model.save())
        #expect(try Data(contentsOf: context.file) == before)
    }
}
