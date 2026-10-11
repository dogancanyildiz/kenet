extension RawDocument {
    /// The mark put in front of an appended Journal line that would otherwise be read as structure.
    public static let journalPlainLineMark = "· "

    /// Appends text to Journal one empty line below its last nonblank line, before retained
    /// trailing blanks and any later section. No existing byte changes.
    ///
    /// The contents are text, never structure. Each string is split at line breaks, leading spaces
    /// and tabs are dropped, and blank lines around the block are dropped. A line that would be read
    /// as a task, a first or second level heading or a code fence gets `journalPlainLineMark` in
    /// front, so nothing is lost and no record appears. Blank contents return the document unchanged.
    /// The append is refused when a task or event would still read differently afterwards.
    public func appendingJournalLines(_ contents: [String]) throws(EditError) -> RawDocument {
        let block = Self.journalAppendBlock(contents)
        guard !block.isEmpty else { return self }
        guard !isReadOnly else { throw .readOnlyDocument }
        return try appendingJournalBlock(block)
    }

    /// Writes prepared lines, refusing a block that would add a record or change an existing one.
    func appendingJournalBlock(_ block: [String]) throws(EditError) -> RawDocument {
        let result = try appendingLines([""] + block, toSection: .journal)
        guard result.recordContents == recordContents else { throw .contentNotRepresentable }
        return result
    }

    /// The lines an append writes below its separating empty line; empty when there is nothing to write.
    static func journalAppendBlock(_ contents: [String]) -> [String] {
        var block: [String] = []
        for content in contents {
            for piece in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                // Indentation would make the line a continuation of a task above it, or code.
                var line = String.UnicodeScalarView(piece.unicodeScalars.drop { $0 == " " || $0 == "\t" })
                if isJournalStructure(Array(String(line).utf8)) {
                    line.insert(contentsOf: journalPlainLineMark.unicodeScalars, at: line.startIndex)
                }
                block.append(String(line))
            }
        }
        let isBlank = { (line: String) in line.allSatisfy(\.isWhitespace) }
        return Array(block.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    private static func isJournalStructure(_ bytes: [UInt8]) -> Bool {
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

    /// Replaces Journal content while preserving its heading and trailing blank lines.
    /// Empty text leaves a missing section unchanged.
    public func replacingJournal(with text: String) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        let contents = Array(
            RawDocument(bytes: [10] + text.utf8).lines.dropFirst()
                .reversed().drop(while: { $0.content.allSatisfy(Syntax.isBlank) }).reversed()
        ).map { $0.text! }
        let existing = daySections.section(.journal)
        if existing == nil, text.allSatisfy(\.isWhitespace) { return self }
        let base: RawDocument
        if let existing {
            let end = existing.lineRange.last { !lines[$0].content.allSatisfy(Syntax.isBlank) }! + 1
            base = try replacingLines(in: (existing.headingLine + 1)..<end, with: [])
        } else {
            base = self
        }
        // The sentinel permits empty replacement text without relaxing append validation.
        let inserted = try base.appendingLines(["Journal"] + contents, toSection: .journal)
        let section = inserted.daySections.section(.journal)!
        let start = section.headingLine + 1
        // Keep a leading empty line from coalescing with a preceding CR into CRLF.
        let firstEnding: LineEnding? =
            inserted.lines[section.headingLine].ending == .cr && contents.first == "" ? .cr : nil
        return try inserted.applying([
            LineEdit(range: start..<(start + 1 + contents.count), contents: contents, firstLineEnding: firstEnding)
        ])
    }
}
