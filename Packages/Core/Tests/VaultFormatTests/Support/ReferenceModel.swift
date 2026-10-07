import VaultFormat

/// What a line looks like, written out independently of the model under test.
struct LineShape: Equatable, CustomStringConvertible {
    var content: [UInt8]
    var ending: LineEnding?

    init(_ content: [UInt8], _ ending: LineEnding?) {
        self.content = content
        self.ending = ending
    }

    init(_ content: String, _ ending: LineEnding?) {
        self.init(Array(content.utf8), ending)
    }

    init(_ line: RawLine) {
        self.init(line.content, line.ending)
    }

    var description: String {
        "(\(hex(content)), \(ending.map { "\($0)" } ?? "none"))"
    }
}

/// A deliberately different implementation of the splitting rules, used to cross-check the model.
enum ReferenceModel {
    static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func hasByteOrderMark(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 3 && Array(bytes[0..<3]) == byteOrderMark
    }

    /// Splits in two passes instead of scanning once: first on LF, deciding per piece whether a
    /// trailing CR belonged to the terminator, then each piece on the CRs that remain inside it.
    static func lines(_ bytes: [UInt8]) -> [LineShape] {
        let body = hasByteOrderMark(bytes) ? Array(bytes.dropFirst(3)) : bytes
        var pieces = body.split(separator: 0x0A, omittingEmptySubsequences: false).map { Array($0) }
        let tail = pieces.removeLast()

        var shapes: [LineShape] = []
        for piece in pieces {
            if piece.last == 0x0D {
                shapes += splitOnCarriageReturns(Array(piece.dropLast()), lastEnding: .crlf)
            } else {
                shapes += splitOnCarriageReturns(piece, lastEnding: .lf)
            }
        }
        shapes += splitOnCarriageReturns(tail, lastEnding: nil).filter { !$0.content.isEmpty || $0.ending != nil }
        return shapes
    }

    /// Every CR inside the piece ends a line; what follows the last CR takes the piece's own ending.
    private static func splitOnCarriageReturns(_ piece: [UInt8], lastEnding: LineEnding?) -> [LineShape] {
        var parts = piece.split(separator: 0x0D, omittingEmptySubsequences: false).map { Array($0) }
        let last = parts.removeLast()
        return parts.map { LineShape($0, .cr) } + [LineShape(last, lastEnding)]
    }

    /// The same file with every line ending replaced by one kind.
    static func bytes(_ bytes: [UInt8], withEveryEndingAs ending: LineEnding) -> [UInt8] {
        let prefix = hasByteOrderMark(bytes) ? byteOrderMark : []
        return prefix + lines(bytes).flatMap { $0.content + ($0.ending == nil ? [] : ending.bytes) }
    }

    /// Strict UTF-8 validation with the standard library's decoder instead of string conversion.
    static func isValidUTF8(_ bytes: some Sequence<UInt8>) -> Bool {
        var decoder = UTF8()
        var iterator = bytes.makeIterator()
        while true {
            switch decoder.decode(&iterator) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }
}

func hex(_ bytes: some Sequence<UInt8>) -> String {
    bytes.map { byte in
        let digits = String(byte, radix: 16, uppercase: true)
        return digits.count == 1 ? "0" + digits : digits
    }.joined(separator: " ")
}
