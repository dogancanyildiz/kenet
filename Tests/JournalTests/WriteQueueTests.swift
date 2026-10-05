import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

@MainActor
struct WriteQueueTests {
    @Test func concurrentAddEventsBothPersistInOrder() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()

        let first = Task {
            try await context.store.performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingEvent(on: day, text: "First queued", time: nil)
                try await Task.sleep(for: .milliseconds(120))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(context.store.isWriting || context.store.isProcessing)

        let second = Task { await context.store.addEvent(on: day, text: "Second queued", time: nil) }
        try await first.value
        #expect(await second.value)

        let texts = context.store.content.day(on: day).events.map(\.text.plainText)
        #expect(texts == ["First queued", "Second queued"])
        let root = try #require(context.store.vaultURL)
        let disk = RawDocument(bytes: try Data(contentsOf: root.appendingPathComponent("journal/\(day).md")))
        #expect(disk.bodyLines.events.map(\.block.text) == ["First queued", "Second queued"])
        #expect(context.store.entryErrorText == nil)
    }

    @Test func editWhileAnotherWriteRunsDoesNotReportExternalChange() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()
        #expect(await context.store.addEvent(on: day, text: "Seed one", time: nil))
        #expect(await context.store.addEvent(on: day, text: "Seed two", time: nil))
        let rows = context.store.content.day(on: day).events
        let firstRow = try #require(rows.first)
        let secondRow = try #require(rows.last)
        let firstTarget = try await context.store.eventTarget(on: day, row: firstRow)
        let secondTarget = try await context.store.eventTarget(on: day, row: secondRow)

        let hold = Task {
            try await context.store.performEdit(path: "journal/\(day).md") { writer in
                try await writer.changingText(of: firstTarget, at: "journal/\(day).md", to: "Edited one")
                try await Task.sleep(for: .milliseconds(120))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(context.store.isWriting || context.store.isProcessing)

        var secondError: (any Error)?
        do {
            try await context.store.changeEvent(on: day, target: secondTarget, to: "Edited two")
        } catch {
            secondError = error
        }
        try await hold.value

        #expect(secondError == nil)
        let texts = context.store.content.day(on: day).events.map(\.text.plainText)
        #expect(texts == ["Edited one", "Edited two"])
        #expect(context.store.entryErrorText == nil)
    }

    @Test func externalFileChangeStillReportsStaleTarget() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()
        #expect(await context.store.addEvent(on: day, text: "Original", time: nil))
        let row = try #require(context.store.content.day(on: day).events.first)
        let target = try await context.store.eventTarget(on: day, row: row)
        let root = try #require(context.store.vaultURL)
        let file = root.appendingPathComponent("journal/\(day).md")
        let external = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(
            of: "Original", with: "Changed outside")
        try Data(external.utf8).write(to: file)

        await #expect(throws: VaultStoreError.staleTarget) {
            try await context.store.changeEvent(on: day, target: target, to: "My edit")
        }
        #expect(try String(contentsOf: file, encoding: .utf8) == external)
    }

    @Test func cancelledWaiterDoesNotBlockFollowingWrite() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()

        let hold = Task {
            try await context.store.performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingEvent(on: day, text: "Holder", time: nil)
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(context.store.isWriting || context.store.isProcessing)

        let cancelled = Task { await context.store.addEvent(on: day, text: "Cancelled", time: nil) }
        try await Task.sleep(for: .milliseconds(20))
        cancelled.cancel()
        #expect(await cancelled.value == false)

        #expect(await context.store.addEvent(on: day, text: "After cancel", time: nil))
        try await hold.value
        let texts = context.store.content.day(on: day).events.map(\.text.plainText)
        #expect(texts == ["Holder", "After cancel"])
    }

    @Test func quickEntryClearsDraftAndAcceptsSecondSubmitWhileWriteRuns() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()

        let hold = Task {
            try await context.store.performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingEvent(on: day, text: "Blocking write", time: nil)
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(context.store.isWriting || context.store.isProcessing)
        #expect(context.store.canAddEvent)

        let model = QuickEntryModel(store: context.store, day: day)
        model.includesTime = false
        model.text = "First enter"
        let firstSubmit = Task { await model.submit(time: nil) }
        for _ in 0..<40 {
            if model.text.isEmpty && !model.isSubmitting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.text.isEmpty)
        #expect(!model.isSubmitting)

        model.text = "Second enter"
        #expect(model.canSubmit)
        #expect(await model.submit(time: nil))
        #expect(await firstSubmit.value)
        try await hold.value

        let texts = context.store.content.day(on: day).events.map(\.text.plainText)
        #expect(texts.contains("First enter"))
        #expect(texts.contains("Second enter"))
        #expect(texts.contains("Blocking write"))
    }
}

@MainActor
private struct WriteQueueContext {
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

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
