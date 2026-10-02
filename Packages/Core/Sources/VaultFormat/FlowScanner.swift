/// Scans inline (flow) collections, which the supported subset limits to one line.
enum FlowScanner {
    /// The index of the bracket or brace that closes the collection opened at `open`, or `nil`
    /// when the line ends, or a comment starts, before it is closed.
    static func closingIndex(in line: [UInt8], openedAt open: Int) -> Int? {
        var depth = 0
        var isAtTokenStart = true
        var index = open
        while index < line.count {
            let byte = line[index]
            if isAtTokenStart, byte == Syntax.doubleQuote || byte == Syntax.singleQuote {
                guard let close = QuotedScalar.closingQuote(in: line, openedAt: index) else { return nil }
                index = close
                isAtTokenStart = false
            } else if byte == Syntax.openBracket || byte == Syntax.openBrace {
                depth += 1
                isAtTokenStart = true
            } else if byte == Syntax.closeBracket || byte == Syntax.closeBrace {
                depth -= 1
                if depth == 0 { return index }
                isAtTokenStart = false
            } else if byte == Syntax.comma {
                isAtTokenStart = true
            } else if byte == Syntax.colon {
                isAtTokenStart = index + 1 < line.count && Syntax.isBlank(line[index + 1])
            } else if byte == Syntax.hash, Syntax.isBlank(line[index - 1]) {
                return nil
            } else if !Syntax.isBlank(byte) {
                isAtTokenStart = false
            }
            index += 1
        }
        return nil
    }

    /// Whether the collection between `open` and `close` is YAML that every reader accepts.
    ///
    /// The grammar is deliberately narrower than YAML's: entries are quoted values, nested
    /// collections, plain values and `key: value` pairs, separated by commas. Anything readers
    /// are known to disagree on (a `?`, a colon inside a plain value, an empty entry, an anchor,
    /// alias or tag) is not valid here.
    static func isValid(_ line: [UInt8], openedAt open: Int, closedAt close: Int) -> Bool {
        collectionEnd(line, openedAt: open) == close
    }

    private static func collectionEnd(_ line: [UInt8], openedAt open: Int) -> Int? {
        let closer = line[open] == Syntax.openBracket ? Syntax.closeBracket : Syntax.closeBrace
        var index = skipBlanks(line, from: open + 1, to: line.count)
        guard index < line.count else { return nil }
        if line[index] == closer { return index }

        while true {
            guard let key = nodeEnd(line, from: index) else { return nil }
            index = skipBlanks(line, from: key.end, to: line.count)
            guard index < line.count else { return nil }
            if line[index] == Syntax.colon, key.isQuoted || endsFlowKey(line, colon: index) {
                index = skipBlanks(line, from: index + 1, to: line.count)
                guard index < line.count else { return nil }
                if line[index] != Syntax.comma, line[index] != closer {
                    guard let value = nodeEnd(line, from: index) else { return nil }
                    index = skipBlanks(line, from: value.end, to: line.count)
                    guard index < line.count else { return nil }
                }
            }
            if line[index] == closer { return index }
            guard line[index] == Syntax.comma else { return nil }
            index = skipBlanks(line, from: index + 1, to: line.count)
            guard index < line.count else { return nil }
            if line[index] == closer { return index }
        }
    }

    /// Whether the colon separates a key from its value: a blank, a comma, a closing bracket or
    /// the end of the line follows.
    private static func endsFlowKey(_ line: [UInt8], colon: Int) -> Bool {
        guard colon + 1 < line.count else { return true }
        let next = line[colon + 1]
        return Syntax.isBlank(next) || Syntax.flowIndicators.contains(next)
    }

    /// The index after the node that starts at `index`, or `nil` when it is not a valid node.
    private static func nodeEnd(_ line: [UInt8], from index: Int) -> (end: Int, isQuoted: Bool)? {
        let first = line[index]
        if first == Syntax.doubleQuote || first == Syntax.singleQuote {
            guard
                let close = QuotedScalar.closingQuote(in: line, openedAt: index),
                QuotedScalar.decode(line, openedAt: index, closedAt: close) != nil
            else { return nil }
            return (close + 1, true)
        }
        if first == Syntax.openBracket || first == Syntax.openBrace {
            guard let close = collectionEnd(line, openedAt: index) else { return nil }
            return (close + 1, false)
        }

        guard PlainScalar.canStart(line, at: index, end: line.count) else { return nil }
        var end = index
        while end < line.count, !Syntax.flowIndicators.contains(line[end]) {
            let byte = line[end]
            if byte == Syntax.colon {
                if endsFlowKey(line, colon: end) { break }
                return nil
            }
            if byte == Syntax.questionMark { return nil }
            if byte == Syntax.hash, end > index, Syntax.isBlank(line[end - 1]) { return nil }
            end += 1
        }
        return end > index ? (end, false) : nil
    }

    /// The items between the brackets when every item is a single plain or quoted value, or
    /// `nil` for anything else: nested collections, `key: value` pairs, empty items.
    static func simpleItems(in line: [UInt8], from start: Int, to end: Int) -> [FrontmatterScalar]? {
        var items: [FrontmatterScalar] = []
        var index = skipBlanks(line, from: start, to: end)
        if index == end { return [] }

        while true {
            guard index < end else { return nil }
            if line[index] == Syntax.doubleQuote || line[index] == Syntax.singleQuote {
                guard
                    let close = QuotedScalar.closingQuote(in: line, openedAt: index), close < end,
                    let text = QuotedScalar.decode(line, openedAt: index, closedAt: close)
                else { return nil }
                items.append(FrontmatterScalar(raw: Syntax.string(line[index...close]), text: text, kind: .text))
                index = close + 1
            } else {
                var itemEnd = index
                while itemEnd < end, line[itemEnd] != Syntax.comma {
                    guard !Syntax.flowIndicators.contains(line[itemEnd]) else { return nil }
                    itemEnd += 1
                }
                let next = itemEnd
                while itemEnd > index, Syntax.isBlank(line[itemEnd - 1]) {
                    itemEnd -= 1
                }
                guard itemEnd > index, PlainScalar.canStart(line, at: index, end: itemEnd) else { return nil }
                guard !PlainScalar.containsMappingIndicator(line[index..<itemEnd]) else { return nil }
                items.append(.plain(line[index..<itemEnd]))
                index = next
            }

            index = skipBlanks(line, from: index, to: end)
            if index == end { return items }
            guard line[index] == Syntax.comma else { return nil }
            index = skipBlanks(line, from: index + 1, to: end)
        }
    }

    private static func skipBlanks(_ line: [UInt8], from start: Int, to end: Int) -> Int {
        var index = start
        while index < end, Syntax.isBlank(line[index]) {
            index += 1
        }
        return index
    }
}
