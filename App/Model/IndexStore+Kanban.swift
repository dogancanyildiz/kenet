import VaultFormat

extension IndexStore {
    /// Resolve against the dragged snapshot; never apply a stale card to a newer row.
    func moveTask(_ row: TaskRow, to status: TaskStatus, on day: CalendarDate) async throws {
        let target = try await taskTarget(row)
        try await performEdit(path: row.file) { writer in
            try await writer.changingStatus(
                of: target, at: row.file, to: status, completionDate: status == .done ? day : nil)
        }
    }

    func moveTask(_ row: TaskRow, toProject project: String?) async throws {
        let target = try await taskTarget(row)
        try await performEdit(path: row.file) { writer in
            try await writer.settingTaskProject(of: target, at: row.file, to: project)
        }
    }
}
