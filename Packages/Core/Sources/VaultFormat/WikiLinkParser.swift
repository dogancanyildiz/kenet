/// Shares existing frontmatter layouts and fence recognition.
enum WikiLinkParser {
    static func parse(_ document: RawDocument) -> [WikiLink] {
        var result: [WikiLink] = []
        if case .parsed(let frontmatter) = document.frontmatter {
            for field in frontmatter.fields {
                result += FrontmatterLinks.parse(field, lines: document.lines)
            }
        }
        var fence = FenceScanner()
        let start = document.frontmatterLineRange?.upperBound ?? 0
        for line in start..<document.lines.count {
            let bytes = document.lines[line].content
            guard !fence.consumes(bytes), document.lines[line].text != nil else { continue }
            for match in WikiLinkScanner.scan(bytes) {
                result.append(
                    WikiLink(
                        line: line, byteRange: match.range, targetRange: match.targetRange,
                        target: match.target, rawTarget: Syntax.string(bytes[match.targetRange]),
                        anchor: match.anchor, displayText: match.display, isEmbedded: match.embedded, source: .body))
            }
        }
        return result
    }
}
