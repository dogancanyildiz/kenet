import Testing
import VaultFormat

/// Every Markdown fixture, and inputs derived from it, must survive read and serialize unchanged.
struct RoundTripTests {
    enum Variant: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case everyEndingAsLF
        case everyEndingAsCRLF
        case everyEndingAsCR
        case byteOrderMarkPrepended
        case finalLineEndingRemoved

        var testDescription: String { rawValue }

        func apply(to bytes: [UInt8]) -> [UInt8] {
            switch self {
            case .everyEndingAsLF:
                return ReferenceModel.bytes(bytes, withEveryEndingAs: .lf)
            case .everyEndingAsCRLF:
                return ReferenceModel.bytes(bytes, withEveryEndingAs: .crlf)
            case .everyEndingAsCR:
                return ReferenceModel.bytes(bytes, withEveryEndingAs: .cr)
            case .byteOrderMarkPrepended:
                return [0xEF, 0xBB, 0xBF] + bytes
            case .finalLineEndingRemoved:
                if bytes.last == 0x0D { return Array(bytes.dropLast()) }
                guard bytes.last == 0x0A else { return bytes }
                let withoutLF = bytes.dropLast()
                return Array(withoutLF.last == 0x0D ? withoutLF.dropLast() : withoutLF)
            }
        }
    }

    /// Files up to this size are cut at every byte position; larger ones at evenly spaced positions.
    static let exhaustiveTruncationLimit = 1024
    static let sampledTruncationCount = 256

    static func truncationLengths(for count: Int) -> [Int] {
        guard count > exhaustiveTruncationLimit else { return Array(0...count) }
        return (0...sampledTruncationCount).map { $0 * count / sampledTruncationCount }
    }

    @Test func fixturesExist() throws {
        #expect(try !Fixtures.markdownPaths().isEmpty)
        #expect(try !Fixtures.markdownPaths(in: "roundtrip").isEmpty)
    }

    @Test(arguments: try Fixtures.markdownPaths())
    func fixtureRoundTrips(path: String) throws {
        let input = try Fixtures.bytes(at: path)

        #expect(RawDocument(bytes: input).serialized() == input)
        #expect(losslessViolations(of: input) == [])
    }

    @Test(arguments: try Fixtures.markdownPaths(), Variant.allCases)
    func derivedInputRoundTrips(path: String, variant: Variant) throws {
        let original = try Fixtures.bytes(at: path)
        let input = variant.apply(to: original)
        let document = RawDocument(bytes: input)

        #expect(document.serialized() == input)
        #expect(losslessViolations(of: input) == [])

        switch variant {
        case .everyEndingAsLF:
            expectEveryEnding(.lf, in: document, derivedFrom: original)
        case .everyEndingAsCRLF:
            expectEveryEnding(.crlf, in: document, derivedFrom: original)
        case .everyEndingAsCR:
            expectEveryEnding(.cr, in: document, derivedFrom: original)
        case .byteOrderMarkPrepended:
            #expect(document.hasByteOrderMark)
            if !RawDocument(bytes: original).hasByteOrderMark {
                #expect(document.lines == RawDocument(bytes: original).lines)
            }
        case .finalLineEndingRemoved:
            // The last line loses its ending; when it had no content, nothing of it remains.
            var expected = RawDocument(bytes: original).lines.map(LineShape.init)
            if let last = expected.popLast(), !last.content.isEmpty || last.ending == nil {
                expected.append(LineShape(last.content, nil))
            }
            #expect(document.lines.map(LineShape.init) == expected)
        }
    }

    /// Changing the kind of line ending must change nothing but the endings.
    private func expectEveryEnding(_ ending: LineEnding, in document: RawDocument, derivedFrom original: [UInt8]) {
        let originalLines = RawDocument(bytes: original).lines

        #expect(document.lines.map(\.content) == originalLines.map(\.content))
        #expect(document.lines.map(\.ending) == originalLines.map { $0.ending == nil ? nil : ending })
        #expect(document.hasByteOrderMark == RawDocument(bytes: original).hasByteOrderMark)
        if originalLines.contains(where: { $0.ending != nil }) {
            #expect(document.lineEndingForNewLines == ending)
        }
    }

    @Test(arguments: try Fixtures.markdownPaths())
    func truncatedInputRoundTrips(path: String) throws {
        let original = try Fixtures.bytes(at: path)

        for length in Self.truncationLengths(for: original.count) {
            let input = Array(original.prefix(length))
            let violations = losslessViolations(of: input)
            #expect(violations == [], "truncated to \(length) of \(original.count) bytes")
            if !violations.isEmpty { break }
        }
    }

    @Test func truncationCoversEveryPositionOfSmallFilesAndSamplesLargeOnes() {
        #expect(Self.truncationLengths(for: 0) == [0])
        #expect(Self.truncationLengths(for: 3) == [0, 1, 2, 3])
        #expect(Self.truncationLengths(for: 1024).count == 1025)

        let sampled = Self.truncationLengths(for: 100_000)
        #expect(sampled.count == 257)
        #expect(sampled.first == 0)
        #expect(sampled.last == 100_000)
    }
}
