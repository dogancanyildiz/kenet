import Foundation
import Testing
import VaultFormat

struct LineSplittingTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var input: [UInt8]
        var hasByteOrderMark = false
        var lines: [LineShape]

        var testDescription: String { name }
    }

    static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    static let cases: [Case] = [
        Case(name: "empty input", input: [], lines: []),
        Case(name: "single line without ending", input: Array("a".utf8), lines: [LineShape("a", nil)]),
        Case(name: "single line with LF", input: Array("a\n".utf8), lines: [LineShape("a", .lf)]),
        Case(name: "two empty lines", input: Array("\n\n".utf8), lines: [LineShape("", .lf), LineShape("", .lf)]),
        Case(
            name: "CRLF then unterminated line",
            input: Array("a\r\nb".utf8),
            lines: [LineShape("a", .crlf), LineShape("b", nil)]
        ),
        Case(name: "only CRLF", input: Array("\r\n".utf8), lines: [LineShape("", .crlf)]),
        Case(name: "only CR", input: Array("\r".utf8), lines: [LineShape("", .cr)]),
        Case(
            name: "CR between two lines",
            input: Array("a\rb".utf8),
            lines: [LineShape("a", .cr), LineShape("b", nil)]
        ),
        Case(name: "input ending with CR", input: Array("a\r".utf8), lines: [LineShape("a", .cr)]),
        Case(
            name: "CR then LF-terminated line",
            input: Array("a\rb\n".utf8),
            lines: [LineShape("a", .cr), LineShape("b", .lf)]
        ),
        Case(name: "CR before CRLF", input: Array("\r\r\n".utf8), lines: [LineShape("", .cr), LineShape("", .crlf)]),
        Case(
            name: "content, CR, then CRLF",
            input: Array("a\r\r\n".utf8),
            lines: [LineShape("a", .cr), LineShape("", .crlf)]
        ),
        Case(name: "two CRs", input: Array("\r\r".utf8), lines: [LineShape("", .cr), LineShape("", .cr)]),
        Case(name: "CRLF then CR", input: Array("\r\n\r".utf8), lines: [LineShape("", .crlf), LineShape("", .cr)]),
        Case(name: "LF then CR", input: Array("\n\r".utf8), lines: [LineShape("", .lf), LineShape("", .cr)]),
        Case(
            name: "LF, CR, then content",
            input: Array("a\n\rb".utf8),
            lines: [LineShape("a", .lf), LineShape("", .cr), LineShape("b", nil)]
        ),
        Case(
            name: "CR-separated tasks are separate lines",
            input: Array("- [ ] x\r- [ ] y".utf8),
            lines: [LineShape("- [ ] x", .cr), LineShape("- [ ] y", nil)]
        ),
        Case(name: "only byte order mark", input: bom, hasByteOrderMark: true, lines: []),
        Case(
            name: "byte order mark and content",
            input: bom + Array("a\nb".utf8),
            hasByteOrderMark: true,
            lines: [LineShape("a", .lf), LineShape("b", nil)]
        ),
        Case(
            name: "byte order mark then LF",
            input: bom + [0x0A],
            hasByteOrderMark: true,
            lines: [LineShape("", .lf)]
        ),
        Case(
            name: "byte order mark then CRLF",
            input: bom + [0x0D, 0x0A],
            hasByteOrderMark: true,
            lines: [LineShape("", .crlf)]
        ),
        Case(
            name: "byte order mark then CR",
            input: bom + [0x0D],
            hasByteOrderMark: true,
            lines: [LineShape("", .cr)]
        ),
        Case(
            name: "second byte order mark is content",
            input: bom + bom + [0x0A],
            hasByteOrderMark: true,
            lines: [LineShape(bom, .lf)]
        ),
        Case(
            name: "byte order mark after the first byte is content",
            input: [0x61] + bom,
            lines: [LineShape([0x61] + bom, nil)]
        ),
        Case(
            name: "incomplete byte order mark is content",
            input: [0xEF, 0xBB],
            lines: [LineShape([0xEF, 0xBB], nil)]
        ),
        Case(
            name: "byte order mark prefix followed by another byte is content",
            input: [0xEF, 0xBB, 0x61, 0x0A],
            lines: [LineShape([0xEF, 0xBB, 0x61], .lf)]
        ),
        Case(
            name: "mixed LF and CRLF",
            input: Array("a\nb\r\nc\n\r\nd".utf8),
            lines: [
                LineShape("a", .lf), LineShape("b", .crlf), LineShape("c", .lf), LineShape("", .crlf),
                LineShape("d", nil),
            ]
        ),
        Case(
            name: "mixed LF, CRLF and CR",
            input: Array("a\rb\nc\r\nd\r\re".utf8),
            lines: [
                LineShape("a", .cr), LineShape("b", .lf), LineShape("c", .crlf), LineShape("d", .cr),
                LineShape("", .cr), LineShape("e", nil),
            ]
        ),
        Case(
            name: "invalid UTF-8 bytes",
            input: [0xFF, 0xFE, 0x0A, 0xC5, 0x0D, 0x0A, 0xF0, 0x9F, 0x0D, 0x61],
            lines: [
                LineShape([0xFF, 0xFE], .lf), LineShape([0xC5], .crlf), LineShape([0xF0, 0x9F], .cr),
                LineShape("a", nil),
            ]
        ),
        Case(name: "NUL bytes", input: [0x00, 0x0A, 0x00], lines: [LineShape([0x00], .lf), LineShape([0x00], nil)]),
        Case(
            name: "other Unicode line breaks are content",
            input: Array("a\u{2028}b\u{2029}c\u{85}d\u{0B}e\u{0C}f\n".utf8),
            lines: [LineShape("a\u{2028}b\u{2029}c\u{85}d\u{0B}e\u{0C}f", .lf)]
        ),
    ]

    @Test(arguments: cases)
    func splitsIntoExpectedLines(testCase: Case) {
        let document = RawDocument(bytes: testCase.input)

        #expect(document.hasByteOrderMark == testCase.hasByteOrderMark)
        #expect(document.lines.map(LineShape.init) == testCase.lines)
        #expect(document.serialized() == testCase.input)
        #expect(losslessViolations(of: testCase.input) == [])
    }

    @Test func lineBytesAreContentFollowedByEnding() {
        let lines = RawDocument(bytes: Array("a\nb\r\nc\rd".utf8)).lines

        #expect(lines.map(\.bytes) == [[0x61, 0x0A], [0x62, 0x0D, 0x0A], [0x63, 0x0D], [0x64]])
    }

    @Test func lineEndingBytes() {
        #expect(LineEnding.lf.bytes == [0x0A])
        #expect(LineEnding.crlf.bytes == [0x0D, 0x0A])
        #expect(LineEnding.cr.bytes == [0x0D])
        #expect(Set(LineEnding.allCases) == [.lf, .crlf, .cr])
    }

    @Test func byteOrderMarkIsNotPartOfTheFirstLine() {
        let document = RawDocument(bytes: Self.bom + Array("---\n".utf8))

        #expect(document.hasByteOrderMark)
        #expect(document.lines.first?.text == "---")
        #expect(document.serialized().starts(with: Self.bom))
    }

    @Test func multiByteCharactersStayWithinTheirLine() {
        // "Ċ" (C4 8A) and "č" (C4 8D) carry continuation bytes that resemble LF and CR.
        let document = RawDocument(bytes: Array("aş\n🛫b\r\nĊč\r🛫\nş".utf8))

        #expect(document.lines.map(\.text) == ["aş", "🛫b", "Ċč", "🛫", "ş"])
        #expect(document.lines.map(\.ending) == [.lf, .crlf, .cr, .lf, nil])
        #expect(document.isValidUTF8)
    }

    @Test func textIsNotNormalized() {
        // Decomposed "ş" (s + combining cedilla) must not be composed while decoding.
        let decomposed: [UInt8] = [0x73, 0xCC, 0xA7]
        let lines = RawDocument(bytes: decomposed).lines

        #expect(lines.map { $0.text.map { Array($0.utf8) } } == [decomposed])
        #expect(lines.map(\.content) == [decomposed])
    }

    @Test func invalidUTF8LineHasNoTextAndMakesTheDocumentReadOnly() {
        let document = RawDocument(bytes: [0x61, 0x0A, 0xFF, 0x0A, 0xC5, 0x9F])

        #expect(document.lines.map(\.text) == ["a", nil, "ş"])
        #expect(!document.isValidUTF8)
        #expect(document.isReadOnly)
    }

    static let illFormedSequences: [[UInt8]] = [
        [0xC5],  // truncated two-byte sequence
        [0xF0, 0x9F, 0x9B],  // truncated four-byte sequence
        [0x9F],  // continuation byte without a lead byte
        [0xC0, 0xAF],  // overlong encoding
        [0xED, 0xA0, 0x80],  // UTF-16 surrogate
        [0xF4, 0x90, 0x80, 0x80],  // beyond U+10FFFF
        [0xFF],
    ]

    @Test(arguments: illFormedSequences)
    func illFormedUTF8HasNoText(content: [UInt8]) {
        let document = RawDocument(bytes: content)

        #expect(document.lines.count == 1)
        #expect(document.lines.first?.text == nil)
        #expect(document.isReadOnly)
        #expect(document.serialized() == content)
    }

    @Test func displayTextEqualsTextForValidContent() {
        let lines = RawDocument(bytes: Array("ş 🛫\r\n\u{FFFD}\n\n".utf8)).lines

        #expect(lines.map(\.displayText) == ["ş 🛫", "\u{FFFD}", ""])
        #expect(lines.map(\.text) == ["ş 🛫", "\u{FFFD}", ""])
    }

    @Test func displayTextReplacesIllFormedBytesAndKeepsTheRest() {
        let bytes: [UInt8] = [0x61, 0xFF, 0x62, 0x0A, 0xC5, 0x9F, 0xC5, 0x0D, 0xFF, 0xFE, 0x0D, 0x0A, 0xC0]
        let lines = RawDocument(bytes: bytes).lines

        #expect(lines.map(\.displayText) == ["a\u{FFFD}b", "ş\u{FFFD}", "\u{FFFD}\u{FFFD}", "\u{FFFD}"])
        #expect(lines.map(\.text) == [nil, nil, nil, nil])
    }

    @Test(arguments: illFormedSequences)
    func displayTextOfIllFormedContentIsOnlyReplacementCharacters(content: [UInt8]) throws {
        let line = try #require(RawDocument(bytes: content).lines.first)

        #expect(!line.displayText.isEmpty)
        #expect(line.displayText.unicodeScalars.allSatisfy { $0 == "\u{FFFD}" })
        #expect(line.content == content)
    }

    @Test func validUTF8DocumentIsWritable() {
        let document = RawDocument(bytes: Array("ş\r\n🛫".utf8))

        #expect(document.isValidUTF8)
        #expect(!document.isReadOnly)
    }

    @Test func emptyDocumentIsWritable() {
        #expect(RawDocument(bytes: []).isValidUTF8)
        #expect(!RawDocument(bytes: Self.bom).isReadOnly)
    }

    @Test(arguments: [
        ("", LineEnding.lf),
        ("a", .lf),
        ("a\n", .lf),
        ("a\r\n", .crlf),
        ("a\r", .cr),
        ("a\r\nb\n", .crlf),
        ("a\r\nb\r", .crlf),
        ("a\nb\r\n", .lf),
        ("a\nb\r", .lf),
        ("a\rb\r\nc\n", .cr),
        ("a\rb", .cr),
    ])
    func newLinesUseTheFirstLineEnding(input: String, expected: LineEnding) {
        #expect(RawDocument(bytes: Array(input.utf8)).lineEndingForNewLines == expected)
    }

    @Test func byteOrderMarkOnlyDocumentUsesLFForNewLines() {
        #expect(RawDocument(bytes: Self.bom).lineEndingForNewLines == .lf)
    }

    @Test func readsFoundationData() {
        let data = Data([0xEF, 0xBB, 0xBF, 0x61, 0x0D, 0x0A])
        let document = RawDocument(bytes: data)

        #expect(document.hasByteOrderMark)
        #expect(document.lines.map(LineShape.init) == [LineShape("a", .crlf)])
        #expect(Data(document.serialized()) == data)
    }

    @Test func documentsReadFromEqualBytesAreEqual() {
        let bytes = Array("a\r\nb".utf8)

        #expect(RawDocument(bytes: bytes) == RawDocument(bytes: bytes))
        #expect(RawDocument(bytes: bytes) != RawDocument(bytes: Array("a\nb".utf8)))
        #expect(RawDocument(bytes: bytes) != RawDocument(bytes: Array("a\rb".utf8)))
        #expect(RawDocument(bytes: bytes) != RawDocument(bytes: Self.bom + bytes))
    }
}
