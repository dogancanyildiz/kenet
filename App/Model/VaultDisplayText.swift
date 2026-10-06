import Foundation
import VaultFormat

/// Display-only transforms for vault text. Never used on write paths.
enum VaultDisplayText {
    /// Replaces wikilink markup with the visible label and strips trailing block ids.
    static func line(_ text: String) -> String {
        stripBlockIdentifiers(stripWikilinks(text))
    }

    /// Applies ``line(_:)`` to each LF-separated line (empty lines preserved).
    static func multiline(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line(String($0)) }
            .joined(separator: "\n")
    }

    private static func stripWikilinks(_ text: String) -> String {
        let document = RawDocument(bytes: text.utf8)
        var bytes = Array(text.utf8)
        for link in document.links.reversed() {
            let offset = document.lines.prefix(link.line).reduce(document.hasByteOrderMark ? 3 : 0) {
                $0 + $1.bytes.count
            }
            let label = Array(visibleLabel(for: link).utf8)
            bytes.replaceSubrange(
                (offset + link.byteRange.lowerBound)..<(offset + link.byteRange.upperBound),
                with: label)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func visibleLabel(for link: WikiLink) -> String {
        if let display = link.displayText, !display.isEmpty { return display }
        let target = link.target
        if target.contains("/") {
            let name = (target as NSString).lastPathComponent
            if name.lowercased().hasSuffix(".md") {
                return String(name.dropLast(3))
            }
            return name
        }
        return target
    }

    /// Trailing ` ^block-id` on a line (Obsidian / vault-format identifiers).
    private static func stripBlockIdentifiers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s+\^[A-Za-z0-9_-]+\s*$"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
