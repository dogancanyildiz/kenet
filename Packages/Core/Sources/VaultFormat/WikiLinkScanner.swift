/// Scans one decoded line, keeping syntax decisions separate from physical byte mapping.
enum WikiLinkScanner {
    struct Match {
        let range: Range<Int>
        let targetRange: Range<Int>
        let target: String
        let anchor: WikiLinkAnchor?
        let display: String?
        let embedded: Bool
    }

    static func scan(_ bytes: [UInt8]) -> [Match] {
        let code = inlineCode(bytes)
        var result: [Match] = []
        var opening: Int?
        var index = 0
        while index + 1 < bytes.count {
            if code[index] || bytes[index] == 10 || bytes[index] == 13 {
                opening = nil
                index += 1
                continue
            }
            if bytes[index] == 91, bytes[index + 1] == 91, !code[index + 1] {
                opening = escaped(bytes, at: index) ? nil : index
                index += 1
            } else if bytes[index] == 93, bytes[index + 1] == 93, let start = opening, !code[index + 1] {
                if let match = match(bytes, start: start, end: index) { result.append(match) }
                opening = nil
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    private static func escaped(_ bytes: [UInt8], at index: Int) -> Bool {
        var start = index
        while start > 0, bytes[start - 1] == 92 { start -= 1 }
        return (index - start) % 2 == 1
    }

    private static func match(_ bytes: [UInt8], start: Int, end: Int) -> Match? {
        let body = (start + 2)..<end
        let pipe = body.first { bytes[$0] == 124 }
        let separator = pipe.map { $0 > start + 2 && bytes[$0 - 1] == 92 ? $0 - 1 : $0 } ?? end
        let hash = body.prefix { $0 < separator }.first { bytes[$0] == 35 }
        let targetRange = trimmedRange(bytes, range: (start + 2)..<(hash ?? separator))
        var normalizedRange = targetRange
        if Syntax.string(bytes[targetRange]).hasSuffix(".md") {
            normalizedRange = targetRange.lowerBound..<(targetRange.upperBound - 3)
        }
        let target = Syntax.string(bytes[trimmedRange(bytes, range: normalizedRange)])
        let anchorText = hash.map { Syntax.string(bytes[($0 + 1)..<separator]) }
        guard !target.isEmpty || anchorText?.isEmpty == false else { return nil }
        let anchor = anchorText.map { text -> WikiLinkAnchor in
            text.hasPrefix("^") ? .block(String(text.dropFirst())) : .heading(text)
        }
        return Match(
            range: start..<(end + 2), targetRange: targetRange, target: target,
            anchor: anchor, display: pipe.map { Syntax.string(bytes[($0 + 1)..<end]) },
            embedded: start > 0 && bytes[start - 1] == 33 && !escaped(bytes, at: start - 1))
    }

    /// Trims whitespace while retaining offsets into the original decoded UTF-8 bytes.
    private static func trimmedRange(_ bytes: [UInt8], range: Range<Int>) -> Range<Int> {
        let text = Syntax.string(bytes[range])
        let leading = text.prefix { $0.isWhitespace }.utf8.count
        let kept = text.drop(while: { $0.isWhitespace }).reversed().drop(while: { $0.isWhitespace }).reversed()
        let lower = range.lowerBound + leading
        return lower..<(lower + String(kept).utf8.count)
    }

    /// Pair maximal backtick runs of equal length within each physical decoded line.
    private static func inlineCode(_ bytes: [UInt8]) -> [Bool] {
        var runs: [(start: Int, end: Int)] = []
        var mask = Array(repeating: false, count: bytes.count)
        var index = 0
        func markRuns() {
            var next: [Int: Int] = [:]
            var closing: [Int: Int] = [:]
            for position in runs.indices.reversed() {
                let width = runs[position].end - runs[position].start
                closing[position] = next[width]
                next[width] = position
            }
            var run = 0
            while run < runs.count {
                let open = runs[run]
                if let close = closing[run] {
                    for position in open.start..<runs[close].end { mask[position] = true }
                    run = close + 1
                } else {
                    run += 1
                }
            }
            runs.removeAll()
        }
        while index < bytes.count {
            if bytes[index] == 10 || bytes[index] == 13 { markRuns() }
            if bytes[index] == 96 {
                let start = index
                while index < bytes.count, bytes[index] == 96 { index += 1 }
                runs.append((start, index))
            } else {
                index += 1
            }
        }
        markRuns()
        return mask
    }
}
