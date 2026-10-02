import Testing
import VaultFormat

/// Ties the document model to what each named fixture is meant to demonstrate.
struct FixtureModelTests {
    static func document(_ name: String) throws -> RawDocument {
        RawDocument(bytes: try Fixtures.bytes(at: "roundtrip/\(name).md"))
    }

    @Test func crlfFixture() throws {
        let document = try Self.document("crlf")

        #expect(document.lines.count == 6)
        #expect(document.lines.allSatisfy { $0.ending == .crlf })
        #expect(document.lines.first?.text == "## Events")
        #expect(document.lineEndingForNewLines == .crlf)
        #expect(!document.isReadOnly)
    }

    @Test func crFixture() throws {
        let document = try Self.document("cr")

        #expect(document.lines.map(\.ending) == [.cr, .cr, .cr])
        #expect(document.lines.first?.text == "## Tasks")
        #expect(document.lines.last?.text == "- [x] Rapor gönderildi ✅ 2026-10-02 ^c4r5d6")
        #expect(document.lineEndingForNewLines == .cr)
        #expect(!document.isReadOnly)
    }

    @Test func bomFixture() throws {
        let document = try Self.document("bom")

        #expect(document.hasByteOrderMark)
        #expect(document.lines.first?.text == "---")
        #expect(document.lines.last?.text == "Bu dosya BOM ile başlar.")
        #expect(!document.isReadOnly)
    }

    @Test func noFinalNewlineFixture() throws {
        let document = try Self.document("no-final-newline")

        #expect(document.lines.map(\.ending) == [.lf, .lf, nil])
        #expect(document.lines.last?.text == "- [[Deniz Arıkan]] ile öğle yemeği")
    }

    @Test func mixedLineEndingsFixture() throws {
        let document = try Self.document("mixed-line-endings")

        #expect(document.lines.map(\.ending) == [.crlf, .lf, .cr, .lf, .crlf, .lf, .cr, .crlf])
        #expect(
            document.lines.map(\.text) == [
                "ilk satır CRLF ile biter", "ikinci satır LF ile biter", "üçüncü satır CR ile biter",
                "dördüncü satır LF ile biter", "", "", "", "son satır CRLF ile biter",
            ]
        )
        #expect(document.lineEndingForNewLines == .crlf)
    }

    @Test func emptyFixture() throws {
        let document = try Self.document("empty")

        #expect(document.lines.isEmpty)
        #expect(!document.hasByteOrderMark)
        #expect(document.lineEndingForNewLines == .lf)
        #expect(!document.isReadOnly)
    }

    @Test func invalidUTF8Fixture() throws {
        let document = try Self.document("invalid-utf8")

        #expect(document.isReadOnly)
        #expect(
            document.lines.map(\.text) == [
                "## Journal", "Geçerli satır: ş 🛫", nil, nil, "Sonraki satır geçerli",
            ]
        )
    }

    @Test func dayFixture() throws {
        let document = try Self.document("day-basic")

        #expect(document.lines.count == 19)
        #expect(document.lines.allSatisfy { $0.ending == .lf })
        #expect(document.lines.first?.text == "---")
        #expect(
            document.lines.dropFirst(9).first?.text == "- [ ] [[Deniz Arıkan]]'a teklifi gönder 📅 2026-10-05 ^k7m2p9"
        )
        #expect(!document.hasByteOrderMark)
        #expect(!document.isReadOnly)
    }
}
