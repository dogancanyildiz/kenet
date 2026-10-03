import VaultFormat

/// Locates already-parsed scalar spellings in order, never matching inside another scalar.
enum RenameListTokens {
    static func ranges(in document: RawDocument, key: String, items: [FrontmatterScalar]) throws -> [Range<Int>] {
        guard case .parsed(let frontmatter) = document.frontmatter,
            let field = frontmatter.field(named: key), case .list(_, let style) = field.value
        else { throw EditError.invalidValue }
        var starts: [Int] = []
        var offset = document.hasByteOrderMark ? 3 : 0
        for line in document.lines {
            starts.append(offset)
            offset += line.bytes.count
        }
        var result: [Range<Int>] = []
        switch style {
        case .inline:
            let line = field.lineRange.lowerBound
            let bytes = document.lines[line].content
            var cursor = try valueStart(bytes)
            guard cursor < bytes.count, bytes[cursor] == 91 else { throw EditError.invalidValue }
            cursor += 1
            for item in items {
                skipSpace(bytes, cursor: &cursor)
                let range = cursor..<(cursor + item.raw.utf8.count)
                guard range.upperBound <= bytes.count, bytes[range].elementsEqual(item.raw.utf8) else {
                    throw EditError.invalidValue
                }
                result.append((starts[line] + range.lowerBound)..<(starts[line] + range.upperBound))
                cursor = range.upperBound
                skipSpace(bytes, cursor: &cursor)
                if cursor < bytes.count, bytes[cursor] == 44 { cursor += 1 }
            }
        case .block:
            for line in field.lineRange.dropFirst() {
                let bytes = document.lines[line].content
                var cursor = 0
                skipSpace(bytes, cursor: &cursor)
                guard cursor + 1 < bytes.count, bytes[cursor] == 45, bytes[cursor + 1] == 32 else { continue }
                cursor += 2
                skipSpace(bytes, cursor: &cursor)
                guard result.count < items.count else { throw EditError.invalidValue }
                let raw = items[result.count].raw.utf8
                let range = cursor..<(cursor + raw.count)
                guard range.upperBound <= bytes.count, bytes[range].elementsEqual(raw) else {
                    throw EditError.invalidValue
                }
                result.append((starts[line] + range.lowerBound)..<(starts[line] + range.upperBound))
            }
        }
        guard result.count == items.count else { throw EditError.invalidValue }
        return result
    }

    private static func skipSpace(_ bytes: [UInt8], cursor: inout Int) {
        while cursor < bytes.count, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
    }

    private static func valueStart(_ bytes: [UInt8]) throws -> Int {
        var quote: UInt8?
        var cursor = 0
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if let current = quote {
                if current == 34, byte == 92 {
                    cursor += 2
                    continue
                }
                if current == 39, byte == 39, cursor + 1 < bytes.count, bytes[cursor + 1] == 39 {
                    cursor += 2
                    continue
                }
                if byte == current { quote = nil }
            } else if cursor == 0, byte == 34 || byte == 39 {
                quote = byte
            } else if byte == 58, cursor + 1 == bytes.count || bytes[cursor + 1] == 32 || bytes[cursor + 1] == 9 {
                cursor += 1
                skipSpace(bytes, cursor: &cursor)
                return cursor
            }
            cursor += 1
        }
        throw EditError.invalidValue
    }
}
