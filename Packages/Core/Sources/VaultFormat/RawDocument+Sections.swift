extension RawDocument {
    /// Appends lines after the section's last nonblank line, creating a missing section in name order.
    public func appendingLines(_ contents: [String], toSection kind: DaySectionKind) throws(EditError) -> RawDocument {
        guard !isReadOnly else { throw .readOnlyDocument }
        guard contents.contains(where: { !$0.utf8.allSatisfy(Syntax.isBlank) }) else { throw .emptySectionAppend }
        let body = daySections
        let position: Int
        var added: [String] = []
        if let section = body.section(kind) {
            let last = section.lineRange.last { !lines[$0].content.allSatisfy(Syntax.isBlank) }!
            position = last + 1
        } else {
            let following = DaySectionKind.allCases.drop { $0 != kind }.dropFirst()
            position = following.lazy.compactMap { body.section($0)?.headingLine }.first ?? lines.count
            if position > 0, !lines[position - 1].content.allSatisfy(Syntax.isBlank) { added.append("") }
            added.append("## " + kind.rawValue)
        }
        let contentStart = position + added.count
        added.append(contentsOf: contents)
        if body.section(kind) == nil, position < lines.count, !added.last!.utf8.allSatisfy(Syntax.isBlank) {
            added.append("")
        }
        let firstEnding: LineEnding? =
            position > 0 && lines[position - 1].ending == .cr && added.first == "" ? .cr : nil
        let edited = try applying([
            LineEdit(range: position..<position, contents: added, firstLineEnding: firstEnding)
        ])
        let result = RawDocument(bytes: edited.serialized())
        guard
            appendIsValid(
                result, kind: kind, position: position, contentRange: contentStart..<(contentStart + contents.count))
        else { throw .sectionNotWritable }
        return result
    }

    /// Check the serialized result, so parser state and physical line ownership agree with a fresh read.
    private func appendIsValid(
        _ result: RawDocument, kind: DaySectionKind, position: Int, contentRange: Range<Int>
    ) -> Bool {
        guard result.frontmatter == frontmatter, result.frontmatterLineRange == frontmatterLineRange else {
            return false
        }
        let scan = SectionParser.scan(result.lines, startingAt: result.frontmatterLineRange?.upperBound ?? 0)
        let originalScan = SectionParser.scan(lines, startingAt: frontmatterLineRange?.upperBound ?? 0)
        guard let target = scan.sections.section(kind),
            !originalScan.fencedBoundaries.contains(position),
            !scan.fencedBoundaries.contains(contentRange.upperBound)
        else { return false }
        for index in contentRange {
            guard target.lineRange.contains(index), index != target.headingLine else { return false }
        }
        let original = originalScan.sections
        let delta = result.lines.count - lines.count
        let retained = scan.sections.sections.filter {
            original.section(kind) != nil || $0.headingLine != target.headingLine
        }
        guard retained.count == original.sections.count else { return false }
        for (before, after) in zip(original.sections, retained) {
            let heading = before.headingLine + (before.headingLine >= position ? delta : 0)
            guard before.kind == after.kind, before.level == after.level, after.headingLine == heading,
                lines[before.headingLine].content == result.lines[heading].content
            else { return false }
            // Existing lines must keep their section, including nested headings and trailing blanks.
            for index in before.lineRange {
                let shifted = index + (index >= position ? delta : 0)
                guard after.lineRange.contains(shifted) else { return false }
            }
        }
        return true
    }
}
