import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class TaskEditorModel: Identifiable {
    let id = UUID()
    let store: IndexStore
    let row: TaskRow
    var text = ""
    private(set) var target: TaskLine?
    private(set) var errorText: String?
    private(set) var isSaving = false
    private(set) var isSaved = false
    private var root: URL?

    init(store: IndexStore, row: TaskRow) {
        self.store = store
        self.row = row
    }

    var canSave: Bool {
        target != nil && !isSaving && !isSaved && store.canAddEvent && root == store.vaultURL
            && !text.allSatisfy(\.isWhitespace) && !text.contains(where: { $0.isNewline })
    }

    func load() async {
        guard target == nil else { return }
        let selected = store.vaultURL
        do {
            let task = try await store.taskTarget(row)
            guard selected == store.vaultURL else { throw VaultStoreError.staleTarget }
            target = task
            text = task.text
            root = selected
        } catch { errorText = DayEditError.message(for: error) }
    }

    func save() async -> Bool {
        guard canSave, let target else { return false }
        let path = row.file
        let text = text
        return await write { writer in
            try await writer.changingText(of: target.block, at: path, to: text)
        }
    }

    func setDue(_ date: CalendarDate?) async -> Bool {
        guard let target else { return false }
        return await write { try await $0.settingTaskDueDate(of: target, at: self.row.file, to: date) }
    }

    func setPriority(_ priority: TaskPriority?) async -> Bool {
        guard let target else { return false }
        return await write { try await $0.settingTaskPriority(of: target, at: self.row.file, to: priority) }
    }

    func setRecurrence(_ recurrence: TaskRecurrence?) async -> Bool {
        guard let target else { return false }
        return await write { try await $0.settingTaskRecurrence(of: target, at: self.row.file, to: recurrence) }
    }

    func delete() async -> Bool {
        guard let target else { return false }
        return await write { try await $0.deletingBlock(target.block, at: self.row.file) }
    }

    private func write(_ operation: @Sendable (VaultStore) async throws -> Void) async -> Bool {
        guard !isSaving, !isSaved, store.canAddEvent, root == store.vaultURL else { return false }
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await store.performEdit(path: row.file, operation: operation)
            isSaved = true
            return true
        } catch VaultStoreError.indexUpdateFailed {
            isSaved = true
            errorText = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
            return true
        } catch {
            target = nil
            errorText = DayEditError.message(for: error)
            return false
        }
    }
}
