extension RawDocument {
    /// Reads a document from the raw bytes of a file.
    ///
    /// Reading never fails: every byte sequence, including an empty one and one that is not
    /// valid UTF-8, produces a document that serializes back to the same bytes.
    public init(bytes: some Sequence<UInt8>) {
        let input = Array(bytes)
        let hasByteOrderMark = input.starts(with: Self.byteOrderMark)

        var lines: [RawLine] = []
        var lineStart = hasByteOrderMark ? Self.byteOrderMark.count : 0
        var index = lineStart
        while index < input.count {
            let ending: LineEnding
            switch input[index] {
            case LineEnding.lineFeed:
                ending = .lf
            case LineEnding.carriageReturn:
                let nextIsLineFeed = index + 1 < input.count && input[index + 1] == LineEnding.lineFeed
                ending = nextIsLineFeed ? .crlf : .cr
            default:
                index += 1
                continue
            }
            lines.append(RawLine(content: Array(input[lineStart..<index]), ending: ending))
            index += ending.bytes.count
            lineStart = index
        }
        if lineStart < input.count {
            lines.append(RawLine(content: Array(input[lineStart...]), ending: nil))
        }

        self.init(hasByteOrderMark: hasByteOrderMark, lines: lines)
    }
}
