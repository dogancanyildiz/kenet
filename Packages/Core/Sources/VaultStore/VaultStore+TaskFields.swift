import VaultFormat

extension VaultStore {
    /// Writes the due date on disk, then refreshes the index for that file.
    @discardableResult
    public func settingTaskDueDate(of task: TaskLine, at path: String, to date: CalendarDate?) async throws
        -> RawDocument
    {
        try await editingTask(task, at: path) { try $0.settingTaskDueDate(of: task, to: date, newID: $1) }
    }

    /// Writes or removes the start date.
    @discardableResult
    public func settingTaskStartDate(of task: TaskLine, at path: String, to date: CalendarDate?) async throws
        -> RawDocument
    {
        try await editingTask(task, at: path) { try $0.settingTaskStartDate(of: task, to: date, newID: $1) }
    }

    /// Writes or removes a supported priority.
    @discardableResult
    public func settingTaskPriority(of task: TaskLine, at path: String, to priority: TaskPriority?) async throws
        -> RawDocument
    {
        try await editingTask(task, at: path) { try $0.settingTaskPriority(of: task, to: priority, newID: $1) }
    }

    /// Writes or removes a project name without its `#project/` prefix.
    @discardableResult
    public func settingTaskProject(of task: TaskLine, at path: String, to project: String?) async throws -> RawDocument
    {
        try await editingTask(task, at: path) { try $0.settingTaskProject(of: task, to: project, newID: $1) }
    }

    private func editingTask(
        _ task: TaskLine, at path: String,
        transform: @escaping @Sendable (RawDocument, String?) throws -> RawDocument
    ) async throws -> RawDocument {
        try await perform {
            try self.edit(path) { document in
                try transform(document, self.replacementID(task.block, path: path, in: document))
            }
        }
    }
}
