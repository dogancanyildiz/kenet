extension RawDocument {
    /// Inserts an event before the first later time, or at the section's end.
    public func addingEvent(text: String, id: String, time: LineClock? = nil) throws(EditError) -> RawDocument {
        try addLine(text: text, id: id, time: time, task: false)
    }

    /// Appends an unchecked task to Tasks, creating that section if necessary.
    public func addingTask(
        text: String, id: String, due: CalendarDate? = nil, start: CalendarDate? = nil,
        priority: TaskPriority? = nil, project: String? = nil, recurrence: TaskRecurrence? = nil
    ) throws(EditError) -> RawDocument {
        try addLine(
            text: TaskFieldWriter.payload(
                text, due: due, start: start, priority: priority, project: project, recurrence: recurrence),
            id: id, time: nil, task: true)
    }

    /// Replaces only the first-line text and, when supplied, the identifier.
    public func changingText(of target: LineBlock, to text: String, newID: String? = nil) throws(EditError)
        -> RawDocument
    {
        var desired = try requireTarget(target)
        let text = try LineParts.clean(text)
        try LineParts.validateID(newID)
        if let task = bodyLines.tasks.first(where: { $0.block == target }) {
            return try changingTaskText(of: task, to: text, newID: newID)
        }
        let parts = LineParts(lines[target.line].content)
        let content = parts.changing(
            lines[target.line].content, range: parts.text,
            value: (parts.needsTextSeparator ? " " : "") + text + (parts.needsIDSuffix ? " " : ""),
            newID: newID)
        desired.block = LineBlock(lineRange: target.lineRange, id: newID ?? target.id, text: text)
        return try rewrite(target, content: content, desired: desired)
    }

    /// Changes the checkbox and completion date, and optionally assigns an identifier.
    public func changingStatus(
        of target: TaskLine, to status: TaskStatus, completionDate: CalendarDate? = nil, newID: String? = nil
    ) throws(EditError) -> RawDocument {
        _ = try requireTarget(target.block)
        guard bodyLines.tasks.contains(target) else { throw .targetNotFound }
        try LineParts.validateID(newID)
        let raw: String
        switch status {
        case .todo: raw = " "
        case .inProgress: raw = "/"
        case .done: raw = "x"
        case .cancelled: raw = "-"
        case .unknown: throw .invalidValue
        }
        let parts = LineParts(lines[target.block.line].content)
        let writtenStatus = status == target.status ? target.rawStatus : raw
        var edits = [TaskFieldWriter.Edit(range: parts.status!, value: writtenStatus)]
        var values = target.fields.values
        if status == .done {
            guard let date = completionDate ?? (target.status == .done ? target.doneDate : nil) else {
                throw .invalidValue
            }
            values.doneDate = date
            edits += TaskFieldWriter.setting(.doneDate, token: "✅ " + date.description, task: target)
        } else if status == .todo || status == .inProgress {
            values.doneDate = nil
            edits += TaskFieldWriter.setting(.doneDate, token: nil, task: target)
        }
        let content = TaskFieldWriter.applying(edits, to: target, newID: newID)
        return try rewritingTask(target, content: content, values: values, status: writtenStatus, newID: newID)
    }

    /// Changes an event's time, moving the complete block only when the rule requires it.
    public func changingTime(
        of target: EventLine, to time: LineClock?, newID: String? = nil
    ) throws(EditError) -> RawDocument {
        var desired = try requireTarget(target.block)
        guard bodyLines.events.contains(target) else { throw .targetNotFound }
        try LineParts.validateID(newID)
        let same = target.time?.hour == time?.hour && target.time?.minute == time?.minute
        let parts = LineParts(lines[target.block.line].content)
        let range = time == nil ? parts.clockRemoval : parts.clockToken ?? (parts.clockStart..<parts.clockStart)
        let value = time.map { $0.token + (parts.clockToken == nil ? " " : "") } ?? ""
        let content = parts.changing(
            lines[target.block.line].content, range: same ? nil : range, value: value, newID: newID)
        desired.time = same ? target.time : time?.eventTime
        desired.block = LineBlock(
            lineRange: target.block.lineRange, id: newID ?? target.block.id, text: target.block.text)
        let position = time != nil && !same ? eventPosition(time, excluding: target.block.lineRange) : target.block.line
        if staysInPlace(target.block.lineRange, position: position) {
            return try rewrite(target.block, content: content, desired: desired)
        }
        var contents = target.block.lineRange.map { lines[$0].text! }
        contents[0] = content
        let edits = [LineEdit(range: target.block.lineRange, contents: []), .inserting(contents, at: position)]
        var origins: [Int?] = lines.indices.map { $0 }
        origins.removeSubrange(target.block.lineRange)
        let destination = position > target.block.line ? position - target.block.lineRange.count : position
        origins.insert(contentsOf: target.block.lineRange.map { Optional($0) }, at: destination)
        desired.block = LineBlock(
            lineRange: destination..<(destination + contents.count), id: desired.block.id, text: desired.block.text)
        return try applyBodyLines(
            edits, origins: origins, target: target.block, desired: desired, changedLine: target.block.line)
    }

    /// Removes exactly the target's occupied lines, retaining its section heading.
    public func deletingBlock(_ target: LineBlock) throws(EditError) -> RawDocument {
        _ = try requireTarget(target)
        var origins: [Int?] = lines.indices.map { $0 }
        origins.removeSubrange(target.lineRange)
        return try applyBodyLines(
            [LineEdit(range: target.lineRange, contents: [])], origins: origins, target: target, desired: nil)
    }

    private func rewrite(_ target: LineBlock, content: String, desired: WrittenBlock) throws(EditError) -> RawDocument {
        try applyBodyLines(
            [.replacing(line: target.line, with: content)], origins: lines.indices.map { $0 },
            target: target, desired: desired, changedLine: target.line)
    }

    private func applyBodyLines(
        _ edits: [LineEdit], origins: [Int?], target: LineBlock?, desired: WrittenBlock?, changedLine: Int? = nil
    ) throws(EditError) -> RawDocument {
        try validatingLines(
            applying(edits), origins: origins, target: target, desired: desired, changedLine: changedLine)
    }

    private func staysInPlace(_ range: Range<Int>, position: Int) -> Bool {
        let between =
            position < range.lowerBound
            ? position..<range.lowerBound : range.upperBound..<max(range.upperBound, position)
        return lines[between].allSatisfy { $0.content.allSatisfy(Syntax.isBlank) }
    }

    private func eventPosition(_ time: LineClock?, excluding range: Range<Int>? = nil) -> Int {
        if let time,
            let next = bodyLines.events.first(where: {
                $0.block.lineRange != range
                    && $0.time.map { $0.hour * 60 + $0.minute > time.hour * 60 + time.minute } == true
            })
        {
            return next.block.line
        }
        let section = daySections.section(.events)!
        return
            (section.lineRange.last {
                range?.contains($0) != true && !lines[$0].content.allSatisfy(Syntax.isBlank)
            } ?? section.headingLine) + 1
    }

    private func addLine(text: String, id: String, time: LineClock?, task: Bool) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        let text = try LineParts.clean(text)
        try LineParts.validateID(id)
        let kind: DaySectionKind = task ? .tasks : .events
        let content = "- " + (task ? "[ ] " : time.map { $0.token + " " } ?? "") + text + " ^" + id
        let section = daySections.section(kind)
        let position: Int
        let edited: RawDocument
        if let section {
            position =
                task
                ? section.lineRange.last { !lines[$0].content.allSatisfy(Syntax.isBlank) }! + 1 : eventPosition(time)
            var origins: [Int?] = lines.indices.map { $0 }
            origins.insert(nil, at: position)
            let desired = WrittenBlock(
                block: LineBlock(lineRange: position..<(position + 1), id: id, text: text),
                time: time?.eventTime, status: task ? " " : nil,
                task: task ? TaskFieldParser.parse(text, offset: 0).values : nil)
            return try applyBodyLines(
                [.inserting([content], at: position)], origins: origins, target: nil, desired: desired)
        } else {
            let following = DaySectionKind.allCases.drop { $0 != kind }.dropFirst()
            position = following.lazy.compactMap { daySections.section($0)?.headingLine }.first ?? lines.count
            edited = try appendingLines([content], toSection: kind)
        }
        let delta = edited.lines.count - lines.count
        var origins: [Int?] = lines.indices.map { $0 }
        origins.insert(contentsOf: Array(repeating: nil, count: delta), at: position)
        let start = section != nil ? position : edited.daySections.section(kind)!.headingLine + 1
        let desired = WrittenBlock(
            block: LineBlock(lineRange: start..<(start + 1), id: id, text: text),
            time: time?.eventTime, status: task ? " " : nil,
            task: task ? TaskFieldParser.parse(text, offset: 0).values : nil)
        return try validatingLines(
            edited, origins: origins, target: nil, desired: desired, addedSection: section == nil ? kind : nil)
    }
}
