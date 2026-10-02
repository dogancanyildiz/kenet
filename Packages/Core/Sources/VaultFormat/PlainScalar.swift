/// Rules for unquoted scalars: what one means when read, and when text may be written as one.
enum PlainScalar {
    private static let nullSpellings: Set<[UInt8]> = Set(["~", "null", "Null", "NULL"].map { Array($0.utf8) })
    private static let trueSpellings: Set<[UInt8]> = Set(["true", "True", "TRUE"].map { Array($0.utf8) })
    private static let falseSpellings: Set<[UInt8]> = Set(["false", "False", "FALSE"].map { Array($0.utf8) })

    /// Words some YAML version reads as something other than text, compared without case.
    private static let reservedWords: Set<[UInt8]> = Set(
        ["true", "false", "yes", "no", "on", "off", "y", "n", "null", "~", "<<", "="].map { Array($0.utf8) }
    )

    /// The meaning of an unquoted spelling. Anything not recognized with certainty is text.
    static func kind(of bytes: [UInt8]) -> FrontmatterScalar.Kind {
        if bytes.isEmpty || nullSpellings.contains(bytes) { return .empty }
        if trueSpellings.contains(bytes) { return .boolean(true) }
        if falseSpellings.contains(bytes) { return .boolean(false) }
        if isNumber(bytes) { return .number }
        if let date = CalendarDate(utf8: bytes) { return .date(date) }
        return .text
    }

    /// Whether the bytes are `[-+]?(0|[1-9][0-9]*)`.
    static func isInteger(_ bytes: [UInt8]) -> Bool {
        integerEnd(bytes) == bytes.count
    }

    /// Whether the bytes are `[-+]?(0|[1-9][0-9]*)(\.[0-9]+)?`.
    ///
    /// Other spellings YAML accepts as numbers (exponents, hexadecimal, octal, `.5`, `1.`, `.inf`,
    /// digits with underscores or leading zeros) are read differently by different YAML readers
    /// and are text here.
    static func isNumber(_ bytes: [UInt8]) -> Bool {
        guard var index = integerEnd(bytes) else { return false }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            guard let end = digitsEnd(bytes, from: index + 1) else { return false }
            index = end
        }
        return index == bytes.count
    }

    /// Whether two number spellings stand for the same value: the sign, the integer digits and
    /// the fraction without trailing zeros are equal, so `20.029` equals `20.0290` and `+5`
    /// equals `5`. Both must satisfy `isNumber`.
    static func numbersAreEqual(_ first: [UInt8], _ second: [UInt8]) -> Bool {
        normalizedNumber(first) == normalizedNumber(second)
    }

    private static func normalizedNumber(_ bytes: [UInt8]) -> [UInt8] {
        let hasSign = bytes.first == Syntax.dash || bytes.first == UInt8(ascii: "+")
        var digits = Array(bytes.dropFirst(hasSign ? 1 : 0))
        if digits.contains(UInt8(ascii: ".")) {
            while digits.last == UInt8(ascii: "0") {
                digits.removeLast()
            }
            if digits.last == UInt8(ascii: ".") { digits.removeLast() }
        }
        let isNegative = bytes.first == Syntax.dash && digits != [UInt8(ascii: "0")]
        return (isNegative ? [Syntax.dash] : []) + digits
    }

    /// The index after the integer at the start of the bytes, or `nil` when there is none.
    private static func integerEnd(_ bytes: [UInt8]) -> Int? {
        let hasSign = bytes.first == Syntax.dash || bytes.first == UInt8(ascii: "+")
        let start = hasSign ? 1 : 0
        guard let end = digitsEnd(bytes, from: start) else { return nil }
        let hasLeadingZero = bytes[start] == UInt8(ascii: "0") && end - start > 1
        return hasLeadingZero ? nil : end
    }

    /// The index after the run of digits that starts at `start`, or `nil` when no digit is there.
    private static func digitsEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index < bytes.count, Syntax.isDigit(bytes[index]) {
            index += 1
        }
        return index > start ? index : nil
    }

    /// Whether a plain scalar can start at `index`, given that the scalar ends before `end`.
    static func canStart(_ bytes: [UInt8], at index: Int, end: Int) -> Bool {
        let first = bytes[index]
        if Syntax.indicators.contains(first) { return false }
        if first == Syntax.dash || first == Syntax.questionMark || first == Syntax.colon {
            return index + 1 < end && !Syntax.isBlank(bytes[index + 1])
        }
        return true
    }

    /// Whether the bytes contain a colon that YAML reads as "key: value" (followed by a blank or the end).
    static func containsMappingIndicator(_ bytes: some Collection<UInt8>) -> Bool {
        var previous: UInt8?
        for byte in bytes {
            if previous == Syntax.colon, Syntax.isBlank(byte) { return true }
            previous = byte
        }
        return previous == Syntax.colon
    }

    /// Whether the bytes contain a `#` that starts a comment (preceded by a blank).
    static func containsComment(_ bytes: some Collection<UInt8>) -> Bool {
        var previous: UInt8?
        for byte in bytes {
            if byte == Syntax.hash, let previous, Syntax.isBlank(previous) { return true }
            previous = byte
        }
        return false
    }

    /// Whether text can be written without quotes and still be read back as the same text.
    ///
    /// The rule errs on the side of quoting: text is quoted when any YAML 1.1 or 1.2 reader
    /// could take it for a number, a date, a boolean, null or a piece of syntax. Inside an inline
    /// list that includes every colon and question mark.
    static func isSafe(_ text: String, inFlow: Bool) -> Bool {
        let bytes = Array(text.utf8)
        guard let first = bytes.first, let last = bytes.last else { return false }
        guard !Syntax.isBlank(first), !Syntax.isBlank(last) else { return false }
        guard !Syntax.indicators.contains(first) else { return false }
        guard first != Syntax.dash, first != Syntax.questionMark, first != Syntax.colon else { return false }
        guard !containsMappingIndicator(bytes), !containsComment(bytes) else { return false }
        guard !text.unicodeScalars.contains(where: QuotedScalar.needsEscape) else { return false }
        if inFlow, bytes.contains(where: isForbiddenInFlow) { return false }
        guard !startsWithDocumentEnd(bytes) else { return false }
        guard !reservedWords.contains(bytes.map(lowercased)) else { return false }
        guard !looksLikeNumber(bytes), !looksLikeDate(bytes) else { return false }
        return kind(of: bytes) == .text
    }

    /// Whether every reader takes an unquoted key for the same text.
    ///
    /// A key that could be a number, a date, a boolean or null is turned into another key by
    /// some readers (`0x1F` becomes `31`, a date becomes a date object), and a key that starts
    /// with `-`, `?` or `:` is read as syntax by some. `yes`, `no`, `on` and `off` are words to
    /// YAML 1.2 readers and are accepted.
    static func isCertainKey(_ bytes: [UInt8]) -> Bool {
        guard let first = bytes.first else { return false }
        guard first != Syntax.dash, first != Syntax.questionMark, first != Syntax.colon else { return false }
        guard kind(of: bytes) == .text, !looksLikeDate(bytes), !startsWithDocumentEnd(bytes) else { return false }

        let hasSign = first == UInt8(ascii: "+")
        let unsigned = bytes.dropFirst(hasSign ? 1 : 0)
        guard let lead = unsigned.first, Syntax.isDigit(lead) || lead == UInt8(ascii: ".") else { return true }
        if lead == UInt8(ascii: ".") { return !looksLikeNumber(bytes) }
        // Digits mixed only with the letters and signs number spellings use.
        return !unsigned.allSatisfy(numberCharacters.contains)
    }

    private static let numberCharacters: Set<UInt8> = Set("0123456789abcdefABCDEFxXoO_.+-:".utf8)

    /// Whether an unquoted item of an inline list must not contain the byte: list syntax, and
    /// the colon and question mark that some readers take for syntax there.
    static func isForbiddenInFlow(_ byte: UInt8) -> Bool {
        Syntax.flowIndicators.contains(byte) || byte == Syntax.colon || byte == Syntax.questionMark
    }

    /// Whether the bytes are `...` alone or followed by a blank, which ends a YAML document at
    /// the start of a line.
    static func startsWithDocumentEnd(_ bytes: [UInt8]) -> Bool {
        let marker = Array("...".utf8)
        return bytes.starts(with: marker) && (bytes.count == marker.count || Syntax.isBlank(bytes[marker.count]))
    }

    /// Whether some YAML reader could take the bytes for a number: a digit after an optional
    /// sign with no blank anywhere, or a leading dot followed by a digit, `inf` or `nan`.
    private static func looksLikeNumber(_ bytes: [UInt8]) -> Bool {
        let hasSign = bytes.first == UInt8(ascii: "+") || bytes.first == Syntax.dash
        let unsigned = bytes.dropFirst(hasSign ? 1 : 0)
        guard let first = unsigned.first else { return false }
        if Syntax.isDigit(first) { return !bytes.contains(where: Syntax.isBlank) }
        guard first == UInt8(ascii: ".") else { return false }
        let rest = unsigned.dropFirst().map(lowercased)
        if let next = rest.first, Syntax.isDigit(next) { return true }
        return rest == Array("inf".utf8) || rest == Array("nan".utf8)
    }

    /// Whether the bytes start like a YAML timestamp: `YYYY-M-D` with one or two digit month and day.
    private static func looksLikeDate(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 8, bytes[0..<4].allSatisfy(Syntax.isDigit), bytes[4] == Syntax.dash else { return false }
        var index = 5
        for part in 0..<2 {
            let start = index
            while index < bytes.count, index - start < 2, Syntax.isDigit(bytes[index]) {
                index += 1
            }
            guard index > start else { return false }
            if part == 0 {
                guard index < bytes.count, bytes[index] == Syntax.dash else { return false }
                index += 1
            }
        }
        return true
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") ? byte + 0x20 : byte
    }
}
