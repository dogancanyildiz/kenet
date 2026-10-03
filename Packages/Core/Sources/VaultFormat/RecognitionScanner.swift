/// Shares the format's code and wikilink exclusions with recognition.
package struct RecognitionScanner {
    private var fences = FenceScanner()

    private let frontmatter: Range<Int>?
    private var line = 0

    package init(document: RawDocument) { frontmatter = document.frontmatterLineRange }

    /// Returns a physical UTF-8 mask for a line, advancing fence state.
    package mutating func excludedBytes(_ bytes: [UInt8], insideFence: Bool = false) -> [Bool] {
        defer { line += 1 }
        if frontmatter?.contains(line) == true { return Array(repeating: true, count: bytes.count) }
        let fenced = fences.consumes(bytes)
        if insideFence || fenced { return Array(repeating: true, count: bytes.count) }
        var excluded = WikiLinkScanner.inlineCode(bytes)
        for link in WikiLinkScanner.scan(bytes) {
            for offset in link.range { excluded[offset] = true }
        }
        for range in MarkdownLinkMask.ranges(bytes, excluding: excluded) {
            for offset in range { excluded[offset] = true }
        }
        return excluded
    }
}
