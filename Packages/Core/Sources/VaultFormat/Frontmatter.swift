/// What reading the frontmatter of a document found.
public enum FrontmatterState: Hashable, Sendable {
    /// The file has no frontmatter: it does not start with `---`, or no later `---` line closes it.
    case absent
    /// A frontmatter block is there but is not YAML that every reader reads the same way.
    /// Nothing is read from it and the app does not write to it.
    case unreadable
    /// The frontmatter was read.
    case parsed(Frontmatter)
}

/// The frontmatter block of a document and the lines each of its fields occupies.
public struct Frontmatter: Hashable, Sendable {
    /// The lines of the block, from the opening `---` line through the closing one.
    public let lineRange: Range<Int>

    /// Every top-level key in file order. No key occurs twice.
    public let fields: [FrontmatterField]

    /// The field with the given key. Keys are compared byte for byte, without Unicode normalization.
    public func field(named key: String) -> FrontmatterField? {
        fields.first { Syntax.exactlyEqual($0.key, key) }
    }
}

/// A top-level key of the frontmatter with its value.
public struct FrontmatterField: Hashable, Sendable {
    /// The key, unquoted when it is written in quotes.
    public let key: String

    /// The lines of the field, from its key line through its last line that is neither blank
    /// nor a comment.
    public let lineRange: Range<Int>

    /// The value of the field.
    public let value: FrontmatterValue

    /// Where the parts of the field are in its lines, for rewriting them in place.
    let layout: FieldLayout
}

/// The value of a frontmatter field.
public enum FrontmatterValue: Hashable, Sendable {
    /// A single value on the key line.
    case scalar(FrontmatterScalar)
    /// A list of single values, written on the key line or as one `- item` line each.
    case list([FrontmatterScalar], style: FrontmatterListStyle)
    /// One level of indented `key: value` lines.
    case mapping([FrontmatterEntry])
    /// Valid YAML outside the supported subset, as the text found in the file: what follows the key
    /// on its line, then the remaining lines of the field, joined with LF. It is shown as is and
    /// never changed.
    case raw(String)

    /// The value seen as a list: a single value is a list of one item, an empty value an empty
    /// list. `nil` for a mapping and for raw text.
    public var listItems: [FrontmatterScalar]? {
        switch self {
        case .scalar(let scalar): scalar.kind == .empty ? [] : [scalar]
        case .list(let items, _): items
        case .mapping, .raw: nil
        }
    }
}

/// How a list is written.
public enum FrontmatterListStyle: Hashable, Sendable {
    /// On the key line: `key: [a, b]`.
    case inline
    /// One `- item` line per item below the key line.
    case block
}

/// One `key: value` line of a one-level mapping.
public struct FrontmatterEntry: Hashable, Sendable {
    /// The key, unquoted when it is written in quotes.
    public let key: String

    /// The line the entry is on.
    public let line: Int

    /// The value of the entry.
    public let value: FrontmatterScalar
}

extension RawDocument {
    /// The frontmatter of the document, read from its lines.
    public var frontmatter: FrontmatterState {
        FrontmatterParser.parse(lines)
    }
}
