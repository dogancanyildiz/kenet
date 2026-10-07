enum TaskFieldWriter {
    struct Edit {
        let range: Range<Int>
        let value: String
    }

    static func setting(_ kind: TaskFieldRange.Kind, token: String?, task: TaskLine) -> [Edit] {
        let ranges = task.fieldRanges.filter { $0.kind == kind }.map(\.byteRange)
        if let token {
            if let range = ranges.first { return [Edit(range: range, value: token)] }
            let end = LineParts(task.block.firstLineContent).text.upperBound
            return [Edit(range: end..<end, value: " " + token)]
        }
        return ranges.map { range in
            let start = range.lowerBound
            let bytes = task.block.firstLineContent
            let lower = start > 0 && Syntax.isBlank(bytes[start - 1]) ? start - 1 : start
            return Edit(range: lower..<range.upperBound, value: "")
        }
    }

    static func changingText(_ text: String, task: TaskLine) -> [Edit] {
        let parts = LineParts(task.block.firstLineContent)
        guard !task.fieldRanges.isEmpty else {
            return [Edit(range: parts.text, value: (parts.needsTextSeparator ? " " : "") + text)]
        }
        let bytes = task.block.firstLineContent
        var cursor = parts.text.lowerBound
        var gaps: [Range<Int>] = []
        for field in task.fieldRanges {
            gaps.append(cursor..<field.byteRange.lowerBound)
            cursor = field.byteRange.upperBound
        }
        gaps.append(cursor..<parts.text.upperBound)
        var used = false
        let edits = gaps.compactMap { gap -> Edit? in
            let lower = gap.lowerBound + bytes[gap].prefix(while: Syntax.isBlank).count
            let upper = gap.upperBound - bytes[gap].reversed().prefix(while: Syntax.isBlank).count
            guard lower < upper else { return nil }
            defer { used = true }
            return Edit(range: lower..<upper, value: used ? "" : text)
        }
        return used ? edits : [Edit(range: parts.text.upperBound..<parts.text.upperBound, value: " " + text)]
    }

    static func applying(_ edits: [Edit], to task: TaskLine, newID: String?) -> String {
        var bytes = task.block.firstLineContent
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.value.utf8)
        }
        // Field offsets belong to the original line; repair the identifier only after those edits.
        return LineParts(bytes).changing(bytes, range: nil, value: nil, newID: newID)
    }

    static func payload(
        _ text: String, due: CalendarDate?, start: CalendarDate?, priority: TaskPriority?, project: String?,
        recurrence: TaskRecurrence? = nil
    ) throws(EditError) -> String {
        if case .other = priority { throw .invalidValue }
        if let project, !TaskFieldParser.validProject(project) { throw .invalidValue }
        guard due != nil || start != nil || priority != nil || project != nil || recurrence != nil else { return text }
        let fields = TaskFieldParser.parse(text, offset: 0)
        let parsed = fields.values
        var rawText = Array(text.utf8)
        for field in fields.ranges.reversed() {
            let start = field.byteRange.lowerBound
            let lower = start > 0 && Syntax.isBlank(rawText[start - 1]) ? start - 1 : start
            rawText.removeSubrange(lower..<field.byteRange.upperBound)
        }
        let tokens: [String?] = [
            (start ?? parsed.startDate).map { "🛫 " + $0.description },
            (due ?? parsed.dueDate).map { "📅 " + $0.description },
            parsed.doneDate.map { "✅ " + $0.description },
            (priority ?? parsed.priority)?.token,
            (recurrence ?? parsed.recurrence).map { "🔁 " + $0.rule },
            (project ?? parsed.project).map { "#project/" + $0 },
        ]
        return ([Syntax.string(rawText)] + tokens.compactMap { $0 }).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
