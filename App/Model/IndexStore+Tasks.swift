import VaultFormat
import VaultStore

extension IndexStore {
    @discardableResult
    func addTask(
        on day: CalendarDate, text: String, due: CalendarDate?, priority: TaskPriority? = nil,
        recurrence: TaskRecurrence? = nil
    ) async -> Bool {
        guard !text.allSatisfy(\.isWhitespace) else { return false }
        // performEdit waits for the write queue and any in-flight refresh.
        guard canAddEvent else { return false }
        reportTaskEntryError(nil)
        do {
            try await performEdit(path: "journal/\(day).md") { writer in
                try await writer.addingTask(on: day, text: text, due: due, priority: priority, recurrence: recurrence)
            }
            return true
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
        if let task = resolvedTask(row, in: document) { return task }
        await refresh()
        throw VaultStoreError.staleTarget
    }

    /// Resolve after the write slot is held so queued inserts that shift lines are already applied.
    func resolvedTask(_ row: TaskRow, in document: RawDocument) -> TaskLine? {
        let tasks = document.bodyLines.tasks
        if let task = tasks.first(where: { $0.block.line == row.sourceLine }),
            taskMatchesExact(task, row: row)
        {
            return task
        }
        if let id = row.sourceIdentifier {
            let matches = tasks.filter { $0.block.id == id && taskMatchesIdentity($0, row: row) }
            return matches.count == 1 ? matches[0] : nil
        }
        let byContent = tasks.filter { taskMatchesIdentity($0, row: row) }
        return byContent.count == 1 ? byContent[0] : nil
    }

    private func taskMatchesExact(_ task: TaskLine, row: TaskRow) -> Bool {
        task.block.lineRange.upperBound == row.sourceEnd && taskMatchesIdentity(task, row: row)
    }

    private func taskMatchesIdentity(_ task: TaskLine, row: TaskRow) -> Bool {
        task.text.utf8.elementsEqual(row.sourceText.utf8) && task.block.id == row.sourceIdentifier
            && task.rawStatus == row.rawStatus && task.dueDate == row.due && task.startDate == row.start
            && task.doneDate == row.done && task.priority == row.priority && task.project == row.project
            && task.recurrenceSource == row.recurrenceSource
    }

    func completeTask(_ row: TaskRow, on today: CalendarDate) async throws {
        try await performEdit(path: row.file) { writer in
            try await self.applyStatusChange(of: row, writer: writer, to: .done, completionDate: today)
        }
    }

    func reopenTask(_ row: TaskRow) async throws {
        try await performEdit(path: row.file) { writer in
            try await self.applyStatusChange(of: row, writer: writer, to: .todo, completionDate: nil)
        }
    }

    func applyStatusChange(
        of row: TaskRow, writer: VaultStore, to status: TaskStatus, completionDate: CalendarDate?
    ) async throws {
        var target = try await taskTarget(row)
        do {
            try await writer.changingStatus(
                of: target, at: row.file, to: status, completionDate: completionDate)
        } catch VaultStoreError.staleTarget {
            // One retry by current document identity after a line-shifting write.
            target = try await taskTarget(row)
            try await writer.changingStatus(
                of: target, at: row.file, to: status, completionDate: completionDate)
        }
    }

}
