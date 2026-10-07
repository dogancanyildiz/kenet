import Foundation
import VaultFormat

/// Display-only transforms for vault text. Never used on write paths.
enum VaultDisplayText {
    /// Replaces wikilink markup with the visible label and strips trailing app block ids.
    /// Multiline input is handled line-by-line (fences left intact).
    static func line(_ text: String) -> String {
        transform(text, stripBlockIDs: true)
    }

    /// Same as ``line(_:)`` but keeps trailing block identifiers (frontmatter values).
    static func wikilinksOnly(_ text: String) -> String {
        transform(text, stripBlockIDs: false)
    }

    /// Applies ``line(_:)`` to each line (empty lines preserved; CRLF normalized for display).
    static func multiline(_ text: String) -> String {
        transform(text, stripBlockIDs: true)
    }

    private static func transform(_ text: String, stripBlockIDs: Bool) -> String {
        let normalized =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var fenceOpen = false
        var fenceMarker: UInt8?
        var fenceCount = 0
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let mapped = lines.map { substring -> String in
            let line = String(substring)
            let bytes = Array(line.utf8)
            if updateFence(
                bytes: bytes, fenceOpen: &fenceOpen, fenceMarker: &fenceMarker, fenceCount: &fenceCount)
            {
                return line
            }
            let stripped = stripWikilinksOnLine(line)
            return stripBlockIDs ? stripBlockIdentifiers(stripped) : stripped
        }
        return mapped.joined(separator: "\n")
    }

    /// Returns true when the line is inside a fence or is a fence delimiter (open or close).
    private static func updateFence(
        bytes: [UInt8], fenceOpen: inout Bool, fenceMarker: inout UInt8?, fenceCount: inout Int
    ) -> Bool {
        let indent = bytes.prefix(while: { $0 == 0x20 || $0 == 0x09 }).count
        let text = bytes.dropFirst(indent)
        if fenceOpen, let marker = fenceMarker {
            let run = text.prefix(while: { $0 == marker }).count
            if indent <= 3, run >= fenceCount, text.dropFirst(run).allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                fenceOpen = false
                fenceMarker = nil
                fenceCount = 0
            }
            return true
        }
        guard let marker = text.first, marker == 0x60 || marker == 0x7E else { return false }
        let count = text.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return false }
        if marker == 0x60, text.dropFirst(count).contains(0x60) { return false }
        guard indent <= 3 else { return false }
        fenceOpen = true
        fenceMarker = marker
        fenceCount = count
        return true
    }

    private static func stripWikilinksOnLine(_ text: String) -> String {
        let document = RawDocument(bytes: text.utf8)
        var bytes = Array(text.utf8)
        for link in document.links.reversed() {
            let offset = document.lines.prefix(link.line).reduce(document.hasByteOrderMark ? 3 : 0) {
                $0 + $1.bytes.count
            }
            var lower = offset + link.byteRange.lowerBound
            if link.isEmbedded, lower > 0, bytes[lower - 1] == 0x21 {
                lower -= 1
            }
            let upper = offset + link.byteRange.upperBound
            let label = Array(visibleLabel(for: link).utf8)
            if label.isEmpty {
                var removeLower = lower
                var removeUpper = upper
                if removeLower > 0, bytes[removeLower - 1] == 0x20 {
                    removeLower -= 1
                } else if removeUpper < bytes.count, bytes[removeUpper] == 0x20 {
                    removeUpper += 1
                }
                bytes.replaceSubrange(removeLower..<removeUpper, with: [])
            } else {
                bytes.replaceSubrange(lower..<upper, with: label)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func visibleLabel(for link: WikiLink) -> String {
        if let display = link.displayText, !display.isEmpty { return display }
        if link.target.isEmpty {
            switch link.anchor {
            case .heading(let heading): return heading
            case .block: return ""
            case nil: return ""
            }
        }
        let target = caretStrippedTarget(link.target)
        if target.isEmpty { return "" }
        if target.contains("/") {
            let name = (target as NSString).lastPathComponent
            if name.lowercased().hasSuffix(".md") {
                return String(name.dropLast(3))
            }
            return name
        }
        return target
    }

    /// `Ad^blok` (caret in target, no `#` anchor) shows as `Ad`.
    private static func caretStrippedTarget(_ target: String) -> String {
        guard let caret = target.firstIndex(of: "^") else { return target }
        return String(target[..<caret])
    }

    /// Trailing app-produced block id: space + `^` + 6 `[a-z0-9]` at end of line.
    /// Only the app's format is stripped; longer hand-named Obsidian ids stay visible.
    private static func stripBlockIdentifiers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s+\^[a-z0-9]{6}\s*$"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}

/// Search-result preview only: vault display rules plus fence delimiter lines and ATX `#` markers dropped.
/// Unlike ``VaultDisplayText``, fence *interior* is also display-transformed so search never shows raw markup.
enum SearchPreviewText {
    static func display(_ text: String) -> String {
        let normalized =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        let result = lines.compactMap { substring -> String? in
            let line = String(substring)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isFenceDelimiter(trimmed) { return nil }
            // Always apply display rules (even for lines that were inside a fence in the source).
            let plain = stripListMarker(stripHeadingMarkers(VaultDisplayText.line(line)))
            return plain
        }
        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Preview title; when the match is only fence markers, fall back to the note name.
    static func title(_ text: String, file: String) -> String {
        let preview = display(text)
        return preview.isEmpty ? noteDisplayName(file) : preview
    }

    /// Vault-relative path → note name without `.md` (never a folder path).
    static func noteDisplayName(_ file: String) -> String {
        let name = (file as NSString).lastPathComponent
        if name.lowercased().hasSuffix(".md") {
            return String(name.dropLast(3))
        }
        return name
    }

    private static func isFenceDelimiter(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "`" || first == "~" else { return false }
        let count = trimmed.prefix(while: { $0 == first }).count
        guard count >= 3 else { return false }
        let rest = trimmed.dropFirst(count)
        if first == "`", rest.contains("`") { return false }
        // Opening may have a language tag; closing is blank after the run.
        return true
    }

    private static func stripHeadingMarkers(_ line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        var hashes = 0
        var cursor = index
        while cursor < line.endIndex, line[cursor] == "#", hashes < 6 {
            hashes += 1
            cursor = line.index(after: cursor)
        }
        guard hashes > 0, cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" else {
            return line
        }
        let afterSpace = line.index(after: cursor)
        return String(line[afterSpace...])
    }

    /// Drops unordered / ordered list markers and Obsidian task boxes for search preview only.
    private static func stripListMarker(_ line: String) -> String {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        let body = line[index...]
        guard let first = body.first else { return line }

        if "-*+".contains(first) {
            var cursor = body.index(after: body.startIndex)
            guard cursor < body.endIndex, body[cursor] == " " || body[cursor] == "\t" else {
                return line
            }
            cursor = body.index(after: cursor)
            while cursor < body.endIndex, body[cursor] == " " || body[cursor] == "\t" {
                cursor = body.index(after: cursor)
            }
            if cursor < body.endIndex, body[cursor] == "[" {
                var box = body.index(after: cursor)
                if box < body.endIndex {
                    box = body.index(after: box)
                    if box < body.endIndex, body[box] == "]" {
                        box = body.index(after: box)
                        if box == body.endIndex { return "" }
                        if body[box] == " " || body[box] == "\t" {
                            box = body.index(after: box)
                            while box < body.endIndex, body[box] == " " || body[box] == "\t" {
                                box = body.index(after: box)
                            }
                            return String(body[box...])
                        }
                    }
                }
            }
            return String(body[cursor...])
        }

        var cursor = body.startIndex
        var digits = 0
        while cursor < body.endIndex, body[cursor].isNumber, digits < 9 {
            digits += 1
            cursor = body.index(after: cursor)
        }
        guard digits > 0, cursor < body.endIndex, body[cursor] == "." || body[cursor] == ")" else {
            return line
        }
        cursor = body.index(after: cursor)
        guard cursor < body.endIndex, body[cursor] == " " || body[cursor] == "\t" else {
            return line
        }
        cursor = body.index(after: cursor)
        while cursor < body.endIndex, body[cursor] == " " || body[cursor] == "\t" {
            cursor = body.index(after: cursor)
        }
        return String(body[cursor...])
    }
}
