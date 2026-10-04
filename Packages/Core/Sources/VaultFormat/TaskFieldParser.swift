enum TaskFieldParser {
    static func parse(_ text: String, offset: Int) -> ParsedTaskFields {
        let bytes = Array(text.utf8)
        var protected = WikiLinkScanner.inlineCode(bytes)
        for range in WikiLinkScanner.scan(bytes).map(\.range)
            + MarkdownLinkMask.ranges(bytes, excluding: protected)
        {
            for index in range { protected[index] = true }
        }
        var values = TaskFieldValues(text: text)
        var ranges: [TaskFieldRange] = []
        var cursor = 0
        while cursor < bytes.count {
            guard !Syntax.isBlank(bytes[cursor]), !protected[cursor], cursor == 0 || Syntax.isBlank(bytes[cursor - 1])
            else {
                cursor += 1
                continue
            }
            let start = cursor
            if let field = TaskRecurrenceField.scan(bytes, start: start, protected: protected) {
                if values.recurrenceSource == nil { values.recurrenceSource = field.source }
                if let recurrence = field.recurrence {
                    if values.recurrence == nil {
                        values.recurrence = recurrence
                        values.recurrenceSource = field.source
                    }
                    ranges.append(
                        TaskFieldRange(
                            kind: .recurrence, byteRange: (start + offset)..<(field.range.upperBound + offset)))
                }
                cursor = max(cursor + 1, field.range.upperBound)
                continue
            }
            while cursor < bytes.count, !Syntax.isBlank(bytes[cursor]) { cursor += 1 }
            let token = Syntax.string(bytes[start..<cursor])
            var kind: TaskFieldRange.Kind?
            if let dateKind = ["📅": TaskFieldRange.Kind.dueDate, "🛫": .startDate, "✅": .doneDate][token],
                cursor < bytes.count, bytes[cursor] == Syntax.space
            {
                let end = cursor + 11
                if end <= bytes.count, end == bytes.count || Syntax.isBlank(bytes[end]),
                    let date = CalendarDate(Syntax.string(bytes[(cursor + 1)..<end]))
                {
                    kind = dateKind
                    switch dateKind {
                    case .dueDate: if values.dueDate == nil { values.dueDate = date }
                    case .startDate: if values.startDate == nil { values.startDate = date }
                    case .doneDate: if values.doneDate == nil { values.doneDate = date }
                    default: break
                    }
                    cursor = end
                }
            } else if let priority = [
                "⏫": TaskPriority.high, "🔼": .medium, "🔽": .low, "🔺": .other("🔺"), "⏬": .other("⏬"),
            ][token] {
                kind = .priority
                if values.priority == nil { values.priority = priority }
            } else if token.hasPrefix("#project/"), validProject(String(token.dropFirst(9))) {
                kind = .project
                if values.project == nil { values.project = String(token.dropFirst(9)) }
            }
            if let kind, !(start..<cursor).contains(where: { protected[$0] }) {
                ranges.append(TaskFieldRange(kind: kind, byteRange: (start + offset)..<(cursor + offset)))
            }
        }
        var remaining = bytes
        for range in ranges.reversed() {
            remaining.removeSubrange((range.byteRange.lowerBound - offset)..<(range.byteRange.upperBound - offset))
        }
        values.text = normalizedText(Syntax.string(remaining))
        return ParsedTaskFields(values: values, ranges: ranges)
    }

    static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    static func validProject(_ project: String) -> Bool {
        !project.isEmpty && !project.contains(where: { $0.isWhitespace || "[]#^`\\|<>".contains($0) })
    }
}
