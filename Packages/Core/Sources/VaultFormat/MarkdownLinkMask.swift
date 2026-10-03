/// Recognizes balanced inline Markdown links without changing their spelling.
enum MarkdownLinkMask {
    static func ranges(_ bytes: [UInt8], excluding mask: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var cursor = 0
        while cursor < bytes.count {
            guard bytes[cursor] == 91, !mask[cursor], !escaped(bytes, at: cursor),
                let labelEnd = end(bytes, from: cursor, opening: 91, closing: 93, mask: mask),
                labelEnd < bytes.count, bytes[labelEnd] == 40,
                let targetEnd = end(bytes, from: labelEnd, opening: 40, closing: 41)
            else {
                cursor += 1
                continue
            }
            ranges.append(cursor..<targetEnd)
            cursor = targetEnd
        }
        return ranges
    }

    private static func end(
        _ bytes: [UInt8], from start: Int, opening: UInt8, closing: UInt8, mask: [Bool]? = nil
    ) -> Int? {
        var depth = 1
        var cursor = start + 1
        while cursor < bytes.count {
            if mask?[cursor] != true && !escaped(bytes, at: cursor) {
                if bytes[cursor] == opening { depth += 1 }
                if bytes[cursor] == closing {
                    depth -= 1
                    if depth == 0 { return cursor + 1 }
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func escaped(_ bytes: [UInt8], at position: Int) -> Bool {
        var start = position
        while start > 0, bytes[start - 1] == 92 { start -= 1 }
        return (position - start) % 2 == 1
    }
}
