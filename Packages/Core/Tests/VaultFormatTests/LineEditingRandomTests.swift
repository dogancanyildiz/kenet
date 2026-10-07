import Testing

@testable import VaultFormat

/// Random documents and random line replacements, checked against the byte-level reference.
///
/// The generator is seeded with a constant, so every run checks exactly the same cases.
struct LineEditingRandomTests {
    static let seed: UInt64 = 0x6C69_6E65_6564_6974
    static let iterations = 6000

    static let contents = ["", "a", "ş", "- [ ] iş 📅", " ", "\u{FEFF}", "\u{FEFF}x", "---", "a: b"]
    static let endings = ["\n", "\n", "\r\n", "\r", ""]

    static func randomDocument(using generator: inout SeededGenerator) -> [UInt8] {
        var text = Int.random(in: 0..<6, using: &generator) == 0 ? "\u{FEFF}" : ""
        for _ in 0..<Int.random(in: 0...7, using: &generator) {
            text += contents.randomElement(using: &generator) ?? ""
            text += endings.randomElement(using: &generator) ?? ""
        }
        return Array(text.utf8)
    }

    @Test func randomReplacementsKeepEveryInvariant() throws {
        var generator = SeededGenerator(seed: Self.seed)
        var sawJoinedEndings = false
        var sawNewByteOrderMark = false
        var sawTerminatedTail = false
        var sawUnterminatedTail = false
        var sawEndings: Set<LineEnding> = []

        for iteration in 0..<Self.iterations {
            let input = Self.randomDocument(using: &generator)
            let document = RawDocument(bytes: input)
            let lower = Int.random(in: 0...document.lines.count, using: &generator)
            let upper = Int.random(in: lower...min(document.lines.count, lower + 3), using: &generator)
            let contents = (0..<Int.random(in: 0...3, using: &generator)).map { _ in
                Self.contents.randomElement(using: &generator) ?? ""
            }

            let edited = try document.replacingLines(in: lower..<upper, with: contents)
            let output = edited.serialized()
            let context: Comment = "iteration \(iteration): \(hex(input)) replacing \(lower..<upper) with \(contents)"

            // The bytes are the untouched bytes around the new lines, as the reference builds them.
            let expected = ReferenceEdit.bytes(input, replacing: lower..<upper, with: contents.map { Array($0.utf8) })
            #expect(output == expected, context)

            // Reading the bytes gives the edited document, which holds every structural invariant.
            #expect(RawDocument(bytes: output) == edited, context)
            #expect(losslessViolations(of: output) == [], context)
            #expect(!edited.isReadOnly, context)

            // Untouched lines keep their bytes, and the mark stays in front.
            let mark = document.hasByteOrderMark ? RawDocument.byteOrderMark : []
            let before = mark + document.lines[..<lower].flatMap(\.bytes)
            let after = Array(document.lines[upper...].flatMap(\.bytes))
            #expect(output.starts(with: before), context)
            #expect(output.suffix(after.count) == after[...], context)
            #expect(output.count >= before.count + after.count, context)
            if document.hasByteOrderMark { #expect(edited.hasByteOrderMark, context) }

            if output != expected || RawDocument(bytes: output) != edited { break }

            let naiveCount = document.lines.count - (upper - lower) + contents.count
            sawJoinedEndings =
                sawJoinedEndings || (edited.lines.count < naiveCount && edited.lines.contains { $0.ending == .crlf })
            sawNewByteOrderMark = sawNewByteOrderMark || (edited.hasByteOrderMark && !document.hasByteOrderMark)
            sawUnterminatedTail = sawUnterminatedTail || edited.lines.last.map { $0.ending == nil } == true
            if document.lines.last.map({ $0.ending == nil }) == true, lower == document.lines.count, !contents.isEmpty {
                sawTerminatedTail = true
            }
            if upper == lower, !contents.isEmpty { sawEndings.insert(document.lineEndingForNewLines) }
        }

        // The generator must actually reach the cases this test exists for.
        #expect(sawJoinedEndings && sawNewByteOrderMark && sawTerminatedTail && sawUnterminatedTail)
        #expect(sawEndings == [.lf, .crlf, .cr])
    }

    @Test func randomBatchesKeepEveryByteOfUntouchedLines() throws {
        var generator = SeededGenerator(seed: Self.seed ^ 0xFFFF)
        var sawJoinedEndings = false

        for iteration in 0..<4000 {
            let input = Self.randomDocument(using: &generator)
            let document = RawDocument(bytes: input)
            // One edit per line at most, so ranges never overlap; insertions may go anywhere.
            var edits: [LineEdit] = []
            for line in 0..<document.lines.count where Bool.random(using: &generator) {
                let content = Self.contents.randomElement(using: &generator) ?? ""
                edits.append(
                    Bool.random(using: &generator) ? .removing(line: line) : .replacing(line: line, with: content))
            }
            if Bool.random(using: &generator) {
                let position = Int.random(in: 0...document.lines.count, using: &generator)
                edits.append(.inserting([Self.contents.randomElement(using: &generator) ?? ""], at: position))
            }

            let expected = ReferenceEdit.bytes(
                input,
                applying: edits.map { edit in
                    ReferenceEdit.Replacement(range: edit.range, contents: edit.contents.map { Array($0.utf8) })
                }
            )
            let edited = try document.applying(edits.shuffled(using: &generator))
            let context: Comment = "iteration \(iteration): \(hex(input)) with \(edits)"

            #expect(edited.serialized() == expected, context)
            #expect(RawDocument(bytes: expected) == edited, context)
            #expect(losslessViolations(of: expected) == [], context)

            // Every byte of a line no edit names is still there, in order.
            var untouched: [UInt8] = []
            for (line, raw) in document.lines.enumerated() where !edits.contains(where: { $0.range.contains(line) }) {
                untouched += raw.bytes
            }
            #expect(isSubsequence(untouched, of: expected), context)
            if edited.serialized() != expected || !isSubsequence(untouched, of: expected) { break }

            let naiveCount = document.lines.count + edits.reduce(0) { $0 + $1.contents.count - $1.range.count }
            sawJoinedEndings = sawJoinedEndings || edited.lines.count < naiveCount
        }

        #expect(sawJoinedEndings)
    }
}

/// Whether every element of the first sequence appears in the second in the same order.
func isSubsequence(_ needle: [UInt8], of haystack: [UInt8]) -> Bool {
    var position = 0
    for byte in haystack where position < needle.count && needle[position] == byte {
        position += 1
    }
    return position == needle.count
}
