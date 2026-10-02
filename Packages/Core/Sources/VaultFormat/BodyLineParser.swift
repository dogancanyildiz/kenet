/// Reads list syntax without normalizing or changing document bytes.
enum BodyLineParser {
    static func parse(_ document: RawDocument) -> BodyLines {
        let lines = document.lines
        let start = document.frontmatterLineRange?.upperBound ?? 0
        let scan = SectionParser.scan(lines, startingAt: start)
        let events = scan.sections.section(.events)?.lineRange
        let ends = blockEnds(lines)
        var tasks: [TaskLine] = []
        var eventLines: [EventLine] = []
        for index in start..<lines.count {
            guard !scan.fencedBoundaries.contains(index), lines[index].text != nil else { continue }
            let bytes = lines[index].content
            let indent = indentation(bytes)
            if let checkbox = task(bytes) {
                let identified = splitID(Syntax.string(bytes))
                let parsed = task(Array(identified.text.utf8))
                let isQuoted = bytes.prefix { Syntax.isBlank($0) || $0 == UInt8(ascii: ">") }
                    .contains(UInt8(ascii: ">"))
                let end = isQuoted ? index + 1 : ends[index]
                tasks.append(
                    TaskLine(
                        block: LineBlock(
                            lineRange: index..<end, id: identified.id, text: parsed?.text ?? "",
                            firstLineContent: bytes, kind: .task),
                        rawStatus: checkbox.raw, status: status(checkbox.raw)))
            } else if indent == 0, events?.contains(index) == true,
                bytes.count >= 2, isBullet(bytes[0]), bytes[1] == Syntax.space
            {
                let identified = splitID(Syntax.string(bytes))
                let clock = event(bytes)
                eventLines.append(
                    EventLine(
                        block: LineBlock(
                            lineRange: index..<ends[index], id: identified.id, text: clock.text,
                            firstLineContent: bytes, kind: .event),
                        time: clock.time))
            }
        }
        return BodyLines(tasks: tasks, events: eventLines)
    }

    private static func isBullet(_ byte: UInt8) -> Bool {
        [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+")].contains(byte)
    }

    static func task(_ bytes: [UInt8]) -> (
        raw: String, text: String, textStart: Int, statusRange: Range<Int>, hasSeparator: Bool
    )? {
        var cursor = bytes.prefix { Syntax.isBlank($0) || $0 == UInt8(ascii: ">") }.count
        guard cursor < bytes.count else { return nil }
        if isBullet(bytes[cursor]) {
            cursor += 1
        } else {
            let start = cursor
            while cursor < bytes.count, Syntax.isDigit(bytes[cursor]) { cursor += 1 }
            guard (1...9).contains(cursor - start), cursor < bytes.count,
                bytes[cursor] == UInt8(ascii: ".") || bytes[cursor] == UInt8(ascii: ")")
            else { return nil }
            cursor += 1
        }
        guard cursor < bytes.count, bytes[cursor] == Syntax.space else { return nil }
        while cursor < bytes.count, bytes[cursor] == Syntax.space { cursor += 1 }
        guard cursor < bytes.count, bytes[cursor] == Syntax.openBracket else { return nil }
        cursor += 1
        guard let scalar = Syntax.string(bytes.dropFirst(cursor)).unicodeScalars.first else { return nil }
        let raw = String(scalar)
        let statusStart = cursor
        cursor += raw.utf8.count
        guard cursor < bytes.count, bytes[cursor] == Syntax.closeBracket else { return nil }
        cursor += 1
        guard cursor == bytes.count || bytes[cursor] == Syntax.space else { return nil }
        let textStart = min(cursor + 1, bytes.count)
        return (
            raw, Syntax.string(bytes.dropFirst(textStart)), textStart, statusStart..<(statusStart + raw.utf8.count),
            cursor < bytes.count
        )
    }

    private static func indentation(_ bytes: [UInt8]) -> Int {
        LineSyntax.indentation(bytes).columns
    }

    private static func status(_ raw: String) -> TaskStatus {
        switch raw {
        case " ": .todo
        case "/": .inProgress
        case "x", "X": .done
        case "-": .cancelled
        default: .unknown
        }
    }

    static func splitID(_ text: String) -> (text: String, id: String?) {
        let bytes = Array(text.utf8)
        let end = bytes.count - bytes.reversed().prefix(while: Syntax.isBlank).count
        var caret = end
        while caret > 0, isIDByte(bytes[caret - 1]) { caret -= 1 }
        guard caret < end, caret >= 2, bytes[caret - 1] == UInt8(ascii: "^"), bytes[caret - 2] == Syntax.space
        else { return (text, nil) }
        return (Syntax.string(bytes[..<(caret - 2)]), Syntax.string(bytes[caret..<end]))
    }

    static func isIDByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || Syntax.isDigit(byte) || byte == Syntax.dash
    }

    /// Returns event text and clock offsets in the original bytes, including empty identified items.
    static func event(_ bytes: [UInt8]) -> (
        time: EventTime?, text: String, textRange: Range<Int>, clockStart: Int, tokenRange: Range<Int>?,
        removalRange: Range<Int>?, needsIDSuffix: Bool
    ) {
        let split = splitID(Syntax.string(bytes))
        let textEnd = split.text.utf8.count
        let clockStart = 1 + bytes.dropFirst().prefix(while: Syntax.isBlank).count
        let clock = time(Syntax.string(bytes[clockStart..<max(clockStart, textEnd)]))
        let tokenEnd = clockStart + (clock.time?.raw.utf8.count ?? 0)
        let start = clock.time == nil ? clockStart : min(tokenEnd + 1, bytes.count)
        let end = max(start, textEnd)
        return (
            clock.time, Syntax.string(bytes[start..<end]), start..<end, clockStart,
            clock.time.map { _ in clockStart..<tokenEnd },
            clock.time.map { _ in clockStart..<start }, split.id != nil && start > textEnd
        )
    }

    private static func time(_ text: String) -> (time: EventTime?, text: String) {
        let bytes = Array(text.utf8)
        let digits = bytes.prefix(while: Syntax.isDigit).count
        guard (1...2).contains(digits), bytes.count >= digits + 3, bytes[digits] == Syntax.colon,
            Syntax.isDigit(bytes[digits + 1]), Syntax.isDigit(bytes[digits + 2])
        else { return (nil, text) }
        let end = digits + 3
        guard bytes.count == end || bytes[end] == Syntax.space else { return (nil, text) }
        let hour = bytes[..<digits].reduce(0) { $0 * 10 + Int($1 - 48) }
        let minute = Int(bytes[digits + 1] - 48) * 10 + Int(bytes[digits + 2] - 48)
        guard hour <= 23, minute <= 59 else { return (nil, text) }
        return (
            EventTime(hour: hour, minute: minute, raw: Syntax.string(bytes[..<end])),
            Syntax.string(bytes.dropFirst(min(end + 1, bytes.count)))
        )
    }

    /// Precomputes continuation extents in linear time; trailing blank lines are excluded.
    private static func blockEnds(_ lines: [RawLine]) -> [Int] {
        var ends = Array(repeating: 0, count: lines.count)
        var stack: [(line: Int, indent: Int)] = []
        var lastNonblank = -1
        for index in lines.indices {
            let bytes = lines[index].content
            if bytes.allSatisfy(Syntax.isBlank) { continue }
            let indent = indentation(bytes)
            while let previous = stack.last, previous.indent >= indent {
                ends[previous.line] = lastNonblank + 1
                stack.removeLast()
            }
            stack.append((index, indent))
            lastNonblank = index
        }
        for previous in stack { ends[previous.line] = lastNonblank + 1 }
        return ends
    }
}
