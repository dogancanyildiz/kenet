import Testing

@testable import VaultFormat

/// The invariants of the single primitive every document change goes through.
struct LineEditingTests {
    static func document(_ text: String) -> RawDocument {
        RawDocument(bytes: Array(text.utf8))
    }

    static func text(_ document: RawDocument) -> String {
        String(decoding: document.serialized(), as: UTF8.self)
    }

    @Test func replacedLineKeepsItsOwnEndingAndOtherLinesKeepTheirBytes() throws {
        let document = Self.document("bir\r\niki\nüç\rdört")
        let edited = try document.replacingLines(in: 1..<2, with: ["İKİ"])

        #expect(Self.text(edited) == "bir\r\nİKİ\nüç\rdört")
        #expect(edited.lines[0] == document.lines[0])
        #expect(edited.lines[2...] == document.lines[2...])
    }

    @Test(arguments: [("a\nb\r\n", "\n"), ("a\r\nb\n", "\r\n"), ("a\rb\n", "\r"), ("a", "\n"), ("", "\n")])
    func addedLinesEndWithTheFirstLineEndingOfTheFile(text: String, ending: String) throws {
        let document = Self.document(text)
        let edited = try document.replacingLines(in: document.lines.count..<document.lines.count, with: ["x", "y"])

        #expect(Self.text(edited).hasSuffix("x" + ending + "y" + ending))
    }

    @Test func unterminatedLastLineIsTerminatedBeforeLinesAreAddedAfterIt() throws {
        let edited = try Self.document("a\r\nb").replacingLines(in: 2..<2, with: ["c"])

        #expect(Self.text(edited) == "a\r\nb\r\nc\r\n")
    }

    @Test func fileWithoutAnyLineEndingGetsLineFeeds() throws {
        let edited = try Self.document("a").replacingLines(in: 1..<1, with: ["b"])

        #expect(Self.text(edited) == "a\nb\n")
    }

    @Test func linesAddedBeforeAnUnterminatedLastLineLeaveItUnterminated() throws {
        let edited = try Self.document("a\nb").replacingLines(in: 1..<1, with: ["x"])

        #expect(Self.text(edited) == "a\nx\nb")
    }

    @Test func replacementOfAnUnterminatedLastLineStaysUnterminated() throws {
        let edited = try Self.document("a\nb").replacingLines(in: 1..<2, with: ["c"])

        #expect(Self.text(edited) == "a\nc")
        #expect(edited.lines.last?.ending == nil)
    }

    @Test func unterminatedLineIsNeverLeftEmptyOrInTheMiddle() throws {
        let document = Self.document("a\nb")

        #expect(Self.text(try document.replacingLines(in: 1..<2, with: [""])) == "a\n\n")
        #expect(Self.text(try document.replacingLines(in: 1..<2, with: ["c", "d"])) == "a\nc\nd\n")
        #expect(Self.text(try document.replacingLines(in: 1..<2, with: [])) == "a\n")
    }

    @Test func contentWithALineBreakIsRefused() {
        let document = Self.document("a\n")

        for content in ["x\ny", "x\ry", "x\r\ny", "\n", "\r"] {
            #expect(throws: EditError.lineBreakInContent) {
                try document.replacingLines(in: 0..<1, with: ["ok", content])
            }
        }
    }

    @Test func rangeOutsideTheDocumentIsRefused() {
        let document = Self.document("a\nb\n")

        #expect(throws: EditError.invalidLineRange) { try document.replacingLines(in: 1..<3, with: []) }
        #expect(throws: EditError.invalidLineRange) { try document.replacingLines(in: 3..<3, with: ["x"]) }
        #expect(throws: EditError.invalidLineRange) { try document.replacingLines(in: -1..<1, with: ["x"]) }
    }

    @Test func readOnlyDocumentIsRefused() {
        let document = RawDocument(bytes: [0x61, 0x0A, 0xFF, 0x0A])

        #expect(document.isReadOnly)
        #expect(throws: EditError.readOnlyDocument) { try document.replacingLines(in: 0..<1, with: ["x"]) }
        #expect(throws: EditError.readOnlyDocument) { try document.replacingLines(in: 0..<0, with: []) }
        #expect(throws: EditError.readOnlyDocument) { try document.applying([]) }
    }

    @Test func byteOrderMarkStaysInFrontWhenLinesAreAddedAtTheStart() throws {
        let document = RawDocument(bytes: [0xEF, 0xBB, 0xBF] + Array("a\n".utf8))
        let edited = try document.replacingLines(in: 0..<0, with: ["x"])

        #expect(edited.serialized() == [0xEF, 0xBB, 0xBF] + Array("x\na\n".utf8))
        #expect(edited.hasByteOrderMark)
        #expect(edited.lines.first?.text == "x")
    }

    @Test func byteOrderMarkStaysWhenEveryLineIsRemoved() throws {
        let document = RawDocument(bytes: [0xEF, 0xBB, 0xBF] + Array("a\n".utf8))
        let edited = try document.replacingLines(in: 0..<1, with: [])

        #expect(edited.serialized() == [0xEF, 0xBB, 0xBF])
        #expect(edited.lines.isEmpty)
    }

    @Test func firstLineThatStartsWithTheMarkBytesMakesADocumentWithAByteOrderMark() throws {
        let inserted = try Self.document("a\n").replacingLines(in: 0..<0, with: ["\u{FEFF}x"])
        #expect(inserted.hasByteOrderMark)
        #expect(inserted.lines.map(\.text) == ["x", "a"])
        #expect(inserted == RawDocument(bytes: inserted.serialized()))

        let exposed = try Self.document("a\n\u{FEFF}").replacingLines(in: 0..<1, with: [])
        #expect(exposed.hasByteOrderMark)
        #expect(exposed.lines.isEmpty)
        #expect(exposed == RawDocument(bytes: exposed.serialized()))
    }

    @Test func carriageReturnBeforeAnEmptyLineFeedLineBecomesOneEnding() throws {
        // Removing "b" leaves the bytes CR LF next to each other, which a file reads as CRLF.
        let removed = try Self.document("a\rb\n\nc\n").replacingLines(in: 1..<2, with: [])
        #expect(Self.text(removed) == "a\r\nc\n")
        #expect(removed.lines.map(\.ending) == [.crlf, .lf])
        #expect(removed == RawDocument(bytes: removed.serialized()))

        // The same seam after an added line, and between a rewritten line and the next one.
        let added = try Self.document("x\ra\n\n").replacingLines(in: 1..<2, with: ["b", "c"])
        #expect(added == RawDocument(bytes: added.serialized()))
        let inserted = try Self.document("x\n\ny\r").replacingLines(in: 3..<3, with: [""])
        #expect(inserted == RawDocument(bytes: inserted.serialized()))
        let rewritten = try Self.document("a\r\n\nb\rc\n\n").replacingLines(in: 2..<4, with: ["d"])
        #expect(Self.text(rewritten) == "a\r\n\nd\r\n")
        #expect(rewritten == RawDocument(bytes: rewritten.serialized()))
    }

    @Test func removingSeveralLinesNeverDropsAByteOfAnUntouchedLine() throws {
        // Lines 1 to 3 go. The CR of line 0 and the LF of the empty line 4 then read as one CRLF;
        // both bytes must still be there.
        let document = Self.document("---\rl:\r  - x\r  - y\n\n---\n")
        let edited = try document.applying([.removing(line: 1), .removing(line: 2), .removing(line: 3)])

        #expect(Self.text(edited) == "---\r\n---\n")
        #expect(edited.lines.map(\.ending) == [.crlf, .lf])
        #expect(edited == RawDocument(bytes: edited.serialized()))
    }

    @Test func emptyDocumentAcceptsLines() throws {
        let edited = try Self.document("").replacingLines(in: 0..<0, with: ["a", "", "b"])

        #expect(Self.text(edited) == "a\n\nb\n")
    }

    @Test func emptyEditReturnsTheSameDocument() throws {
        let document = Self.document("a\r\nb")

        #expect(try document.replacingLines(in: 1..<1, with: []) == document)
        #expect(try document.applying([]) == document)
    }

    @Test func batchedEditsReferToTheOriginalLines() throws {
        let document = Self.document("0\n1\n2\n3\n4\n")
        let edited = try document.applying([
            .replacing(line: 1, with: "bir"),
            .removing(line: 3),
            .inserting(["yeni"], at: 5),
            .inserting(["a", "b"], at: 2),
        ])

        #expect(Self.text(edited) == "0\nbir\na\nb\n2\n4\nyeni\n")
    }

    @Test func insertionAtAReplacedLineLandsBeforeIt() throws {
        let document = Self.document("0\n1\n")
        let edited = try document.applying([.replacing(line: 1, with: "bir"), .inserting(["yeni"], at: 1)])

        #expect(Self.text(edited) == "0\nyeni\nbir\n")
    }

    @Test func overlappingBatchedEditsAreRefused() {
        let document = Self.document("0\n1\n2\n")

        #expect(throws: EditError.invalidLineRange) {
            try document.applying([LineEdit(range: 0..<2, contents: []), .replacing(line: 1, with: "x")])
        }
        #expect(throws: EditError.invalidLineRange) {
            try document.applying([.removing(line: 3)])
        }
    }
}
