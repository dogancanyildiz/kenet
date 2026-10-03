/// Whether the lines of a version's frontmatter block, comments included, are still in a merged
/// frontmatter block.
///
/// Field values are compared elsewhere, by meaning. This check is about the bytes a value
/// comparison does not see: comment lines, and comments at the end of field lines. A nonblank
/// line of the block survives when the merged block has it verbatim, or when it is a field line
/// without a comment, or when its comment reappears on a line with the same key part.
enum FrontmatterLineSurvival {
    static func linesSurvive(of document: RawDocument, in merged: RawDocument) -> Bool {
        guard case .parsed(let frontmatter) = document.frontmatter else { return true }
        let innerLines = frontmatter.lineRange.dropFirst().dropLast()
        var available: [[UInt8]: Int] = [:]
        if let range = merged.frontmatterLineRange {
            for index in range.dropFirst().dropLast() {
                available[merged.lines[index].content, default: 0] += 1
            }
        }
        var commentedParts = commentedParts(of: merged)
        let partByLine = Dictionary(uniqueKeysWithValues: parts(of: frontmatter).map { ($0.line, $0) })

        for index in innerLines {
            let content = document.lines[index].content
            if MergeBody.isBlank(content) { continue }
            if let count = available[content], count > 0 {
                available[content] = count - 1
                continue
            }
            guard let part = partByLine[index] else { return false }
            guard part.tail.utf8.contains(Syntax.hash) else { continue }
            let key = Key(head: part.head, tail: part.tail)
            guard let count = commentedParts[key], count > 0 else { return false }
            commentedParts[key] = count - 1
        }
        return true
    }

    private struct Key: Hashable {
        let head: [UInt8]
        let tail: [UInt8]

        init(head: String, tail: String) {
            // The indentation of an entry taken from the other version is adjusted, so it is not part of the key.
            self.head = Array(head.utf8.drop(while: Syntax.isBlank))
            self.tail = Array(tail.utf8)
        }
    }

    /// The key lines and item or entry lines of every field, with how each is split around its value.
    private static func parts(of frontmatter: Frontmatter) -> [LinePart] {
        frontmatter.fields.flatMap { [$0.layout.keyPart] + $0.layout.children }
    }

    /// How many lines of the merged block carry each (key part, comment) combination.
    private static func commentedParts(of merged: RawDocument) -> [Key: Int] {
        guard case .parsed(let frontmatter) = merged.frontmatter else { return [:] }
        var counts: [Key: Int] = [:]
        for part in parts(of: frontmatter) where part.tail.utf8.contains(Syntax.hash) {
            counts[Key(head: part.head, tail: part.tail), default: 0] += 1
        }
        return counts
    }
}
