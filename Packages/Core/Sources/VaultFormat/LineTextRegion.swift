/// The user's text within an event or task first line: no list marker, clock, checkbox, field or identifier.
///
/// Recognition and the unlinked mentions query read a line's structure through this one definition,
/// so what the app links while writing and what it offers to link later cannot drift apart.
package struct LineTextRegion: Sendable {
    /// The text's UTF-8 range within the first line's content; empty for a line it does not understand.
    package let text: Range<Int>
    /// Ranges inside the text that hold a field rather than the user's words.
    package let fields: [Range<Int>]

    /// A task's text without its recognized fields, any recurrence rule and Obsidian Tasks' other dates.
    package init(_ task: TaskLine) {
        let text = Self.text(of: task.block)
        self.text = text
        fields =
            task.fieldRanges.map(\.byteRange)
            + Self.unreadFields(Array(task.block.firstLineContent[text])).map {
                ($0.lowerBound + text.lowerBound)..<($0.upperBound + text.lowerBound)
            }
    }

    package init(_ block: LineBlock, fields: [Range<Int>] = []) {
        text = Self.text(of: block)
        self.fields = fields
    }

    /// Every task line, in any section, and every event line of a document, by physical line number.
    package static func regions(in document: RawDocument) -> [Int: LineTextRegion] {
        let body = document.bodyLines
        var regions: [Int: LineTextRegion] = [:]
        for event in body.events { regions[event.block.line] = LineTextRegion(event.block) }
        for task in body.tasks { regions[task.block.line] = LineTextRegion(task) }
        return regions
    }

    package func contains(_ range: Range<Int>) -> Bool {
        text.lowerBound <= range.lowerBound && range.upperBound <= text.upperBound
            && !fields.contains(where: { $0.overlaps(range) })
    }

    /// Marks every byte of the line that is not the user's text.
    package func exclude(from excluded: inout [Bool]) {
        for index in excluded.indices where !text.contains(index) { excluded[index] = true }
        for field in fields {
            for index in field where excluded.indices.contains(index) { excluded[index] = true }
        }
    }

    private static func text(of block: LineBlock) -> Range<Int> {
        let content = block.firstLineContent
        var end = content.count
        if let id = block.id {
            while end > 0, content[end - 1] == 32 || content[end - 1] == 9 { end -= 1 }
            end -= id.utf8.count + 2
        }
        let start = end - block.text.utf8.count
        // The parsed text is the slice that ends where the identifier begins. A line that does not
        // fit that shape is not one this region understands, and its empty text holds nothing.
        guard start >= 0, end <= content.count, content[start..<end].elementsEqual(block.text.utf8) else {
            return 0..<0
        }
        return start..<end
    }

    /// Fields the task model keeps as text: a recurrence rule it cannot read, which runs to the end
    /// of the line, and the scheduled and created dates of Obsidian Tasks.
    private static func unreadFields(_ bytes: [UInt8]) -> [Range<Int>] {
        var ranges = TaskRecurrenceField.fields(in: bytes).map(\.range)
        var cursor = 0
        while cursor < bytes.count {
            guard !Syntax.isBlank(bytes[cursor]), cursor == 0 || Syntax.isBlank(bytes[cursor - 1]) else {
                cursor += 1
                continue
            }
            let start = cursor
            while cursor < bytes.count, !Syntax.isBlank(bytes[cursor]) { cursor += 1 }
            let end = cursor + 11
            if ["⏳", "➕"].contains(Syntax.string(bytes[start..<cursor])), cursor < bytes.count,
                bytes[cursor] == Syntax.space, end <= bytes.count, end == bytes.count || Syntax.isBlank(bytes[end]),
                CalendarDate(Syntax.string(bytes[(cursor + 1)..<end])) != nil
            {
                ranges.append(start..<end)
                cursor = end
            }
        }
        return ranges
    }
}
