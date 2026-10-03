import Foundation
import SQLite3
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor
struct QuickEntryTests {
    @Test func writesDayBytesAndPublishesEventsInFileOrder() async throws {
        let context = try EntryTestContext()
        defer { context.clean() }
        await context.store.start()
        let root = try #require(context.store.vaultURL)
        let date = LocalDay.today()
        let clock = try LineClock(hour: 14, minute: 30)
        #expect(await context.store.addEvent(text: "First event", time: clock))
        let file = root.appendingPathComponent("journal/\(date).md")
        let document = RawDocument(bytes: try Data(contentsOf: file))
        let id = try #require(document.bodyLines.events.first?.block.id)
        let expected = "---\ntype: journal\ndate: \(date)\n---\n\n## Events\n- 14:30 First event ^\(id)\n"
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
        #expect(id.count == 6)
        #expect(await context.store.addEvent(text: "Earlier event", time: try LineClock(hour: 9, minute: 5)))
        #expect(await context.store.addEvent(text: "Untimed event", time: nil))
        let events = context.store.content.day(on: date).events
        #expect(events.map(\.text.plainText) == ["Earlier event", "First event", "Untimed event"])
        #expect(events.map { $0.time?.hour } == [9, 14, nil])
        let disk = RawDocument(bytes: try Data(contentsOf: file))
        #expect(disk.bodyLines.events.map(\.block.text) == ["Earlier event", "First event", "Untimed event"])
        #expect(context.store.counts.events == 3)
        let database = try context.databaseURL()
        let index = try VaultIndex(databaseURL: database)
        #expect(try index.snapshot().blocks.filter { $0.kind == "event" }.count == 3)
        #expect(context.store.entryErrorText == nil)
    }

    @Test func whitespaceAndClosedVaultDoNotWrite() async throws {
        let context = try EntryTestContext()
        defer { context.clean() }
        #expect(!context.store.canAddEvent)
        #expect(await !context.store.addEvent(text: "Event", time: nil))
        await context.store.start()
        #expect(await !context.store.addEvent(text: " \t\n ", time: nil))
        #expect(context.store.counts.events == 0)
        let root = try #require(context.store.vaultURL)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("journal").path).isEmpty)
    }

    @Test func readOnlyDocumentRetainsDraftAndProducesMessage() async throws {
        let context = try EntryTestContext()
        defer { context.clean() }
        await context.store.start()
        let root = try #require(context.store.vaultURL)
        let file = root.appendingPathComponent("journal/\(LocalDay.today()).md")
        let bytes = Data([0xFF, 0xFE, 0x00])
        try bytes.write(to: file)
        #expect(await !context.store.addEvent(text: "Event", time: nil))
        #expect(context.store.entryErrorText == EntryWriteError.message(for: CocoaError(.fileWriteNoPermission)))
        #expect(try Data(contentsOf: file) == bytes)
        #expect(!context.store.isWriting)
    }

    @Test func failedIndexUpdateReportsSavedAndCanBeRebuilt() async throws {
        let context = try EntryTestContext()
        defer { context.clean() }
        await context.store.start()
        let database = try context.databaseURL()
        var connection: OpaquePointer?
        #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
        let handle = try #require(connection)
        defer { sqlite3_close(handle) }
        // Break indexing only after the writer's identifier query; the Markdown commit still succeeds.
        let sql = "CREATE TRIGGER reject_event BEFORE INSERT ON blocks BEGIN SELECT RAISE(ABORT, 'test failure'); END;"
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
        #expect(await context.store.addEvent(text: "Saved event", time: nil))
        #expect(context.store.entryErrorText == EntryWriteError.savedWithoutIndex)
        let root = try #require(context.store.vaultURL)
        let file = root.appendingPathComponent("journal/\(LocalDay.today()).md")
        #expect(RawDocument(bytes: try Data(contentsOf: file)).bodyLines.events.count == 1)
        #expect(sqlite3_exec(handle, "DROP TRIGGER reject_event", nil, nil, nil) == SQLITE_OK)
        await context.store.refresh(rebuild: true)
        #expect(context.store.content.day(on: LocalDay.today()).events.map(\.text.plainText) == ["Saved event"])
        #expect(context.store.counts.events == 1)
    }

    @Test func staleTargetMessageDiffersFromSavedMessage() {
        #expect(EntryWriteError.message(for: VaultStoreError.staleTarget) != EntryWriteError.savedWithoutIndex)
        #expect(
            EntryWriteError.message(
                for: VaultStoreError.indexUpdateFailed(
                    path: "journal/test.md", underlying: CocoaError(.fileReadUnknown)))
                == EntryWriteError.savedWithoutIndex)
    }

    @Test func localClockAndDayUseTheSameTimeZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-03T22:05:00Z"))
        let zone = try #require(TimeZone(secondsFromGMT: 3 * 3600))
        #expect(LocalDay.today(at: instant, timeZone: zone).description == "2026-10-04")
        #expect(LocalDay.clock(at: instant, timeZone: zone) == (try LineClock(hour: 1, minute: 5)))
    }
}

@MainActor
private struct EntryTestContext {
    let directory: URL
    let defaults: TestDefaults
    let store: IndexStore

    init() throws {
        directory = try testDirectory()
        defaults = try TestDefaults()
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func databaseURL() throws -> URL {
        try #require(
            FileManager.default.contentsOfDirectory(
                at: directory.appendingPathComponent("indexes"), includingPropertiesForKeys: nil
            )
            .first { $0.pathExtension == "sqlite" })
    }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
