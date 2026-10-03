/// The physical position of a spelling, excluding an at sign and apostrophe suffix.
public struct MentionPosition: Hashable, Sendable {
    /// The zero-based physical line number, excluding a leading BOM.
    public let line: Int
    /// The half-open UTF-8 range within that line's content.
    public let byteRange: Range<Int>

    /// Creates a position suitable for a user's candidate selection.
    public init(line: Int, byteRange: Range<Int>) {
        self.line = line
        self.byteRange = byteRange
    }
}

/// A recognized name with all distinct candidate entities in ranking order.
public struct Mention: Equatable, Sendable {
    /// The original source location.
    public let position: MentionPosition
    /// The zero-based physical line number.
    public var line: Int { position.line }
    /// The half-open UTF-8 byte range within the line.
    public var byteRange: Range<Int> { position.byteRange }
    /// The original source spelling, preserving its bytes.
    public let spelling: String
    /// Ranked candidates; ranking never changes certainty.
    public let candidates: [KnownEntity]
    /// Whether one candidate can be linked without a user choice.
    public var isCertain: Bool { candidates.count == 1 && (!isCaseMismatch || isExplicit) }
    /// Whether more than one candidate matches.
    public var isAmbiguous: Bool { candidates.count > 1 }
    /// Whether the initial letter differs in case from every matching name or alias.
    public let isCaseMismatch: Bool
    /// Whether an at sign immediately precedes this spelling.
    public let isExplicit: Bool
    /// Whether the spelling was selected as an alias rather than a name.
    public let isAlias: Bool
}

/// An uppercase explicit mention that matched no known entity.
public struct UnknownMention: Equatable, Sendable {
    /// The source position, excluding the at sign and suffix.
    public let position: MentionPosition
    /// The original spelling for a possible new entity.
    public let spelling: String
}
