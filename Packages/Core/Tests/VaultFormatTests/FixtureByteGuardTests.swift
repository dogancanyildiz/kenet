import Testing

/// Guards the byte-level properties the round trip fixtures exist to exercise.
///
/// These read the raw files without the model. They turn red if git, an editor or a formatter
/// rewrites a fixture (for example when `Fixtures/** -text` is dropped from `.gitattributes`).
struct FixtureByteGuardTests {
    static func containsCRLF(_ bytes: [UInt8]) -> Bool {
        zip(bytes, bytes.dropFirst()).contains { $0 == 0x0D && $1 == 0x0A }
    }

    static func containsBareLF(_ bytes: [UInt8]) -> Bool {
        bytes.first == 0x0A || zip(bytes, bytes.dropFirst()).contains { $0 != 0x0D && $1 == 0x0A }
    }

    static func containsLoneCR(_ bytes: [UInt8]) -> Bool {
        bytes.last == 0x0D || zip(bytes, bytes.dropFirst()).contains { $0 == 0x0D && $1 != 0x0A }
    }

    @Test func crlfFixtureUsesOnlyCRLF() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/crlf.md")

        #expect(Self.containsCRLF(bytes))
        #expect(!Self.containsBareLF(bytes))
        #expect(!Self.containsLoneCR(bytes))
    }

    @Test func crFixtureUsesOnlyCR() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/cr.md")

        #expect(bytes.count { $0 == 0x0D } >= 2)
        #expect(!bytes.contains(0x0A))
        #expect(bytes.last == 0x0D)
    }

    @Test func bomFixtureStartsWithByteOrderMark() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/bom.md")

        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(bytes.count > 3)
    }

    @Test func noFinalNewlineFixtureEndsWithoutLineEnding() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/no-final-newline.md")

        #expect(!bytes.isEmpty)
        #expect(bytes.last != 0x0A)
        #expect(bytes.last != 0x0D)
        #expect(bytes.contains(0x0A))
    }

    @Test func mixedLineEndingsFixtureHasAllThreeEndings() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/mixed-line-endings.md")

        #expect(Self.containsCRLF(bytes))
        #expect(Self.containsBareLF(bytes))
        #expect(Self.containsLoneCR(bytes))
    }

    @Test func emptyFixtureHasNoBytes() throws {
        #expect(try Fixtures.bytes(at: "roundtrip/empty.md").isEmpty)
    }

    @Test func invalidUTF8FixtureIsNotValidUTF8() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/invalid-utf8.md")

        #expect(!ReferenceModel.isValidUTF8(bytes))
        #expect(bytes.contains(0xFF))
    }

    @Test func dayFixtureIsPlainUTF8WithLFEndings() throws {
        let bytes = try Fixtures.bytes(at: "roundtrip/day-basic.md")

        #expect(ReferenceModel.isValidUTF8(bytes))
        #expect(!bytes.contains(0x0D))
        #expect(bytes.last == 0x0A)
        #expect(Array(bytes.prefix(4)) == Array("---\n".utf8))
    }
}
