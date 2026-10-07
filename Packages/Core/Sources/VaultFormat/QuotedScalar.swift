/// Reading and writing of single and double quoted scalars that fit on one line.
enum QuotedScalar {
    /// The index of the quote that closes the scalar opened at `open`, or `nil` when the line
    /// ends first.
    static func closingQuote(in line: [UInt8], openedAt open: Int) -> Int? {
        let isDouble = line[open] == Syntax.doubleQuote
        var index = open + 1
        while index < line.count {
            let byte = line[index]
            if isDouble, byte == Syntax.backslash {
                index += 2
            } else if byte == line[open] {
                // Inside single quotes two quotes in a row stand for one quote.
                let isEscaped = !isDouble && index + 1 < line.count && line[index + 1] == Syntax.singleQuote
                if !isEscaped { return index }
                index += 2
            } else {
                index += 1
            }
        }
        return nil
    }

    /// The text of the scalar between the quotes at `open` and `close`, or `nil` when it uses
    /// an escape that is not understood.
    static func decode(_ line: [UInt8], openedAt open: Int, closedAt close: Int) -> String? {
        let body = line[(open + 1)..<close]
        return line[open] == Syntax.doubleQuote ? decodeDoubleQuoted(body) : decodeSingleQuoted(body)
    }

    private static func decodeSingleQuoted(_ body: ArraySlice<UInt8>) -> String {
        var output: [UInt8] = []
        var index = body.startIndex
        while index < body.endIndex {
            output.append(body[index])
            index += body[index] == Syntax.singleQuote ? 2 : 1
        }
        return Syntax.string(output)
    }

    private static func decodeDoubleQuoted(_ body: ArraySlice<UInt8>) -> String? {
        var output: [UInt8] = []
        var index = body.startIndex
        while index < body.endIndex {
            guard body[index] == Syntax.backslash else {
                output.append(body[index])
                index += 1
                continue
            }
            guard index + 1 < body.endIndex else { return nil }
            let escape = body[index + 1]
            index += 2
            if let digitCount = hexDigitCounts[escape] {
                guard index + digitCount <= body.endIndex else { return nil }
                guard let scalar = scalar(hexDigits: body[index..<(index + digitCount)]) else { return nil }
                output.append(contentsOf: String(Character(scalar)).utf8)
                index += digitCount
            } else if let scalar = simpleEscapes[escape] {
                output.append(contentsOf: String(Character(scalar)).utf8)
            } else {
                return nil
            }
        }
        return Syntax.string(output)
    }

    /// Escapes that are followed by a fixed number of hexadecimal digits.
    private static let hexDigitCounts: [UInt8: Int] = [
        UInt8(ascii: "x"): 2, UInt8(ascii: "u"): 4, UInt8(ascii: "U"): 8,
    ]

    private static let simpleEscapes: [UInt8: Unicode.Scalar] = [
        UInt8(ascii: "0"): "\u{00}", UInt8(ascii: "a"): "\u{07}", UInt8(ascii: "b"): "\u{08}",
        UInt8(ascii: "t"): "\u{09}", Syntax.tab: "\u{09}", UInt8(ascii: "n"): "\u{0A}",
        UInt8(ascii: "v"): "\u{0B}", UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "r"): "\u{0D}",
        UInt8(ascii: "e"): "\u{1B}", Syntax.space: " ", Syntax.doubleQuote: "\"",
        UInt8(ascii: "/"): "/", Syntax.backslash: "\\", UInt8(ascii: "N"): "\u{85}",
        UInt8(ascii: "_"): "\u{A0}", UInt8(ascii: "L"): "\u{2028}", UInt8(ascii: "P"): "\u{2029}",
    ]

    private static func scalar(hexDigits: ArraySlice<UInt8>) -> Unicode.Scalar? {
        var value: UInt32 = 0
        for digit in hexDigits {
            guard let nibble = Character(Unicode.Scalar(digit)).hexDigitValue else { return nil }
            value = value << 4 | UInt32(nibble)
        }
        return Unicode.Scalar(value)
    }

    /// Whether a character has to be written as an escape, which only double quotes can do:
    /// everything outside YAML's printable characters, and the printable ones that break a line
    /// or cannot be seen (tab, U+0085, U+2028, U+2029, U+FEFF).
    static func needsEscape(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF: true
        default: false
        }
    }

    /// The text as a double quoted scalar on one line.
    static func encode(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{00}": output += "\\0"
            case "\u{85}": output += "\\N"
            case "\u{2028}": output += "\\L"
            case "\u{2029}": output += "\\P"
            default:
                if needsEscape(scalar) {
                    // Two hexadecimal digits up to U+00FF, four above.
                    let digits = String(scalar.value, radix: 16, uppercase: true)
                    let width = scalar.value > 0xFF ? 4 : 2
                    output +=
                        (width == 4 ? "\\u" : "\\x") + String(repeating: "0", count: width - digits.count) + digits
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }
}
