import Foundation
import Testing
import VaultFormat
import VaultStore

struct RecurrenceStoreTests {
    @Test func appWrittenRecurrenceCanBeChangedAndRemoved() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let added = try await vault.store.addingTask(
            on: storeDate, text: "Water plants", recurrence: TaskRecurrence("every week"))
        let task = try #require(added.bodyLines.tasks.first)
        let changed = try await vault.store.settingTaskRecurrence(
            of: task, at: storePath, to: TaskRecurrence("every day"))
        let expected = String(decoding: added.serialized(), as: UTF8.self)
            .replacingOccurrences(of: "🔁 every week", with: "🔁 every day")
        #expect(changed.serialized() == Array(expected.utf8))
        #expect(Array(try vault.bytes()) == changed.serialized())
        try vault.check()
        let removed = try await vault.store.settingTaskRecurrence(
            of: try #require(changed.bodyLines.tasks.first), at: storePath, to: nil)
        #expect(removed.serialized() == Array(expected.replacingOccurrences(of: " 🔁 every day", with: "").utf8))
        #expect(Array(try vault.bytes()) == removed.serialized())
        try vault.check()
    }

    @Test(arguments: ["old", "my-long-block-id"])
    func duplicateIdentityRepairWithRecurrenceEdit(id: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let row = "- [ ] Water 🔁 every week ^" + id + "\n"
        try vault.write(storePath, row + row)
        try vault.index.rebuild(vaultRoot: vault.root)
        let document = RawDocument(bytes: (row + row).utf8)
        let task = try #require(document.bodyLines.tasks.last)
        let edited = try await vault.store.settingTaskRecurrence(
            of: task, at: storePath, to: TaskRecurrence("every day"))
        let repaired = try #require(edited.bodyLines.tasks.last?.block.id)
        #expect(repaired != id && repaired.count == 6)
        #expect(edited.serialized() == Array((row + "- [ ] Water 🔁 every day ^" + repaired + "\n").utf8))
        #expect(Array(try vault.bytes()) == edited.serialized())
        try vault.check()
    }

    @Test func unknownRecurrenceEditLeavesDiskAndIndexUntouched() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let source = "- [ ] Su ver 🔁 every week bahçedeki çiçeklere 📅 2026-10-10\n"
        try vault.write(storePath, source)
        try vault.index.rebuild(vaultRoot: vault.root)
        let task = try #require(RawDocument(bytes: source.utf8).bodyLines.tasks.first)
        await #expect(throws: EditError.contentNotRepresentable) {
            try await vault.store.settingTaskRecurrence(of: task, at: storePath, to: TaskRecurrence("every week"))
        }
        #expect(Array(try vault.bytes()) == Array(source.utf8))
        try vault.check()
    }

    @Test func completionPersistsBothRowsAndRebuildMatchesIndex() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let source = "- [ ] Task 🔁 every week 📅 2026-10-04 #project/demo ^old\n"
        try vault.write(storePath, source)
        try vault.index.rebuild(vaultRoot: vault.root)
        let task = try #require(RawDocument(bytes: source.utf8).bodyLines.tasks.first)
        let result = try await vault.store.changingStatus(
            of: task, at: storePath, to: .done, completionDate: CalendarDate("2026-10-04"))
        let tasks = result.bodyLines.tasks
        #expect(tasks.count == 2)
        #expect(tasks[0].status == .todo && tasks[1].status == .done)
        #expect(tasks[0].block.id != tasks[1].block.id && tasks[0].doneDate == nil)
        #expect(tasks[0].dueDate == CalendarDate("2026-10-11"))
        #expect(
            try vault.index.snapshot().blocks.filter { $0.kind == "task" }.map(\.recurrence) == [
                "every week", "every week",
            ])
        try vault.check()
        _ = try await vault.store.changingStatus(
            of: tasks[1], at: storePath, to: .done, completionDate: CalendarDate("2026-10-05"))
        #expect(RawDocument(bytes: try vault.bytes()).bodyLines.tasks.count == 2)
    }
    @Test func unknownAndCancellationDoNotGenerateRows() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        for (rule, status) in [("every weekday", TaskStatus.done), ("every day", .cancelled)] {
            let source = "- [ ] Task 🔁 " + rule + " 📅 2026-10-04 ^old\n"
            try vault.write(storePath, source)
            try vault.index.rebuild(vaultRoot: vault.root)
            let task = try #require(RawDocument(bytes: source.utf8).bodyLines.tasks.first)
            let result = try await vault.store.changingStatus(
                of: task, at: storePath, to: status, completionDate: CalendarDate("2026-10-04"))
            #expect(result.bodyLines.tasks.count == 1)
            try vault.check()
        }
    }
    @Test func missingOriginalIDAndNextIDAreDifferent() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: random.next)
        defer { vault.remove() }
        let source = "- [?] Task 🔁 every day 📅 2026-10-04\n"
        try vault.write(storePath, source)
        try vault.index.rebuild(vaultRoot: vault.root)
        let task = try #require(RawDocument(bytes: source.utf8).bodyLines.tasks.first)
        let result = try await vault.store.changingStatus(
            of: task, at: storePath, to: .done, completionDate: CalendarDate("2026-10-04"))
        let tasks = result.bodyLines.tasks
        #expect(Set(tasks.compactMap { $0.block.id }).count == 2)
        try vault.check()
    }
}
