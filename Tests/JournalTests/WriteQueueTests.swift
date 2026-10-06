import Foundation
import Testing
import VaultFormat
import VaultIndex
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

    @Test func handoffThenCancelDoesNotLeakWriteSlot() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()

        context.store.testingOccupyWriteSlot()
        let cancelled = Task { await context.store.addEvent(on: day, text: "Cancelled after handoff", time: nil) }
        try await Task.sleep(for: .milliseconds(30))
        // Same turn: hand the slot to the waiter, then cancel before its body runs.
        context.store.testingReleaseWriteSlot()
        cancelled.cancel()
        #expect(await cancelled.value == false)

        #expect(await context.store.addEvent(on: day, text: "After handoff cancel", time: nil))
        let texts = context.store.content.day(on: day).events.map(\.text.plainText)
        #expect(texts == ["After handoff cancel"])
        #expect(!texts.contains("Cancelled after handoff"))
    }

    @Test func quickEntryKeepsFailedDraftWhenUserTypedOverClear() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()

        context.store.testingOccupyWriteSlot()
        let model = QuickEntryModel(store: context.store, day: day)
        model.includesTime = false
        model.text = "Failed first"
        let firstSubmit = Task { await model.submit(time: nil) }
        for _ in 0..<40 {
            if model.text.isEmpty && !model.isSubmitting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.text.isEmpty)

        model.text = "Typed second"
        context.store.testingReleaseWriteSlot()
        firstSubmit.cancel()
        #expect(await firstSubmit.value == false)
        #expect(model.text.contains("Failed first"))
        #expect(model.text.contains("Typed second"))
        #expect(model.text.hasPrefix("Failed first"))
        #expect(model.errorText != nil || context.store.entryErrorText != nil)
    }

    @Test func quickEntryKeepsDraftAndShowsErrorWhenVaultChangesWhileQueued() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()
        let otherRoot = context.directory.appendingPathComponent("OtherVault")
        try FileManager.default.createDirectory(
            at: otherRoot.appendingPathComponent(".app"), withIntermediateDirectories: true)
        try Data("{ \"formatVersion\": 1 }\n".utf8).write(
            to: otherRoot.appendingPathComponent(".app/vault.json"))
        for name in ["journal", "people", "places", "goals", "notes", "templates"] {
            try FileManager.default.createDirectory(
                at: otherRoot.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        context.store.testingOccupyWriteSlot()
        let model = QuickEntryModel(store: context.store, day: day)
        model.includesTime = false
        model.text = "Queued before switch"
        let firstSubmit = Task { await model.submit(time: nil) }
        for _ in 0..<40 {
            if model.text.isEmpty && !model.isSubmitting { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.text.isEmpty)

        await context.store.select(otherRoot)
        #expect(await firstSubmit.value == false)
        #expect(model.text.contains("Queued before switch"))
        #expect(model.errorText != nil || context.store.entryErrorText != nil)
        context.store.testingReleaseWriteSlot()
    }

    @Test func writeHandedSlotAcrossVaultSwitchDoesNotWriteIntoNewVault() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()
        let otherRoot = context.directory.appendingPathComponent("OtherVault")
        try FileManager.default.createDirectory(
            at: otherRoot.appendingPathComponent(".app"), withIntermediateDirectories: true)
        try Data("{ \"formatVersion\": 1 }\n".utf8).write(
            to: otherRoot.appendingPathComponent(".app/vault.json"))
        for name in ["journal", "people", "places", "goals", "notes", "templates"] {
            try FileManager.default.createDirectory(
                at: otherRoot.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        context.store.testingOccupyWriteSlot()
        let queued = Task { await context.store.addEvent(on: day, text: "Old vault text", time: nil) }
        try await Task.sleep(for: .milliseconds(20))
        // Hand the slot over, then switch vault before the waiter's body runs.
        context.store.testingReleaseWriteSlot()
        await context.store.select(otherRoot)
        #expect(await queued.value == false)
        let newDay = otherRoot.appendingPathComponent("journal/\(day).md")
        #expect(!FileManager.default.fileExists(atPath: newDay.path))
        _ = await context.store.addEvent(on: day, text: "New vault text", time: nil)
        #expect(FileManager.default.fileExists(atPath: newDay.path))
    }

    @Test func completeTaskAfterQueuedEventInsertApplies() async throws {
        let context = try WriteQueueContext()
        defer { context.clean() }
        await context.store.start()
        let day = LocalDay.today()
        let root = try #require(context.store.vaultURL)
        // Events above Tasks so inserted events shift task line numbers.
        let seed = """
            ---
            type: journal
            date: \(day)
            ---

            ## Events
            - Seed event ^seed01

            ## Tasks
            - [ ] Mark me done ^task01

            """
        let file = root.appendingPathComponent("journal/\(day).md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(seed.utf8).write(to: file)
        await context.store.refresh()
        let row = try #require(context.store.content.tasks.first { $0.sourceText == "Mark me done" })
        let beforeLine = row.sourceLine

        let hold = Task {
            try await context.store.performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingEvent(on: day, text: "Inserted event line", time: nil)
                try await writer.addingEvent(on: day, text: "Second insert shifts further", time: nil)
                try await Task.sleep(for: .milliseconds(120))
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(context.store.isWriting || context.store.isProcessing)

        try await context.store.completeTask(row, on: day)
        try await hold.value

        let task = try #require(context.store.content.tasks.first { $0.sourceText == "Mark me done" })
        #expect(task.isClosed)
        #expect(task.sourceLine > beforeLine)
        let disk = RawDocument(bytes: try Data(contentsOf: file))
        #expect(disk.bodyLines.tasks.contains { $0.text == "Mark me done" && $0.status == .done })
        #expect(disk.bodyLines.events.map(\.block.text).contains("Inserted event line"))
    }

    @Test func writeDuringOpenWaitsForInitialRefresh() async throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let gate = UpdateGate()
        let store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory),
            supportURL: directory.appendingPathComponent("indexes"),
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                let result = try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
                await gate.hold()
                return result
            })
        await gate.arm()
        let opening = Task { await store.start() }
        for _ in 0..<100 {
            if store.canAddEvent { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.canAddEvent)
        #expect(store.lastUpdated == nil)

        let write = Task { await store.addEvent(on: LocalDay.today(), text: "During open", time: nil) }
        try await Task.sleep(for: .milliseconds(40))
        #expect(!store.isWriting)
        #expect(store.lastUpdated == nil)

        await gate.release()
        await opening.value
        #expect(await write.value)
        #expect(store.lastUpdated != nil)
        #expect(
            store.content.days.contains { day in
                day.events.contains { $0.text.plainText == "During open" }
            })
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
            location: VaultLocation(
                defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}
