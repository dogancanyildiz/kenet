import Testing
import VaultFormat

/// Arbitrary bytes must be read without crashing and serialized back unchanged.
///
/// The generator is seeded with a constant, so every run checks exactly the same inputs.
struct RandomInputTests {
    static let seed: UInt64 = 0x6A6F_7572_6E61_6C21
    static let iterations = 3000

    /// Bytes that matter to the splitter, so that short inputs hit the edge cases often.
    static let interestingBytes: [UInt8] = [
        0x0A, 0x0A, 0x0D, 0x0D,  // LF, CR
        0xEF, 0xBB, 0xBF,  // byte order mark
        0x61, 0x20, 0x00,  // ASCII and NUL
        0xC5, 0x9F,  // "ş"
        0xF0, 0x9F, 0x9B, 0xAB,  // "🛫"
        0xFF, 0xC0, 0x8A, 0x8D,  // never valid, overlong lead, continuation bytes
    ]

    @Test func uniformRandomBytesRoundTrip() {
        var generator = SeededGenerator(seed: Self.seed)

        for iteration in 0..<Self.iterations {
            let count = Int.random(in: 0...96, using: &generator)
            let input = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let violations = losslessViolations(of: input)
            #expect(violations == [], "iteration \(iteration)")
            if !violations.isEmpty { break }
        }
    }

    @Test func lineEndingHeavyRandomBytesRoundTrip() throws {
        var generator = SeededGenerator(seed: Self.seed ^ 0xFFFF_FFFF)
        var sawCRLF = false
        var sawCR = false
        var sawByteOrderMark = false
        var sawUnterminatedTail = false
        var sawInvalidUTF8 = false

        for iteration in 0..<Self.iterations {
            let count = Int.random(in: 0...48, using: &generator)
            var input: [UInt8] = []
            for _ in 0..<count {
                input.append(try #require(Self.interestingBytes.randomElement(using: &generator)))
            }
            if iteration % 8 == 0 {
                input = [0xEF, 0xBB, 0xBF] + input
            }

            let violations = losslessViolations(of: input)
            #expect(violations == [], "iteration \(iteration)")
            if !violations.isEmpty { break }

            let document = RawDocument(bytes: input)
            sawCRLF = sawCRLF || document.lines.contains { $0.ending == .crlf }
            sawCR = sawCR || document.lines.contains { $0.ending == .cr }
            sawByteOrderMark = sawByteOrderMark || document.hasByteOrderMark
            sawUnterminatedTail = sawUnterminatedTail || document.lines.last.map { $0.ending == nil } == true
            sawInvalidUTF8 = sawInvalidUTF8 || document.isReadOnly
        }

        // The generator must actually reach the cases this test exists for.
        #expect(sawCRLF && sawCR && sawByteOrderMark && sawUnterminatedTail && sawInvalidUTF8)
    }

    @Test func generatorIsDeterministic() {
        var first = SeededGenerator(seed: Self.seed)
        var second = SeededGenerator(seed: Self.seed)

        #expect((0..<16).map { _ in first.next() } == (0..<16).map { _ in second.next() })
    }
}
