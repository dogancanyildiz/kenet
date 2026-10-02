/// What follows a key or a list dash on its line.
enum ScannedValue {
    /// A single value, possibly empty.
    case scalar(FrontmatterScalar, gap: String, tail: String)
    /// An inline list of single values.
    case list([FrontmatterScalar], gap: String, tail: String)
    /// A block scalar header (`|` or `>`): the following indented lines are its text. The
    /// header may state how many spaces the text is indented by.
    case blockScalar(indentation: Int?)
    /// Valid YAML outside the supported subset. An anchor with nothing after it may be followed
    /// by the lines of the collection it names.
    case unsupported(acceptsChildren: Bool)
    /// Not YAML every reader accepts, or a value whose end cannot be known from this line: the
    /// frontmatter cannot be trusted.
    case broken
}

/// The key at the start of a `key: value` line.
enum ScannedKey {
    /// The key and the index of the colon that ends it.
    case key(String, colon: Int)
    /// The line does not start with a key.
    case notAKey
    /// A quoted key whose quote is not closed on the line.
    case broken
}

/// Scans the pieces of a single frontmatter line.
enum FrontmatterLineScanner {
    /// Whether a list item starts at `index`: a dash followed by a space or the end of the line.
    /// A tab after the dash is not accepted by every reader.
    static func isListItem(_ line: [UInt8], at index: Int) -> Bool {
        guard index < line.count, line[index] == Syntax.dash else { return false }
        return index + 1 == line.count || line[index + 1] == Syntax.space
    }

    /// Scans the key that starts at `start`, which must be inside the line.
    static func key(in line: [UInt8], from start: Int) -> ScannedKey {
        let first = line[start]
        if first == Syntax.doubleQuote || first == Syntax.singleQuote {
            guard let close = QuotedScalar.closingQuote(in: line, openedAt: start) else { return .broken }
            guard let key = QuotedScalar.decode(line, openedAt: start, closedAt: close) else { return .notAKey }
            var index = close + 1
            while index < line.count, Syntax.isBlank(line[index]) {
                index += 1
            }
            guard index < line.count, line[index] == Syntax.colon, endsKey(line, colon: index) else { return .notAKey }
            return .key(key, colon: index)
        }

        guard PlainScalar.canStart(line, at: start, end: line.count) else { return .notAKey }
        guard let colon = (start..<line.count).first(where: { line[$0] == Syntax.colon && endsKey(line, colon: $0) })
        else { return .notAKey }
        var end = colon
        while end > start, Syntax.isBlank(line[end - 1]) {
            end -= 1
        }
        guard end > start, !PlainScalar.containsComment(line[start..<end]) else { return .notAKey }
        guard PlainScalar.isCertainKey(Array(line[start..<end])) else { return .notAKey }
        return .key(Syntax.string(line[start..<end]), colon: colon)
    }

    private static func endsKey(_ line: [UInt8], colon: Int) -> Bool {
        colon + 1 == line.count || Syntax.isBlank(line[colon + 1])
    }

    /// Scans the value that follows the key colon or list dash, starting at `start`.
    ///
    /// Anchors found on the way are added to `anchors`; an alias is only valid when its anchor
    /// is already there.
    static func value(
        in line: [UInt8],
        from start: Int,
        allowsList: Bool,
        anchors: inout Set<[UInt8]>
    ) -> ScannedValue {
        var index = start
        while index < line.count, Syntax.isBlank(line[index]) {
            index += 1
        }
        let startsComment = index < line.count && line[index] == Syntax.hash && index > start
        guard index < line.count, !startsComment else {
            return .scalar(.plain([]), gap: "", tail: Syntax.string(line[start...]))
        }
        let gap = Syntax.string(line[start..<index])
        let first = line[index]

        if first == Syntax.doubleQuote || first == Syntax.singleQuote {
            guard
                let close = QuotedScalar.closingQuote(in: line, openedAt: index),
                let tail = tail(of: line, from: close + 1),
                let text = QuotedScalar.decode(line, openedAt: index, closedAt: close)
            else { return .broken }
            let scalar = FrontmatterScalar(raw: Syntax.string(line[index...close]), text: text, kind: .text)
            return .scalar(scalar, gap: gap, tail: tail)
        }

        if first == Syntax.openBracket || first == Syntax.openBrace {
            guard
                let close = FlowScanner.closingIndex(in: line, openedAt: index),
                let tail = tail(of: line, from: close + 1),
                FlowScanner.isValid(line, openedAt: index, closedAt: close)
            else { return .broken }
            guard
                first == Syntax.openBracket, allowsList,
                let items = FlowScanner.simpleItems(in: line, from: index + 1, to: close)
            else { return .unsupported(acceptsChildren: false) }
            return .list(items, gap: gap, tail: tail)
        }

        if first == UInt8(ascii: "|") || first == UInt8(ascii: ">") {
            return blockScalarHeader(line, at: index)
        }
        if first == UInt8(ascii: "&") || first == UInt8(ascii: "*") || first == UInt8(ascii: "!") {
            return property(in: line, at: index, anchors: &anchors)
        }
        guard PlainScalar.canStart(line, at: index, end: line.count) else { return .broken }

        // A `#` starts a comment only after a blank; elsewhere it is part of the value.
        let comment = ((index + 1)..<line.count).first { line[$0] == Syntax.hash && Syntax.isBlank(line[$0 - 1]) }
        var end = comment ?? line.count
        while Syntax.isBlank(line[end - 1]) {
            end -= 1
        }
        guard !PlainScalar.containsMappingIndicator(line[index..<end]) else { return .broken }
        return .scalar(.plain(line[index..<end]), gap: gap, tail: Syntax.string(line[end...]))
    }

    /// Reads `|` or `>` at `index`, which may be followed by a chomping indicator, an
    /// indentation digit and a comment, and by nothing else.
    private static func blockScalarHeader(_ line: [UInt8], at index: Int) -> ScannedValue {
        var end = index + 1
        var hasChomping = false
        var indentation: Int?
        while end < line.count {
            let byte = line[end]
            if !hasChomping, byte == UInt8(ascii: "+") || byte == Syntax.dash {
                hasChomping = true
            } else if indentation == nil, byte >= UInt8(ascii: "1"), byte <= UInt8(ascii: "9") {
                indentation = Int(byte - UInt8(ascii: "0"))
            } else {
                break
            }
            end += 1
        }
        return tail(of: line, from: end) != nil ? .blockScalar(indentation: indentation) : .broken
    }

    /// Scans a value that starts with an anchor, an alias or a tag. These are never read, only
    /// kept; what matters is whether every reader accepts them.
    private static func property(in line: [UInt8], at index: Int, anchors: inout Set<[UInt8]>) -> ScannedValue {
        var end = index + 1
        while end < line.count, !Syntax.isBlank(line[end]) {
            end += 1
        }
        let name = Array(line[(index + 1)..<end])
        // Readers agree on anchor names made of ASCII letters, digits, `-` and `_`; a tag is checked below.
        let isAnchorName = !name.isEmpty && name.allSatisfy(Syntax.isAnchorCharacter)
        guard isAnchorName || line[index] == UInt8(ascii: "!") else { return .broken }

        switch line[index] {
        case UInt8(ascii: "*"):
            // An alias stands alone and must name an anchor defined before it.
            guard anchors.contains(name), tail(of: line, from: end) != nil else { return .broken }
            return .unsupported(acceptsChildren: false)
        case UInt8(ascii: "&"):
            anchors.insert(name)
            switch value(in: line, from: end, allowsList: true, anchors: &anchors) {
            case .broken: return .broken
            case .blockScalar(let indentation): return .blockScalar(indentation: indentation)
            case .scalar(let scalar, _, _) where scalar.raw.isEmpty: return .unsupported(acceptsChildren: true)
            case .unsupported(acceptsChildren: true): return .broken
            case .scalar, .list, .unsupported: return .unsupported(acceptsChildren: false)
            }
        default:
            // Readers resolve tags differently; only `!!str` before a single value is certain.
            guard name == Array("!str".utf8) else { return .broken }
            guard case .scalar(let scalar, _, _) = value(in: line, from: end, allowsList: false, anchors: &anchors),
                !scalar.raw.isEmpty
            else { return .broken }
            return .unsupported(acceptsChildren: false)
        }
    }

    /// What follows a quoted scalar or an inline list, or `nil` when it is anything but blanks
    /// and a comment.
    private static func tail(of line: [UInt8], from start: Int) -> String? {
        let rest = line[start...]
        guard let firstContent = rest.firstIndex(where: { !Syntax.isBlank($0) }) else { return Syntax.string(rest) }
        guard line[firstContent] == Syntax.hash, firstContent > start else { return nil }
        return Syntax.string(rest)
    }
}
