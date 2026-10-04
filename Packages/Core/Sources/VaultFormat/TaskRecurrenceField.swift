package struct TaskRecurrenceField {
    package let range: Range<Int>
    let source: String
    var recurrence: TaskRecurrence? { TaskRecurrence(source) }

    package static func fields(in bytes: [UInt8]) -> [Self] {
        var protected = WikiLinkScanner.inlineCode(bytes)
        for range in WikiLinkScanner.scan(bytes).map(\.range) + MarkdownLinkMask.ranges(bytes, excluding: protected) {
            for index in range { protected[index] = true }
        }
        var fields: [Self] = []
        var cursor = 0
        while cursor < bytes.count {
            if !protected[cursor], cursor == 0 || Syntax.isBlank(bytes[cursor - 1]),
                let field = scan(bytes, start: cursor, protected: protected)
            {
                fields.append(field)
                cursor = max(cursor + 1, field.range.upperBound)
            } else {
                cursor += 1
            }
        }
        return fields
    }

    static func scan(_ bytes: [UInt8], start: Int, protected: [Bool]) -> Self? {
        let marker = Array("🔁".utf8)
        guard start + marker.count < bytes.count, Array(bytes[start..<(start + marker.count)]) == marker,
            Syntax.isBlank(bytes[start + marker.count])
        else { return nil }
        var end = start + marker.count
        while end < bytes.count, Syntax.isBlank(bytes[end]) { end += 1 }
        let ruleStart = end
        while end < bytes.count {
            if Syntax.isBlank(bytes[end]) {
                var next = end
                while next < bytes.count, Syntax.isBlank(bytes[next]) { next += 1 }
                let rest = Syntax.string(bytes[next...])
                if ["📅", "🛫", "✅", "⏫", "🔼", "🔽", "🔺", "⏬", "🔁", "#project/"].contains(where: rest.hasPrefix) { break }
            }
            if protected[end] { break }
            end += 1
        }
        while end > ruleStart, Syntax.isBlank(bytes[end - 1]) { end -= 1 }
        guard end >= ruleStart else { return nil }
        return Self(range: start..<end, source: Syntax.string(bytes[ruleStart..<end]))
    }
}
