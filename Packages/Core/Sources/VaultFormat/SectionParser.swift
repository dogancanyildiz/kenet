/// Scans ATX headings while tracking fenced code blocks.
enum SectionParser {
    static func parse(_ lines: [RawLine], startingAt start: Int) -> DaySections {
        scan(lines, startingAt: start).sections
    }

    static func scan(_ lines: [RawLine], startingAt start: Int) -> (sections: DaySections, fencedBoundaries: Set<Int>) {
        var fencedBoundaries: Set<Int> = []
        var headings: [(line: Int, level: Int, kind: DaySectionKind?)] = []
        var seen: Set<DaySectionKind> = []
        var fence: (byte: UInt8, count: Int)?
        for index in start..<lines.count {
            let bytes = lines[index].content
            let indent = bytes.prefix { $0 == Syntax.space }.count
            if fence != nil { fencedBoundaries.insert(index) }
            guard indent <= 3 else { continue }
            let text = Array(bytes.dropFirst(indent))
            if let open = fence {
                let run = text.prefix { $0 == open.byte }.count
                if run >= open.count, text.dropFirst(run).allSatisfy(Syntax.isBlank) { fence = nil }
                continue
            }
            if let marker = text.first, marker == 0x60 || marker == 0x7E {
                let count = text.prefix { $0 == marker }.count
                if count >= 3 {
                    fence = (marker, count)
                    continue
                }
            }
            let level = text.prefix { $0 == Syntax.hash }.count
            guard (1...6).contains(level), text.count == level || Syntax.isBlank(text[level]) else { continue }
            // Deeper headings belong to the current section, rather than splitting it.
            if let active = headings.last, level > 2, level > active.level { continue }
            let trimmed = bytes.reversed().drop(while: Syntax.isBlank).reversed()
            let candidate = DaySectionKind.allCases.first { trimmed.elementsEqual(("## " + $0.rawValue).utf8) }
            let kind = candidate.flatMap { seen.insert($0).inserted ? $0 : nil }
            headings.append((index, level, kind))
        }
        // A boundary records the state before a line, including the boundary at EOF.
        if fence != nil { fencedBoundaries.insert(lines.count) }
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
}
