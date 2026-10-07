import VaultFormat

/// Reads the bytes and returns every way the resulting document breaks the lossless contract.
///
/// An empty result means: serialization reproduces the input, the structural invariants hold,
/// and the lines match the independent reference model.
func losslessViolations(of input: [UInt8]) -> [String] {
    let document = RawDocument(bytes: input)
    let lines = document.lines
    var violations: [String] = []

    if document.serialized() != input {
        violations.append("serialized bytes differ from the input")
    }

    let joined = (document.hasByteOrderMark ? RawDocument.byteOrderMark : []) + lines.flatMap(\.bytes)
    if joined != input {
        violations.append("byte order mark plus the bytes of every line differ from the input")
    }

    for (index, line) in lines.enumerated() {
        if line.content.contains(0x0A) || line.content.contains(0x0D) {
            violations.append("line \(index) content contains LF or CR")
        }
        if line.ending == nil && index != lines.count - 1 {
            violations.append("line \(index) has no line ending but is not the last line")
        }
        if line.ending == nil && line.content.isEmpty {
            violations.append("line \(index) has neither content nor a line ending")
        }
        if line.ending == .lf && line.content.isEmpty && index > 0 && lines[index - 1].ending == .cr {
            violations.append("lines \(index - 1) and \(index) split one CRLF into a CR and an LF ending")
        }
        let expectedBytes = line.content + (line.ending?.bytes ?? [])
        if line.bytes != expectedBytes {
            violations.append("line \(index) bytes are not its content followed by its ending")
        }
        switch line.text {
        case .some(let text):
            if Array(text.utf8) != line.content {
                violations.append("line \(index) text does not encode back to its content")
            }
            if !ReferenceModel.isValidUTF8(line.content) {
                violations.append("line \(index) has text although its content is not valid UTF-8")
            }
            if line.displayText != text {
                violations.append("line \(index) display text differs from its text")
            }
        case .none:
            if ReferenceModel.isValidUTF8(line.content) {
                violations.append("line \(index) has no text although its content is valid UTF-8")
            }
            if !line.displayText.unicodeScalars.contains("\u{FFFD}") {
                violations.append("line \(index) display text does not mark its ill-formed bytes")
            }
        }
    }

    if document.hasByteOrderMark != ReferenceModel.hasByteOrderMark(input) {
        violations.append("byte order mark flag is \(document.hasByteOrderMark)")
    }

    let expectedLines = ReferenceModel.lines(input)
    if lines.map(LineShape.init) != expectedLines {
        violations.append("lines \(lines.map(LineShape.init)) differ from the reference \(expectedLines)")
    }

    let body = input.dropFirst(document.hasByteOrderMark ? RawDocument.byteOrderMark.count : 0)
    if document.isValidUTF8 != ReferenceModel.isValidUTF8(body) {
        violations.append("isValidUTF8 is \(document.isValidUTF8)")
    }
    if document.isReadOnly == document.isValidUTF8 {
        violations.append("isReadOnly is not the opposite of isValidUTF8")
    }

    let expectedNewLineEnding = expectedLines.first?.ending ?? .lf
    if document.lineEndingForNewLines != expectedNewLineEnding {
        violations.append("lineEndingForNewLines is \(document.lineEndingForNewLines)")
    }

    return violations.map { "\($0) [input: \(hex(input.prefix(64)))\(input.count > 64 ? " …" : "")]" }
}
