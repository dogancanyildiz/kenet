extension RawDocument {
    /// Explicitly replace/remove recurrence, including an unsupported source rule.
    public func settingTaskRecurrence(of task: TaskLine, to recurrence: TaskRecurrence?, newID: String? = nil)
        throws(EditError) -> RawDocument
    {
        _ = try requireTarget(task.block)
        guard bodyLines.tasks.contains(task) else { throw .targetNotFound }
        let fields = TaskRecurrenceField.fields(in: task.block.firstLineContent)
        let edits: [TaskFieldWriter.Edit]
        if fields.isEmpty {
            edits = TaskFieldWriter.setting(.recurrence, token: recurrence.map { "🔁 " + $0.rule }, task: task)
        } else {
            edits = fields.enumerated().map { index, field in
                let lower = field.range.lowerBound
                let replacement = index == 0 ? recurrence.map { "🔁 " + $0.rule } : nil
                let start =
                    replacement == nil && lower > 0 && Syntax.isBlank(task.block.firstLineContent[lower - 1])
                    ? lower - 1 : lower
                return TaskFieldWriter.Edit(range: start..<field.range.upperBound, value: replacement ?? "")
            }
        }
        let content = TaskFieldWriter.applying(edits, to: task, newID: newID)
        let parsed = RawDocument(bytes: content.utf8).bodyLines.tasks.first
        guard let parsed else { throw .contentNotRepresentable }
        return try rewritingTask(task, content: content, values: parsed.fields.values, newID: newID)
    }

    /// Complete in place and insert a fresh, one-line occurrence immediately above it.
    public func completingRecurringTask(
        _ task: TaskLine, completionDate: CalendarDate, newID: String,
        completedID: String? = nil
    ) throws(EditError) -> RawDocument {
        _ = try requireTarget(task.block)
        guard !task.status.isClosed, let recurrence = task.recurrence else { throw .invalidValue }
        try LineParts.validateID(newID)
        guard !WrittenBlock.all(self).contains(where: { $0.block.id == newID }), newID != completedID else {
            throw .invalidValue
        }
        let reference = task.dueDate ?? task.startDate ?? completionDate
        guard let next = recurrence.nextOccurrence(after: reference, completedOn: completionDate) else {
            throw .invalidValue
        }
        let shiftedStart = task.startDate?.addingDays(next.ordinal - reference.ordinal)
        guard task.startDate == nil || shiftedStart != nil else { throw .invalidValue }
        let completed = try changingStatus(of: task, to: .done, completionDate: completionDate, newID: completedID)
        guard let source = completed.bodyLines.tasks.first(where: { $0.block.line == task.block.line }) else {
            throw .contentNotRepresentable
        }
        let parts = LineParts(source.block.firstLineContent)
        var edits = [TaskFieldWriter.Edit(range: parts.status!, value: " ")]
        edits += TaskFieldWriter.setting(.dueDate, token: "📅 " + next.description, task: source)
        edits += TaskFieldWriter.setting(.doneDate, token: nil, task: source)
        if let shiftedStart {
            edits += TaskFieldWriter.setting(.startDate, token: "🛫 " + shiftedStart.description, task: source)
        }
        let content = TaskFieldWriter.applying(edits, to: source, newID: newID)
        let position = task.block.line
        let edited = try completed.applying([.inserting([content], at: position)])
        return try completed.validatingRecurrenceInsertion(edited, content: content, at: position, id: newID)
    }

    private func validatingRecurrenceInsertion(_ edited: RawDocument, content: String, at position: Int, id: String)
        throws(EditError) -> RawDocument
    {
        let result = RawDocument(bytes: edited.serialized())
        guard result.lines.count == lines.count + 1, result.hasByteOrderMark == hasByteOrderMark,
            result.frontmatter == frontmatter, result.daySections.sections.count == daySections.sections.count,
            let added = result.bodyLines.tasks.first(where: { $0.block.line == position }),
            added.block.id == id, added.status == .todo, added.doneDate == nil, added.block.lineRange.count == 1,
            added.block.firstLineContent == Array(content.utf8)
        else { throw .contentNotRepresentable }
        for index in lines.indices {
            guard lines[index] == result.lines[index < position ? index : index + 1] else {
                throw .contentNotRepresentable
            }
        }
        var expected = WrittenBlock.all(self).map { original in
            var item = original
            let range = item.block.lineRange
            let lower = range.lowerBound >= position ? range.lowerBound + 1 : range.lowerBound
            let upper = range.upperBound > position ? range.upperBound + 1 : range.upperBound
            item.block = LineBlock(
                lineRange: lower..<upper, id: item.block.id, text: item.block.text, kind: item.block.kind)
            return item
        }
        expected.append(WrittenBlock(block: added.block, status: added.rawStatus, task: added.fields.values))
        expected.sort { $0.block.line < $1.block.line }
        guard expected == WrittenBlock.all(result) else { throw .contentNotRepresentable }
        return result
    }
}
