import Foundation
import Testing
import VaultFormat
import VaultStore

struct RecurrenceStoreTests {
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
