/// A read-only wikilink with physical source positions.
public struct WikiLink: Hashable, Sendable {
    /// The zero-based physical line index.
    public let line: Int
    /// Zero-based, half-open UTF-8 byte offsets, excluding an embedding exclamation mark.
    public let byteRange: Range<Int>
    /// The target spelling including its extension, excluding outer whitespace and separator escapes.
    public let targetRange: Range<Int>
    /// The decoded target with surrounding whitespace and a trailing `.md` removed.
    public let target: String
    /// The exact source bytes of the target, decoded as UTF-8, including YAML escapes.
    public let rawTarget: String
    /// A heading or block anchor, without the separating hash.
    public let anchor: WikiLinkAnchor?
    /// Everything after the first pipe, or nil when no pipe occurs.
    public let displayText: String?
    /// Whether an unescaped exclamation mark immediately precedes the opening brackets.
    public let isEmbedded: Bool
    /// Whether the target is empty and the anchor refers to the current file.
    public var isSameFile: Bool { target.isEmpty }
    /// Whether the target contains a vault-relative path separator.
    public var isPath: Bool { target.contains("/") }
    /// The body or the top-level frontmatter key and optional mapping entry key.
    public let source: WikiLinkSource
}

/// The meaning of a wikilink anchor; spelling is preserved without trimming.
public enum WikiLinkAnchor: Hashable, Sendable {
    /// A heading title.
    case heading(String)
    /// A block identifier without its leading caret.
    case block(String)
}

/// Where a wikilink's text was read.
public enum WikiLinkSource: Hashable, Sendable {
    /// A document body line.
    case body
    /// A decoded frontmatter value, optionally in a mapping entry.
    case frontmatter(key: String, entry: String?)
}

extension RawDocument {
    /// Extracts wikilinks in source order without resolving targets or changing bytes.
    public var links: [WikiLink] { WikiLinkParser.parse(self) }
}
