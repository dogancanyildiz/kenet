import Testing
import VaultFormat

struct SectionModelTests {
    @Test func sectionRangesPartitionBody() throws {
        let document = RawDocument(bytes: "---\ntype: day\n---\nön\n## Tasks\nnot\n## Other\nson\n".utf8)
        let body = document.daySections
        #expect(document.frontmatterLineRange == 0..<3)
        #expect(body.preambleRange == 3..<4)
        #expect(body.sections.map(\.lineRange) == [4..<6, 6..<8])
        let tasks = try #require(body.section(.tasks))
        #expect(tasks.headingLine == 4)
        #expect(tasks.level == 2)
        #expect(body.section(.events) == nil)
    }

    @Test func unreadableFrontmatterReservesItsLines() {
        let document = RawDocument(bytes: "---\ninvalid\n## Tasks\n---\n## Events\n".utf8)
        #expect(document.frontmatter == .unreadable)
        #expect(document.frontmatterLineRange == 0..<4)
        #expect(document.daySections.section(.tasks) == nil)
        #expect(document.daySections.section(.events)?.headingLine == 4)
    }

    @Test func ambiguousOpeningWithoutClosingReservesWholeFile() {
        let document = RawDocument(bytes: "--- \n## Tasks\n".utf8)
        #expect(document.frontmatterLineRange == 0..<2)
        #expect(document.daySections.preambleRange == 2..<2)
        #expect(document.daySections.sections.isEmpty)
    }

    @Test func appendRejectsEmptyListAndLineBreaks() {
        let document = RawDocument(bytes: "## Tasks\n".utf8)
        #expect(throws: EditError.emptySectionAppend) { try document.appendingLines([], toSection: .tasks) }
        #expect(throws: EditError.lineBreakInContent) { try document.appendingLines(["not", "\n"], toSection: .tasks) }
        #expect(throws: EditError.lineBreakInContent) { try document.appendingLines(["\r"], toSection: .journal) }
        #expect(document.serialized() == Array("## Tasks\n".utf8))
    }

    @Test func readOnlyDocumentRejectsAppend() {
        let document = RawDocument(bytes: [0xFF])
        #expect(throws: EditError.readOnlyDocument) { try document.appendingLines(["not"], toSection: .events) }
        #expect(throws: EditError.readOnlyDocument) { try document.appendingLines([], toSection: .tasks) }
    }

    @Test func blankContentIsRefused() {
        let document = RawDocument(bytes: "## Journal\nnot\n".utf8)
        for contents in [[""], [" ", "\t", ""]] {
            #expect(throws: EditError.emptySectionAppend) { try document.appendingLines(contents, toSection: .journal) }
        }
        #expect(document.serialized() == Array("## Journal\nnot\n".utf8))
    }

    @Test func arbitraryBytesHaveLosslessSectionCoverage() {
        var random = SeededGenerator(seed: 0xB17E_5EC7)
        let fragments: [[UInt8]] = [
            Array("## Tasks\n".utf8), Array("## Events\r".utf8), Array("## Journal\r\n".utf8),
            Array("### Notes\n".utf8), Array("~~~\n".utf8), Array("# Other\n".utf8),
            [0xFF, 0x0A], [0x00, 0x0A], [], Array("---\n".utf8),
        ]
        for _ in 0..<300 {
            let bytes = (0..<Int.random(in: 0...30, using: &random)).flatMap { _ in
                fragments.randomElement(using: &random)!
            }
            let document = RawDocument(bytes: bytes)
            let body = document.daySections
            let ranges = [body.preambleRange] + body.sections.map(\.lineRange)
            #expect(
                ranges.flatMap { Array($0) }
                    == Array((document.frontmatterLineRange?.upperBound ?? 0)..<document.lines.count))
            #expect(document.serialized() == bytes)
            #expect(Set(body.sections.compactMap(\.kind)).count == body.sections.compactMap(\.kind).count)
        }
    }
}
