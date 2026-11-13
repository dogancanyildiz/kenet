extension RawDocument {
    /// The mark put in front of an appended Diary line that would otherwise be read as structure.
    public static let diaryPlainLineMark = "· "

    /// Appends text to Diary one empty line below its last nonblank line, before retained
    /// trailing blanks and any later section. No existing byte changes.
    ///
    /// The contents are text, never structure. Each string is split at line breaks, leading spaces
    /// and tabs are dropped, and blank lines around the block are dropped. A line that would be read
    /// as a task, a first or second level heading or a code fence gets `diaryPlainLineMark` in
    /// front, so nothing is lost and no record appears. Blank contents return the document unchanged.
    /// The append is refused when a task or event would still read differently afterwards.
    public func appendingDiaryLines(_ contents: [String]) throws(EditError) -> RawDocument {
        let block = Self.diaryAppendBlock(contents)
        guard !block.isEmpty else { return self }
        guard !isReadOnly else { throw .readOnlyDocument }
        return try appendingDiaryBlock(block)
    }

    /// Writes prepared lines, refusing a block that would add a record or change an existing one.
    func appendingDiaryBlock(_ block: [String]) throws(EditError) -> RawDocument {
        let result = try appendingLines([""] + block, toSection: .diary)
        guard result.recordContents == recordContents else { throw .contentNotRepresentable }
        return result
    }

    /// The lines an append writes below its separating empty line; empty when there is nothing to write.
    static func diaryAppendBlock(_ contents: [String]) -> [String] {
        var block: [String] = []
        for content in contents {
            for piece in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                // Indentation would make the line a continuation of a task above it, or code.
                var line = String.UnicodeScalarView(piece.unicodeScalars.drop { $0 == " " || $0 == "\t" })
                if isDiaryStructure(Array(String(line).utf8)) {
                    line.insert(contentsOf: diaryPlainLineMark.unicodeScalars, at: line.startIndex)
                }
                block.append(String(line))
            }
        }
        let isBlank = { (line: String) in line.allSatisfy(\.isWhitespace) }
        return Array(block.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    private static func isDiaryStructure(_ bytes: [UInt8]) -> Bool {
        if BodyLineParser.task(bytes) != nil { return true }
        if let level = SectionParser.headingLevel(bytes), level <= 2 { return true }
        guard let first = bytes.first, first == 0x60 || first == 0x7E else { return false }
        return bytes.prefix { $0 == first }.count >= 3
    }

    /// The lines of every task and event, which an append must leave as they were.
    private var recordContents: [[[[UInt8]]]] {
        let body = bodyLines
        return [body.tasks.map(\.block), body.events.map(\.block)].map { blocks in
            blocks.map { lines[$0.lineRange].map(\.content) }
        }
    }

    /// The bytes after the Diary heading up to the next section, as the editor shows them;
    /// empty without a section. A writer compares it with what its caller read.
    public func diaryText() throws(EditError) -> String {
        guard !isReadOnly else { throw .readOnlyDocument }
        guard let section = daySections.section(.diary) else { return "" }
        let bytes = lines[(section.headingLine + 1)..<section.lineRange.upperBound].flatMap(\.bytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Replaces Diary content while preserving its heading and trailing blank lines.
    /// Empty text leaves a missing section unchanged.
    public func replacingDiary(with text: String) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        let contents = Array(
            RawDocument(bytes: [10] + text.utf8).lines.dropFirst()
                .reversed().drop(while: { $0.content.allSatisfy(Syntax.isBlank) }).reversed()
        ).map { $0.text! }
        let existing = daySections.section(.diary)
        if existing == nil, text.allSatisfy(\.isWhitespace) { return self }
        let base: RawDocument
        var replaced: ArraySlice<RawLine> = []
        if let existing {
            let end = existing.lineRange.last { !lines[$0].content.allSatisfy(Syntax.isBlank) }! + 1
            replaced = lines[(existing.headingLine + 1)..<end]
            base = try replacingLines(in: (existing.headingLine + 1)..<end, with: [])
        } else {
            base = self
        }
        // The sentinel permits empty replacement text without relaxing append validation.
        let inserted = try base.appendingLines(["Diary"] + contents, toSection: .diary)
        let section = inserted.daySections.section(.diary)!
        let start = section.headingLine + 1
        // Keep a leading empty line from coalescing with a preceding CR into CRLF.
        let firstEnding: LineEnding? =
            inserted.lines[section.headingLine].ending == .cr && contents.first == "" ? .cr : nil
        let written = try inserted.applying([
            LineEdit(range: start..<(start + 1 + contents.count), contents: contents, firstLineEnding: firstEnding)
        ])
        return written.keepingEndings(of: Array(replaced), forLinesFrom: start, count: contents.count)
    }

    /// Gives each unchanged line of a rewritten range the ending it had before. Old and new lines
    /// pair by content in order (the longest common subsequence); new and changed lines keep the
    /// ending the rewrite gave them. An old CR ending is not kept where it would stand before an
    /// empty LF line, nor an old LF ending of an empty line after a CR: the two would read as one
    /// CRLF line and a blank line would be lost.
    private func keepingEndings(of old: [RawLine], forLinesFrom start: Int, count: Int) -> RawDocument {
        guard !old.isEmpty, count > 0 else { return self }
        let new = lines[start..<(start + count)].map(\.content)
        let difference = new.difference(from: old.map(\.content))
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let keptOld = old.indices.filter { !removed.contains($0) }
        let keptNew = (0..<count).filter { !inserted.contains($0) }
        var result = lines
        for (oldOffset, newOffset) in zip(keptOld, keptNew) {
            let index = start + newOffset
            guard let ending = old[oldOffset].ending, let current = result[index].ending, ending != current else {
                continue
            }
            let line = result[index]
            if ending == .cr, index + 1 < result.count, result[index + 1].content.isEmpty,
                result[index + 1].ending == .lf
            {
                continue
            }
            if ending == .lf, line.content.isEmpty, index > 0, result[index - 1].ending == .cr { continue }
            result[index] = RawLine(content: line.content, ending: ending)
        }
        return RawDocument(hasByteOrderMark: hasByteOrderMark, lines: result)
    }
}
