import Foundation
import Testing
import VaultFormat
import VaultStore

struct TaskFieldStoreTests {
    @Test func typedCreationHasCanonicalBytesAndIndexFields() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let document = try await vault.store.addingTask(
            on: storeDate, text: "[[Deniz]] ile görüş",
            due: CalendarDate("2026-10-05"), start: CalendarDate("2026-10-01"), priority: .medium, project: "iş")
        #expect(
            String(decoding: document.serialized(), as: UTF8.self)
                == "---\ntype: journal\ndate: 2026-09-27\n---\n\n## Tasks\n- [ ] [[Deniz]] ile görüş 🛫 2026-10-01 📅 2026-10-05 🔼 #project/iş ^aaaaaa\n"
        )
        let task = document.bodyLines.tasks[0]
        #expect(task.text == "[[Deniz]] ile görüş")
        #expect(task.dueDate == CalendarDate("2026-10-05"))
        #expect(try vault.index.blocks(on: storeDate).first?.project == "iş")
        try vault.check()
    }

    @Test func completionReopeningAndCancellationPreserveOtherBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let original =
            "\u{FEFF}## Tasks\r\n*  [ ] x 📅 2026-10-05 #project/iş ^task\r\n  continuation\r\n\r\n## Journal\r\nkeep"
        try vault.write(storePath, original)
        let before = try await vault.store.document(at: storePath)
        let completed = try await vault.store.changingStatus(
            of: before.bodyLines.tasks[0], at: storePath,
            to: .done, completionDate: CalendarDate("2026-10-03"))
        #expect(
            try vault.bytes()
                == Data(
                    original.replacingOccurrences(of: "[ ] x", with: "[x] x")
                        .replacingOccurrences(of: " ^task", with: " ✅ 2026-10-03 ^task").utf8))
        try vault.check()
        let cancelled = try await vault.store.changingStatus(
            of: completed.bodyLines.tasks[0], at: storePath, to: .cancelled)
        #expect(cancelled.bodyLines.tasks[0].doneDate == CalendarDate("2026-10-03"))
        let reopened = try await vault.store.changingStatus(
            of: cancelled.bodyLines.tasks[0], at: storePath, to: .inProgress)
        #expect(reopened.bodyLines.tasks[0].doneDate == nil)
        #expect(try vault.bytes() == Data(original.replacingOccurrences(of: "[ ]", with: "[/]").utf8))
        try vault.check()
    }

    @Test func settersAssignRemoveAndPreserveUntouchedBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let original = "## Tasks\n- [ ] x 📅 2026-10-05 y ^task\n  keep\n"
        try vault.write(storePath, original)
        var document = try await vault.store.document(at: storePath)
        document = try await vault.store.settingTaskDueDate(
            of: document.bodyLines.tasks[0], at: storePath, to: CalendarDate("2026-10-07"))
        #expect(try vault.bytes() == Data(original.replacingOccurrences(of: "2026-10-05", with: "2026-10-07").utf8))
        document = try await vault.store.settingTaskStartDate(
            of: document.bodyLines.tasks[0], at: storePath, to: CalendarDate("2026-10-01"))
        document = try await vault.store.settingTaskPriority(of: document.bodyLines.tasks[0], at: storePath, to: .high)
        document = try await vault.store.settingTaskProject(of: document.bodyLines.tasks[0], at: storePath, to: "iş")
        try vault.check()
        document = try await vault.store.settingTaskDueDate(of: document.bodyLines.tasks[0], at: storePath, to: nil)
        document = try await vault.store.settingTaskStartDate(of: document.bodyLines.tasks[0], at: storePath, to: nil)
        document = try await vault.store.settingTaskPriority(of: document.bodyLines.tasks[0], at: storePath, to: nil)
        _ = try await vault.store.settingTaskProject(of: document.bodyLines.tasks[0], at: storePath, to: nil)
        #expect(try vault.bytes() == Data(original.replacingOccurrences(of: " 📅 2026-10-05", with: "").utf8))
        try vault.check()
    }

    @Test func staleFieldTargetCannotOverwriteNewDiskContent() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "- [ ] x 📅 2026-10-05 ^task")
        let target = try await vault.store.document(at: storePath).bodyLines.tasks[0]
        let external = "- [ ] x 📅 2026-10-07 ^task"
        try vault.write(storePath, external)
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.settingTaskDueDate(of: target, at: storePath, to: nil)
        }
        #expect(try vault.bytes() == Data(external.utf8))
    }
}
