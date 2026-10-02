/// A replacement of a range of lines, used to apply several changes to one document.
struct LineEdit: Hashable, Sendable {
    /// The lines to replace. An empty range inserts before the line at its lower bound.
    let range: Range<Int>
    /// The contents of the lines that take their place, without line endings.
    let contents: [String]

    /// An insertion may preserve a separating blank after CR without merging it into CRLF.
    var firstLineEnding: LineEnding? = nil

    /// Replaces the content of one line.
    static func replacing(line: Int, with content: String) -> LineEdit {
        LineEdit(range: line..<(line + 1), contents: [content])
    }

    /// Removes one line together with its line ending.
    static func removing(line: Int) -> LineEdit {
        LineEdit(range: line..<(line + 1), contents: [])
    }

    /// Inserts lines before the line at the given index, or at the end of the document.
    static func inserting(_ contents: [String], at line: Int) -> LineEdit {
        LineEdit(range: line..<line, contents: contents)
    }
}

extension RawDocument {
    /// Returns a document in which the lines in `range` are replaced by lines with the given contents.
    func replacingLines(in range: Range<Int>, with contents: [String]) throws(EditError) -> RawDocument {
        try applying([LineEdit(range: range, contents: contents)])
    }

    /// Returns a document with the edits applied. Their ranges refer to this document's lines
    /// and must not overlap; an insertion at the lower bound of a replaced range lands before
    /// the replaced lines.
    ///
    /// This is the only way a document changes. Lines outside the ranges keep their bytes, and
    /// the result is always what reading its serialized bytes would produce:
    /// - A replacement line takes over the line ending of the line at the same position in its
    ///   range, so rewriting a line changes its content only. Lines beyond the replaced ones end
    ///   with `lineEndingForNewLines`.
    /// - An unterminated last line is terminated before lines are added after it. A replacement
    ///   of that line stays unterminated only while it is still the last line and has content.
    /// - A line ending in CR that comes to stand before an empty line ending in LF forms one
    ///   CRLF ending with it, because those two bytes cannot be told apart from CRLF in a file.
    ///   This is decided once, on the final lines, so no byte of an untouched line is dropped.
    /// - The byte order mark stays in front. A document without one whose first line would start
    ///   with those three bytes is a document with a byte order mark.
    func applying(_ edits: [LineEdit]) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        let ordered = edits.enumerated().sorted { first, second in
            if first.element.range.lowerBound != second.element.range.lowerBound {
                return first.element.range.lowerBound < second.element.range.lowerBound
            }
            if first.element.range.isEmpty != second.element.range.isEmpty { return first.element.range.isEmpty }
            return first.offset < second.offset
        }.map(\.element)

        var covered = 0
        for edit in ordered {
            guard edit.range.lowerBound >= covered, edit.range.upperBound <= lines.count else {
                throw .invalidLineRange
            }
            covered = edit.range.upperBound
            for content in edit.contents {
                let bytes = content.utf8
                guard !bytes.contains(LineEnding.lineFeed), !bytes.contains(LineEnding.carriageReturn) else {
                    throw .lineBreakInContent
                }
            }
        }

        let newLineEnding = lineEndingForNewLines
        var assembled: [RawLine] = []
        var next = 0
        for edit in ordered {
            assembled.append(contentsOf: lines[next..<edit.range.lowerBound])
            for (offset, content) in edit.contents.enumerated() {
                let ending =
                    offset == 0 && edit.firstLineEnding != nil
                    ? edit.firstLineEnding
                    : (offset < edit.range.count ? lines[edit.range.lowerBound + offset].ending : newLineEnding)
                assembled.append(RawLine(content: Array(content.utf8), ending: ending))
            }
            next = edit.range.upperBound
        }
        assembled.append(contentsOf: lines[next...])

        var result: [RawLine] = []
        for (index, line) in assembled.enumerated() {
            // A line without an ending must be the last line and must have content.
            let needsEnding = line.ending == nil && (index < assembled.count - 1 || line.content.isEmpty)
            let ending = needsEnding ? newLineEnding : line.ending
            if let previous = result.last, previous.ending == .cr, ending == .lf, line.content.isEmpty {
                result[result.count - 1] = RawLine(content: previous.content, ending: .crlf)
            } else {
                result.append(RawLine(content: line.content, ending: ending))
            }
        }

        var hasByteOrderMark = hasByteOrderMark
        if !hasByteOrderMark, let first = result.first, first.content.starts(with: Self.byteOrderMark) {
            hasByteOrderMark = true
            let content = Array(first.content.dropFirst(Self.byteOrderMark.count))
            if content.isEmpty, first.ending == nil {
                result.removeFirst()
            } else {
                result[0] = RawLine(content: content, ending: first.ending)
            }
        }

        return RawDocument(hasByteOrderMark: hasByteOrderMark, lines: result)
    }
}
