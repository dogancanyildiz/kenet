extension RawDocument {
    /// Sets or removes the first-line due date without moving existing fields.
    public func settingTaskDueDate(of task: TaskLine, to date: CalendarDate?, newID: String? = nil) throws(EditError)
        -> RawDocument
    {
        var values = task.fields.values
        values.dueDate = date
        return try settingTaskField(
            .dueDate, of: task, token: date.map { "📅 " + $0.description }, values: values, newID: newID)
    }

    /// Sets or removes the first-line start date.
    public func settingTaskStartDate(of task: TaskLine, to date: CalendarDate?, newID: String? = nil) throws(EditError)
        -> RawDocument
    {
        var values = task.fields.values
        values.startDate = date
        return try settingTaskField(
            .startDate, of: task, token: date.map { "🛫 " + $0.description }, values: values, newID: newID)
    }

    /// Only high, medium and low can be written; other source priorities can be removed.
    public func settingTaskPriority(of task: TaskLine, to priority: TaskPriority?, newID: String? = nil)
        throws(EditError)
        -> RawDocument
    {
        if case .other = priority { throw .invalidValue }
        var values = task.fields.values
        values.priority = priority
        return try settingTaskField(.priority, of: task, token: priority?.token, values: values, newID: newID)
    }

    /// Sets or removes a project; the supplied value excludes `#project/`.
    public func settingTaskProject(of task: TaskLine, to project: String?, newID: String? = nil) throws(EditError)
        -> RawDocument
    {
        if let project, !TaskFieldParser.validProject(project) { throw .invalidValue }
        var values = task.fields.values
        values.project = project
        return try settingTaskField(
            .project, of: task, token: project.map { "#project/" + $0 }, values: values, newID: newID)
    }

    private func settingTaskField(
        _ kind: TaskFieldRange.Kind, of task: TaskLine, token: String?, values: TaskFieldValues, newID: String?
    ) throws(EditError) -> RawDocument {
        _ = try requireTarget(task.block)
        guard bodyLines.tasks.contains(task) else { throw .targetNotFound }
        let content = TaskFieldWriter.applying(
            TaskFieldWriter.setting(kind, token: token, task: task), to: task, newID: newID)
        return try rewritingTask(task, content: content, values: values, newID: newID)
    }

    func changingTaskText(of task: TaskLine, to text: String, newID: String?) throws(EditError) -> RawDocument {
        var values = task.fields.values
        values.text = TaskFieldParser.normalizedText(text)
        let content = TaskFieldWriter.applying(TaskFieldWriter.changingText(text, task: task), to: task, newID: newID)
        return try rewritingTask(task, content: content, values: values, newID: newID)
    }

    func rewritingTask(
        _ task: TaskLine, content: String, values: TaskFieldValues, status: String? = nil, newID: String?
    ) throws(EditError) -> RawDocument {
        var desired = try requireTarget(task.block)
        try LineParts.validateID(newID)
        guard bodyLines.tasks.contains(task) else { throw .targetNotFound }
        let rawText = BodyLineParser.task(Array(BodyLineParser.splitID(content).text.utf8))?.text ?? ""
        desired.block = LineBlock(lineRange: task.block.lineRange, id: newID ?? task.block.id, text: rawText)
        desired.task = values
        desired.status = status ?? task.rawStatus
        return try validatingLines(
            applying([.replacing(line: task.block.line, with: content)]), origins: lines.indices.map { $0 },
            target: task.block, desired: desired, changedLine: task.block.line)
    }
}
