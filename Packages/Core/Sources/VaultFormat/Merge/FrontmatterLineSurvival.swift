/// Whether the lines of a version's frontmatter block, comments included, are still in a merged
/// frontmatter block.
///
/// Field values are compared elsewhere, by meaning. This check is about the bytes a value
/// comparison does not see: comment lines, and comments at the end of field lines. A nonblank
/// line of the block survives when the merged block has it verbatim, or when it is a field line
/// without a comment, or when its comment reappears on a line of the same field with the same
/// key part (and, for a list item, the same item). Every merged line answers for one line only.
enum FrontmatterLineSurvival {
    static func linesSurvive(of document: RawDocument, in merged: RawDocument) -> Bool {
        guard case .parsed(let frontmatter) = document.frontmatter else { return true }
        var pool = mergedLines(of: merged)
        let partByLine = Dictionary(uniqueKeysWithValues: parts(of: frontmatter).map { ($0.line, $0) })

        for index in frontmatter.lineRange.dropFirst().dropLast() {
            let content = document.lines[index].content
            if MergeBody.isBlank(content) { continue }
            if let found = pool.firstIndex(where: { $0.content == content }) {
                pool.remove(at: found)
                continue
            }
            guard let part = partByLine[index] else { return false }
            guard part.hasComment else { continue }
            guard let found = pool.firstIndex(where: { $0.part?.key == part.key }) else { return false }
            pool.remove(at: found)
        }
        return true
    }

    /// A field line split around its value, with what identifies it for a comment to move onto.
    private struct Part {
        let line: Int
        let fieldKey: String
        let head: String
        /// The item of a list; empty for a key line or a mapping entry, whose value may change.
        let item: String
        let tail: String

        var hasComment: Bool { tail.utf8.contains(Syntax.hash) }

        /// The indentation of an entry taken from the other version is adjusted, so it is not part of the key.
        var key: [[UInt8]] {
            [Array(fieldKey.utf8), Array(head.utf8.drop(while: Syntax.isBlank)), Array(item.utf8), Array(tail.utf8)]
        }
    }

    private struct PooledLine {
        let content: [UInt8]
        let part: Part?
    }

    /// The key lines and item or entry lines of every field.
    private static func parts(of frontmatter: Frontmatter) -> [Part] {
        frontmatter.fields.flatMap { field -> [Part] in
            let keyPart = field.layout.keyPart
            var parts = [
                Part(line: keyPart.line, fieldKey: field.key, head: keyPart.head, item: "", tail: keyPart.tail)
            ]
            let items: [FrontmatterScalar]
            if case .list(let listItems, style: .block) = field.value { items = listItems } else { items = [] }
            for (offset, child) in field.layout.children.enumerated() {
                let item = offset < items.count ? items[offset].raw : ""
                parts.append(
                    Part(line: child.line, fieldKey: field.key, head: child.head, item: item, tail: child.tail))
            }
            return parts
        }
    }

    /// The nonblank lines between the delimiters of the merged block, each with its field part.
    private static func mergedLines(of merged: RawDocument) -> [PooledLine] {
        guard let range = merged.frontmatterLineRange else { return [] }
        var partByLine: [Int: Part] = [:]
        if case .parsed(let frontmatter) = merged.frontmatter {
            partByLine = Dictionary(uniqueKeysWithValues: parts(of: frontmatter).map { ($0.line, $0) })
        }
        return range.dropFirst().dropLast().compactMap { index in
            let content = merged.lines[index].content
            return MergeBody.isBlank(content) ? nil : PooledLine(content: content, part: partByLine[index])
        }
    }
}
