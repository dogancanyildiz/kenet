/// Shared physical indentation and unquoted list syntax.
enum LineSyntax {
    static func indentation(_ bytes: [UInt8]) -> (bytes: Int, columns: Int) {
        var count = 0
        var columns = 0
        for byte in bytes {
            if byte == Syntax.tab {
                columns += 4 - columns % 4
            } else if byte == Syntax.space {
                columns += 1
            } else {
                break
            }
            count += 1
        }
        return (count, columns)
    }

    static func listContentColumn(_ bytes: [UInt8], indent: (bytes: Int, columns: Int)) -> Int? {
        var cursor = indent.bytes
        guard cursor < bytes.count else { return nil }
        if [UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "+")].contains(bytes[cursor]) {
            cursor += 1
        } else {
            let start = cursor
            while cursor < bytes.count, Syntax.isDigit(bytes[cursor]) { cursor += 1 }
            guard (1...9).contains(cursor - start), cursor < bytes.count,
                bytes[cursor] == UInt8(ascii: ".") || bytes[cursor] == UInt8(ascii: ")")
            else { return nil }
            cursor += 1
        }
        guard cursor < bytes.count, bytes[cursor] == Syntax.space else { return nil }
        while cursor < bytes.count, bytes[cursor] == Syntax.space { cursor += 1 }
        return indent.columns + cursor - indent.bytes
    }
}
