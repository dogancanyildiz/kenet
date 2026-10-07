/// Scans ATX headings while tracking fenced code blocks.
enum SectionParser {
    static func parse(_ lines: [RawLine], startingAt start: Int) -> DaySections {
        scan(lines, startingAt: start).sections
    }

    static func scan(_ lines: [RawLine], startingAt start: Int, includingNested: Bool = false) -> (
        sections: DaySections, fencedBoundaries: Set<Int>
    ) {
        var fencedBoundaries: Set<Int> = []
        var headings: [(line: Int, level: Int, kind: DaySectionKind?)] = []
        var seen: Set<DaySectionKind> = []
        var fence = FenceScanner()
        for index in start..<lines.count {
            let bytes = lines[index].content
            if fence.isOpen { fencedBoundaries.insert(index) }
            if fence.consumes(bytes) { continue }
            guard let level = headingLevel(bytes) else { continue }
            // Deeper headings belong to the current section, rather than splitting it.
            if !includingNested, let active = headings.last, level > 2, level > active.level { continue }
            let candidate = DaySectionKind.allCases.first {
                trimmedHeading(bytes).elementsEqual(("## " + $0.rawValue).utf8)
            }
            let kind = candidate.flatMap { seen.insert($0).inserted ? $0 : nil }
            headings.append((index, level, kind))
        }
        // A boundary records the state before a line, including the boundary at EOF.
        if fence.isOpen { fencedBoundaries.insert(lines.count) }
        let sections = headings.enumerated().map { offset, heading in
            let end = offset + 1 < headings.count ? headings[offset + 1].line : lines.count
            return DaySection(
                kind: heading.kind, headingLine: heading.line, level: heading.level,
                lineRange: heading.line..<end)
        }
        return (
            DaySections(preambleRange: start..<(headings.first?.line ?? lines.count), sections: sections),
            fencedBoundaries
        )
    }

    /// The level of an ATX heading line outside a fence: at most three spaces, one to six `#`,
    /// then a blank or the end of the line. `nil` for any other line.
    static func headingLevel(_ bytes: [UInt8]) -> Int? {
        let indent = bytes.prefix(while: Syntax.isBlank).count
        guard indent <= 3, !bytes.prefix(indent).contains(Syntax.tab) else { return nil }
        let text = bytes.dropFirst(indent)
        let level = text.prefix { $0 == Syntax.hash }.count
        guard (1...6).contains(level), text.count == level || Syntax.isBlank(text[text.startIndex + level]) else {
            return nil
        }
        return level
    }

    /// The heading line without its trailing blanks, which is how headings are compared.
    static func trimmedHeading(_ bytes: [UInt8]) -> [UInt8] {
        Array(bytes.reversed().drop(while: Syntax.isBlank).reversed())
    }
}
