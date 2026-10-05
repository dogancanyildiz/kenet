import VaultFormat
import VaultStore

extension IndexStore {
    @discardableResult
    func addTask(
        on day: CalendarDate, text: String, due: CalendarDate?, priority: TaskPriority? = nil,
        recurrence: TaskRecurrence? = nil
    ) async -> Bool {
        guard !text.allSatisfy(\.isWhitespace) else { return false }
        // performEdit waits for an in-flight refresh; avoid rejecting before that wait.
        reportTaskEntryError(nil)
        do {
            try await performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingTask(on: day, text: text, due: due, priority: priority, recurrence: recurrence)
            }
            return true
        } catch VaultStoreError.staleTarget {
            return false
        } catch VaultStoreError.indexUpdateFailed {
            reportTaskEntryError(EntryWriteError.savedWithoutIndex)
            return true
        } catch {
            reportTaskEntryError(EntryWriteError.message(for: error))
            return false
        }
    }

    func taskTarget(_ row: TaskRow) async throws -> TaskLine {
        let document = try await document(at: row.file)
        guard let task = document.bodyLines.tasks.first(where: { $0.block.line == row.sourceLine }),
            task.block.lineRange.upperBound == row.sourceEnd,
            task.text.utf8.elementsEqual(row.sourceText.utf8), task.block.id == row.sourceIdentifier,
            task.rawStatus == row.rawStatus, task.dueDate == row.due, task.startDate == row.start,
            task.doneDate == row.done, task.priority == row.priority, task.project == row.project,
            task.recurrenceSource == row.recurrenceSource
        else {
            await refresh()
            throw VaultStoreError.staleTarget
        }
        return task
    }

    func completeTask(_ row: TaskRow, on today: CalendarDate) async throws {
        let target = try await taskTarget(row)
        try await performEdit(path: row.file) { writer in
            try await writer.changingStatus(of: target, at: row.file, to: .done, completionDate: today)
        }
    }
    func reopenTask(_ row: TaskRow) async throws {
        let target = try await taskTarget(row)
        try await performEdit(path: row.file) { writer in
            try await writer.changingStatus(of: target, at: row.file, to: .todo)
        }
    }

}
