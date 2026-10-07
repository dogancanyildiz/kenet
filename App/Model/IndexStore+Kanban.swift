import VaultFormat
import VaultStore

extension IndexStore {
    /// Resolve against the dragged snapshot; never apply a stale card to a newer row.
    func moveTask(_ row: TaskRow, to status: TaskStatus, on day: CalendarDate) async throws {
        try await performEdit(path: row.file) { writer in
            try await self.applyStatusChange(
                of: row, writer: writer, to: status, completionDate: status == .done ? day : nil)
        }
    }

    func moveTask(_ row: TaskRow, toProject project: String?) async throws {
        try await performEdit(path: row.file) { writer in
            var target = try await self.taskTarget(row)
            do {
                try await writer.settingTaskProject(of: target, at: row.file, to: project)
            } catch VaultStoreError.staleTarget {
                target = try await self.taskTarget(row)
                try await writer.settingTaskProject(of: target, at: row.file, to: project)
            }
        }
    }
}
