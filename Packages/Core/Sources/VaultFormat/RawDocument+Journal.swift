extension RawDocument {
    /// Replaces Journal content while preserving its heading and trailing blank lines.
    /// Empty text leaves a missing section unchanged.
    public func replacingJournal(with text: String) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        let contents = RawDocument(bytes: [10] + text.utf8).lines.dropFirst().map { $0.text! }
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
