/// Reads the frontmatter block of a document into fields that know their lines.
///
/// The parser understands a small YAML subset and is deliberately not a YAML parser. It reads
/// a block only when it is sure every YAML reader would read it the same way:
/// - A structure in the subset becomes a value.
/// - Valid YAML outside the subset becomes a raw field, which is kept and never changed.
/// - Anything else (YAML that a reader rejects, or that readers are known to disagree on)
///   makes the whole block unreadable.
enum FrontmatterParser {
    static func parse(_ lines: [RawLine]) -> FrontmatterState {
        guard let opening = lines.first else { return .absent }
        guard opening.content == Syntax.delimiter else {
            return isDelimiterLookalike(opening.content) ? .unreadable : .absent
        }
        var closing: Int?
        for index in lines.indices.dropFirst() {
            if lines[index].content == Syntax.delimiter {
                closing = index
                break
            }
            if isDelimiterLookalike(lines[index].content) { return .unreadable }
        }
        guard let closing else { return .absent }
        guard let fields = fields(in: lines, body: 1..<closing) else { return .unreadable }
        return .parsed(Frontmatter(lineRange: 0..<(closing + 1), fields: fields))
    }

    /// Whether the line is `---` followed by blanks. Readers disagree on whether that is a
    /// delimiter, so a block that depends on the answer is not trusted.
    private static func isDelimiterLookalike(_ content: [UInt8]) -> Bool {
        content.count > Syntax.delimiter.count && content.starts(with: Syntax.delimiter)
            && content.dropFirst(Syntax.delimiter.count).allSatisfy(Syntax.isBlank)
    }

    /// Whether the line starts with `---` or `...` followed by a blank or nothing, which starts
    /// or ends a YAML document. A frontmatter block holds exactly one document.
    private static func isDocumentMarker(_ content: [UInt8]) -> Bool {
        let startsWithMarker = content.starts(with: Syntax.delimiter) || content.starts(with: Array("...".utf8))
        return startsWithMarker && (content.count == 3 || Syntax.isBlank(content[3]))
    }

    /// A field whose key line has been read and whose following lines are still being collected.
    private struct OpenField {
        let keyLine: Int
        let key: String
        let colon: Int
        let value: ScannedValue
        /// The lines after the key line that belong to the field and are not blank or comments.
        var contentLines: [Int] = []
        /// Whether a comment line has been seen since the last line of the field.
        var hasPendingComment = false
        /// Whether a comment line stands before a line of the field.
        var hasInnerComment = false
        /// Whether a blank line made of spaces has been seen since the last line of the field.
        var hasPendingSpaces = false
        /// Whether a blank line made of spaces stands before a line of the field.
        var hasInnerSpaces = false
        /// The longest blank line before the first line of the field.
        var leadingBlankWidth = 0

        var isBlockScalar: Bool {
            if case .blockScalar = value { return true }
            return false
        }

        /// Whether nothing follows the key on its line, so that items or entries may follow below.
        var hasNoValue: Bool {
            if case .scalar(let scalar, _, _) = value { return scalar.raw.isEmpty }
            return false
        }

        mutating func noteBlankLine(width: Int) {
            if width > 0 { hasPendingSpaces = true }
            if contentLines.isEmpty { leadingBlankWidth = max(leadingBlankWidth, width) }
        }

        mutating func append(_ line: Int) {
            contentLines.append(line)
            hasInnerComment = hasInnerComment || hasPendingComment
            hasInnerSpaces = hasInnerSpaces || hasPendingSpaces
            hasPendingComment = false
            hasPendingSpaces = false
        }
    }

    /// The fields in the lines between the delimiters, or `nil` when the block is unreadable.
    private static func fields(in lines: [RawLine], body: Range<Int>) -> [FrontmatterField]? {
        var fields: [FrontmatterField] = []
        var keys: Set<[UInt8]> = []
        var anchors: Set<[UInt8]> = []
        var open: OpenField?

        func close(_ finished: OpenField?) -> Bool {
            guard let finished else { return true }
            // A key that occurs twice is rejected by readers. `<<` merges another mapping into
            // this one, and some readers do that even when the key is quoted.
            let key = Array(finished.key.utf8)
            guard key != Syntax.mergeKey, keys.insert(key).inserted else { return false }
            guard let field = field(from: finished, lines: lines, anchors: &anchors) else { return false }
            fields.append(field)
            return true
        }

        for index in body {
            let line = lines[index].content
            guard StrictUTF8.decode(line) != nil, !Syntax.containsUnreadableCharacter(line) else { return nil }
            guard let contentStart = line.firstIndex(where: { !Syntax.isBlank($0) }) else {
                // A blank line may hold spaces; readers do not agree on one that holds a tab.
                guard !line.contains(Syntax.tab) else { return nil }
                open?.noteBlankLine(width: line.count)
                continue
            }
            let indentation = line.prefix { $0 == Syntax.space }.count
            let isInBlockScalar = indentation > 0 && open?.isBlockScalar == true
            // Inside a block scalar an indented `#` line is text, not a comment.
            if line[contentStart] == Syntax.hash, !isInBlockScalar {
                // Like a blank line, a comment may be indented with spaces but not with a tab.
                guard contentStart == indentation else { return nil }
                open?.hasPendingComment = true
                continue
            }
            // A tab cannot indent; after the indentation of a block scalar it is text.
            guard contentStart == indentation || isInBlockScalar else { return nil }

            if indentation > 0 {
                guard open != nil else { return nil }
                open?.append(index)
            } else if FrontmatterLineScanner.isListItem(line, at: 0) {
                // A block list may sit at the indentation of its key.
                guard open?.hasNoValue == true else { return nil }
                open?.append(index)
            } else {
                guard close(open), !isDocumentMarker(line) else { return nil }
                guard case .key(let key, let colon) = FrontmatterLineScanner.key(in: line, from: 0) else { return nil }
                let value = FrontmatterLineScanner.value(in: line, from: colon + 1, allowsList: true, anchors: &anchors)
                if case .broken = value { return nil }
                open = OpenField(keyLine: index, key: key, colon: colon, value: value)
            }
        }
        return close(open) ? fields : nil
    }

    /// The finished field, or `nil` when its lines make the block unreadable.
    private static func field(
        from open: OpenField,
        lines: [RawLine],
        anchors: inout Set<[UInt8]>
    ) -> FrontmatterField? {
        let keyLine = lines[open.keyLine].content
        let head = Syntax.string(keyLine[...open.colon])
        let lineRange = open.keyLine..<((open.contentLines.last ?? open.keyLine) + 1)
        let contents = open.contentLines.map { lines[$0].content }

        func make(_ value: FrontmatterValue, gap: String, tail: String, children: Children? = nil) -> FrontmatterField {
            let keyPart = LinePart(line: open.keyLine, head: head, gap: gap, tail: tail)
            let layout = FieldLayout(
                keyPart: keyPart,
                children: children?.parts ?? [],
                childIndent: children?.indent ?? ""
            )
            return FrontmatterField(key: open.key, lineRange: lineRange, value: value, layout: layout)
        }
        func raw() -> FrontmatterField {
            var text = [Array(keyLine[(open.colon + 1)...].drop(while: Syntax.isBlank))]
            text += lines[lineRange].dropFirst().map(\.content)
            return make(.raw(Syntax.string(text.joined(separator: [LineEnding.lineFeed]))), gap: "", tail: "")
        }

        switch open.value {
        case .scalar(let scalar, let gap, let tail):
            if contents.isEmpty { return make(.scalar(scalar), gap: gap, tail: tail) }
            guard open.hasNoValue else {
                return continuesPlainText(open, scalar: scalar, tail: tail, contents: contents) ? raw() : nil
            }
            guard isValidBlock(open, contents: contents, anchors: &anchors) else { return nil }
            switch children(of: open, lines: lines) {
            case .list(let items, let children):
                return make(.list(items, style: .block), gap: gap, tail: tail, children: children)
            case .mapping(let entries, let children):
                return make(.mapping(entries), gap: gap, tail: tail, children: children)
            case .unsupported:
                return raw()
            }
        case .list(let items, let gap, let tail):
            return contents.isEmpty ? make(.list(items, style: .inline), gap: gap, tail: tail) : nil
        case .blockScalar(let indentation):
            return isValidBlockScalar(open, indentation: indentation, contents: contents) ? raw() : nil
        case .unsupported(let acceptsChildren):
            if contents.isEmpty { return raw() }
            return acceptsChildren && isValidBlock(open, contents: contents, anchors: &anchors) ? raw() : nil
        case .broken:
            return nil
        }
    }

    /// Whether the lines below a key are block YAML every reader accepts. A block scalar deeper
    /// inside is only trusted when no comment or space-only line could be part of its text.
    private static func isValidBlock(_ open: OpenField, contents: [[UInt8]], anchors: inout Set<[UInt8]>) -> Bool {
        var holdsBlockScalar = false
        guard BlockValidator.isValid(contents, anchors: &anchors, holdsBlockScalar: &holdsBlockScalar) else {
            return false
        }
        return !(holdsBlockScalar && (open.hasInnerComment || open.hasInnerSpaces))
    }

    /// Whether the indented lines below a block scalar header are its text and nothing else:
    /// no line is indented less than the first one (or than the header says), and no comment
    /// at the start of a line cuts the text in two.
    private static func isValidBlockScalar(_ open: OpenField, indentation: Int?, contents: [[UInt8]]) -> Bool {
        let widths = contents.map { $0.prefix { $0 == Syntax.space }.count }
        guard !open.hasInnerComment, let first = widths.first else { return !open.hasInnerComment }
        let required = indentation ?? first
        return widths.allSatisfy { $0 >= required } && (indentation != nil || open.leadingBlankWidth <= first)
    }

    /// Whether the lines below an unquoted value only continue its text. Lines that could be
    /// read as structure (an item, a key, a comment) are not accepted as continuation.
    private static func continuesPlainText(
        _ open: OpenField,
        scalar: FrontmatterScalar,
        tail: String,
        contents: [[UInt8]]
    ) -> Bool {
        let isQuoted = scalar.raw.utf8.first == Syntax.doubleQuote || scalar.raw.utf8.first == Syntax.singleQuote
        guard !isQuoted, !tail.utf8.contains(Syntax.hash), !open.hasInnerComment else { return false }
        return contents.allSatisfy { line in
            let start = line.prefix { $0 == Syntax.space }.count
            let first = line[start]
            guard !Syntax.indicators.contains(first), first != Syntax.dash, first != Syntax.questionMark,
                first != Syntax.colon
            else { return false }
            return !PlainScalar.containsMappingIndicator(line) && !PlainScalar.containsComment(line)
        }
    }

    private struct Children {
        var parts: [LinePart] = []
        var indent = ""
    }

    private enum ScannedChildren {
        case list([FrontmatterScalar], Children)
        case mapping([FrontmatterEntry], Children)
        case unsupported
    }

    /// Reads lines already known to be valid YAML as a block list or a one-level mapping: every
    /// line sits at the same indentation and holds one single value. Anything else is valid but
    /// outside the subset.
    private static func children(of open: OpenField, lines: [RawLine]) -> ScannedChildren {
        let first = lines[open.contentLines[0]].content
        let indent = first.prefix { $0 == Syntax.space }.count
        let isList = FrontmatterLineScanner.isListItem(first, at: indent)
        var children = Children(indent: String(repeating: " ", count: indent))
        var items: [FrontmatterScalar] = []
        var entries: [FrontmatterEntry] = []
        var anchors: Set<[UInt8]> = []

        for index in open.contentLines {
            let line = lines[index].content
            guard line.prefix(while: { $0 == Syntax.space }).count == indent else { return .unsupported }
            let valueStart: Int
            var key = ""
            if isList {
                guard FrontmatterLineScanner.isListItem(line, at: indent) else { return .unsupported }
                valueStart = indent + 1
            } else {
                guard case .key(let scannedKey, let colon) = FrontmatterLineScanner.key(in: line, from: indent) else {
                    return .unsupported
                }
                key = scannedKey
                valueStart = colon + 1
            }
            let value = FrontmatterLineScanner.value(in: line, from: valueStart, allowsList: false, anchors: &anchors)
            guard case .scalar(let scalar, let gap, let tail) = value else { return .unsupported }
            let head = Syntax.string(line[..<valueStart])
            children.parts.append(LinePart(line: index, head: head, gap: gap, tail: tail))
            if isList {
                items.append(scalar)
            } else {
                entries.append(FrontmatterEntry(key: key, line: index, value: scalar))
            }
        }
        return isList ? .list(items, children) : .mapping(entries, children)
    }
}
