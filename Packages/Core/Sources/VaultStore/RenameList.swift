import Foundation
import VaultFormat

/// Uses the YAML list writer to encode changed values, then splices only their source tokens.
/// This preserves inline spacing and untouched empty/number spellings as well as block comments.
enum RenameList {
    static func rewrite(_ document: RawDocument, key: String, items: [FrontmatterScalar], targets: RenameTargets) throws
        -> RawDocument
    {
        let links = document.links.filter {
            guard case .frontmatter(let source, nil) = $0.source else { return false }
            return source.utf8.elementsEqual(key.utf8) && targets.matches($0.target)
        }
        guard !links.isEmpty else { return document }
        let ranges = try RenameListTokens.ranges(in: document, key: key, items: items)
        var replacements: [(Range<Int>, [UInt8])] = []
        for (item, range) in zip(items, ranges) {
            let text = try targets.text(item.text)
            guard !text.utf8.elementsEqual(item.text.utf8) else { continue }
            let encoded = try RawDocument(bytes: []).settingFrontmatterList([.text(text)], forKey: "value")
            guard case .parsed(let frontmatter) = encoded.frontmatter,
                let raw = frontmatter.field(named: "value")?.value.listItems?.first?.raw
            else { throw EditError.invalidValue }
            replacements.append((range, Array(raw.utf8)))
        }
        var bytes = document.serialized()
        for (range, replacement) in replacements.reversed() {
            bytes.replaceSubrange(range, with: replacement)
        }
        return RawDocument(bytes: bytes)
    }
}
