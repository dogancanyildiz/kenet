/// The three named sections, in their creation order.
public enum DaySectionKind: String, CaseIterable, Hashable, Sendable {
    /// Tasks recorded for the day.
    case tasks = "Tasks"
    /// Events recorded for the day.
    case events = "Events"
    /// Free journal text.
    case journal = "Journal"
}

/// A heading and the lines it owns, including its heading (zero-based, half-open).
public struct DaySection: Hashable, Sendable {
    /// The recognized name, or nil for an unknown or duplicate heading.
    public let kind: DaySectionKind?
    /// The heading's zero-based line index.
    public let headingLine: Int
    /// The ATX heading level.
    public let level: Int
    /// The heading and its contents, including trailing blank lines.
    public let lineRange: Range<Int>
}

/// A partition of the body into preamble and sections in file order.
public struct DaySections: Hashable, Sendable {
    /// Lines before the first body heading; may be empty.
    public let preambleRange: Range<Int>
    /// Recognized and unknown sections in file order.
    public let sections: [DaySection]

    /// The first section with this name.
    public func section(_ kind: DaySectionKind) -> DaySection? {
        sections.first { $0.kind == kind }
    }
}

extension RawDocument {
    /// The frontmatter's occupied lines, even when its contents cannot be read.
    /// Ambiguous delimiters reserve the block through the first closing candidate, or EOF.
    public var frontmatterLineRange: Range<Int>? {
        switch frontmatter {
        case .absent: return nil
        case .parsed(let block): return block.lineRange
        case .unreadable:
            let closing = lines.indices.dropFirst().first {
                lines[$0].content == Syntax.delimiter || FrontmatterParser.isDelimiterLookalike(lines[$0].content)
            }
            return 0..<(closing.map { $0 + 1 } ?? lines.count)
        }
    }

    /// Reads the body headings without changing any bytes.
    public var daySections: DaySections {
        SectionParser.parse(lines, startingAt: frontmatterLineRange?.upperBound ?? 0)
    }
}

/// An ATX body heading outside code fences, including headings nested within sections.
public struct BodyHeading: Hashable, Sendable {
    public let line: Int
    public let level: Int
}

extension RawDocument {
    /// Reads every body heading using the same fence and heading rules as day sections.
    public var bodyHeadings: [BodyHeading] {
        SectionParser.scan(lines, startingAt: frontmatterLineRange?.upperBound ?? 0, includingNested: true)
            .sections.sections.map { BodyHeading(line: $0.headingLine, level: $0.level) }
    }
}
