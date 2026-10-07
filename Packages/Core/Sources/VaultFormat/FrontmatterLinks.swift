/// Projects decoded scalar offsets back onto the physical YAML spelling.
enum FrontmatterLinks {
    static func parse(_ field: FrontmatterField, lines: [RawLine]) -> [WikiLink] {
        let part = field.layout.keyPart
        var result: [WikiLink] = []
        func append(_ scalar: FrontmatterScalar, part: LinePart, offset: Int, entry: String? = nil) {
            let raw = Array(scalar.raw.utf8)
            let spans = sourceSpans(raw)
            let decoded = Array(scalar.text.utf8)
            guard spans.count == decoded.count else { return }
            func physical(_ range: Range<Int>) -> Range<Int> {
                let lower = range.lowerBound < spans.count ? spans[range.lowerBound].lowerBound : raw.count
                let upper = range.isEmpty ? lower : spans[range.upperBound - 1].upperBound
                return (offset + lower)..<(offset + upper)
            }
            for match in WikiLinkScanner.scan(decoded) {
                let targetRange = physical(match.targetRange)
                result.append(
                    WikiLink(
                        line: part.line, byteRange: physical(match.range), targetRange: targetRange,
                        target: match.target, rawTarget: Syntax.string(lines[part.line].content[targetRange]),
                        anchor: match.anchor, displayText: match.display, isEmbedded: match.embedded,
                        source: .frontmatter(key: field.key, entry: entry)))
            }
        }
        func offset(_ part: LinePart) -> Int { part.head.utf8.count + part.gap.utf8.count }
        switch field.value {
        case .scalar(let scalar): append(scalar, part: part, offset: offset(part))
        case .list(let items, .block):
            for (item, child) in zip(items, field.layout.children) {
                append(item, part: child, offset: offset(child))
            }
        case .list(let items, .inline):
            let bytes = lines[part.line].content
            var cursor = offset(part) + 1
            for item in items {
                let raw = Array(item.raw.utf8)
                guard !raw.isEmpty,
                    let start = (cursor..<bytes.count).first(where: {
                        bytes[$0...].starts(with: raw)
                    })
                else { continue }
                append(item, part: part, offset: start)
                cursor = start + raw.count
            }
        case .mapping(let entries):
            for (entry, child) in zip(entries, field.layout.children) {
                append(entry.value, part: child, offset: offset(child), entry: entry.key)
            }
        case .raw: break
        }
        return result
    }

    /// Each decoded UTF-8 byte owns the full source token that produced it.
    private static func sourceSpans(_ raw: [UInt8]) -> [Range<Int>] {
        guard let quote = raw.first, quote == 34 || quote == 39 else {
            return raw.indices.map { $0..<($0 + 1) }
        }
        var result: [Range<Int>] = []
        var index = 1
        while index < raw.count - 1 {
            let start = index
            if quote == 34, raw[index] == 92 {
                let width: Int
                switch raw[index + 1] {
                case 120: width = 4
                case 117: width = 6
                case 85: width = 10
                default: width = 2
                }
                index += width
                let token = [quote] + raw[start..<index] + [quote]
                let text = QuotedScalar.decode(token, openedAt: 0, closedAt: token.count - 1) ?? ""
                result += Array(repeating: start..<index, count: text.utf8.count)
            } else if quote == 39, raw[index] == 39 {
                index += 2
                result.append(start..<index)
            } else {
                index += 1
                result.append(start..<index)
            }
        }
        return result
    }
}
