/// Splits a paragraph block into the entries the relationship graph treats as written together.
///
/// A paragraph block is every non-blank line between blank lines, headings, events and tasks, so a
/// Journal list or a quote under a sentence arrives as one block. Each list item (`-`, `*`, `+`,
/// `1.` or `1)` after optional indentation, then a space, as in the vault format's list marker)
/// starts a segment; lines indented deeper than the item continue it, nested items included. Each
/// run of consecutive `>` lines is one segment, and each run of other lines is one segment.
/// Indentation is measured in columns with tabs advancing to the next multiple of 4.
public enum ParagraphSegments {
    /// The segment ordinal of every line of `text`, lines separated by LF as stored in the index.
    public static func indices(in text: String) -> [Int] {
        enum Run: Equatable {
            case item(indent: Int)
            case quote
            case prose
        }
        var result: [Int] = []
        var run: Run?
        var segment = -1
        for line in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            let bytes = Array(line)
            let (start, indent) = indentation(bytes)
            if case .item(let itemIndent) = run, indent > itemIndent {
                result.append(segment)
                continue
            }
            let next: Run
            if start < bytes.count, bytes[start] == UInt8(ascii: ">") {
                next = .quote
            } else if isListItem(bytes, from: start) {
                next = .item(indent: indent)
            } else {
                next = .prose
            }
            // Quote and prose runs continue on a line of the same kind; every item starts anew.
            if next == .quote || next == .prose, next == run {
                result.append(segment)
                continue
            }
            segment += 1
            run = next
            result.append(segment)
        }
        return result
    }

    /// The segment ordinal of the zero-based `line` of `text`; a line outside the text is segment 0.
    public static func index(ofLine line: Int, in text: String) -> Int {
        let segments = indices(in: text)
        return segments.indices.contains(line) ? segments[line] : 0
    }

    private static func indentation(_ bytes: [UInt8]) -> (bytes: Int, columns: Int) {
        var count = 0
        var columns = 0
        for byte in bytes {
            if byte == UInt8(ascii: "\t") {
                columns += 4 - columns % 4
            } else if byte == UInt8(ascii: " ") {
                columns += 1
            } else {
                break
            }
            count += 1
        }
        return (count, columns)
    }

    private static func isListItem(_ bytes: [UInt8], from start: Int) -> Bool {
        var cursor = start
        guard cursor < bytes.count else { return false }
        if [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+")].contains(bytes[cursor]) {
            cursor += 1
        } else {
            while cursor < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[cursor]) { cursor += 1 }
            guard (1...9).contains(cursor - start), cursor < bytes.count,
                bytes[cursor] == UInt8(ascii: ".") || bytes[cursor] == UInt8(ascii: ")")
            else { return false }
            cursor += 1
        }
        return cursor < bytes.count && bytes[cursor] == UInt8(ascii: " ")
    }
}
