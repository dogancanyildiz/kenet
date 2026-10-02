/// Spells the lines the app writes into a frontmatter block.
enum FrontmatterWriter {
    /// The indentation the app uses for the entries of a mapping it creates.
    static let entryIndent = "  "

    /// How a key is written: as is, or in double quotes when YAML would read it differently.
    /// An empty key and the merge key `<<` cannot be written.
    static func keySpelling(_ key: String) throws(EditError) -> String {
        guard !key.isEmpty, Array(key.utf8) != Syntax.mergeKey else { throw .invalidKey }
        return PlainScalar.isSafe(key, inFlow: false) ? key : QuotedScalar.encode(key)
    }

    /// A `key: value` line with the given indentation.
    static func line(key: String, value: String, indent: String = "") -> String {
        indent + key + ": " + value
    }

    /// An inline list with the given item spellings.
    static func inlineList(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }

    /// The lines of a new frontmatter block around the given field lines.
    static func block(_ fieldLines: [String]) -> [String] {
        [Syntax.string(Syntax.delimiter)] + fieldLines + [Syntax.string(Syntax.delimiter)]
    }

    /// Whether a spelling found outside an inline list can be used inside one unchanged: it
    /// is quoted, or it holds none of the characters an unquoted item must not contain.
    static func isValidInFlow(_ raw: String) -> Bool {
        guard let first = raw.utf8.first else { return false }
        if first == Syntax.doubleQuote || first == Syntax.singleQuote { return true }
        return !raw.utf8.contains(where: PlainScalar.isForbiddenInFlow)
    }
}
