import Testing
import VaultFormat

/// Parts of the frontmatter model that fixtures cannot express: typed accessors and lookups.
struct FrontmatterModelTests {
    static func frontmatter(_ text: String) throws -> Frontmatter {
        guard case .parsed(let frontmatter) = RawDocument(bytes: Array(text.utf8)).frontmatter else {
            throw FixtureError.unreadable(path: text, reason: "the frontmatter is not parsed")
        }
        return frontmatter
    }

    static func scalar(_ spelling: String) throws -> FrontmatterScalar {
        guard case .scalar(let scalar) = try frontmatter("---\na: \(spelling)\n---\n").field(named: "a")?.value else {
            throw FixtureError.unreadable(path: spelling, reason: "the value is not a scalar")
        }
        return scalar
    }

    @Test(
        arguments: [
            ("25", 25, 25.0), ("-3", -3, -3.0), ("+5", 5, 5.0), ("0", 0, 0.0), ("-0", 0, 0.0),
            ("29.0290", nil, 29.029), ("-0.25", nil, -0.25), ("0.5", nil, 0.5),
            ("99999999999999999999", nil, 1e20),
        ] as [(String, Int?, Double)])
    func numberHasItsValue(spelling: String, integer: Int?, double: Double) throws {
        let scalar = try Self.scalar(spelling)

        #expect(scalar.kind == .number)
        #expect(scalar.raw == spelling)
        #expect(scalar.integerValue == integer)
        #expect(scalar.doubleValue == double)
    }

    @Test(arguments: [
        "012", "0x1F", "0o17", ".5", "5.", "1_000", "1e3", "1E3", "1e-5", "1.0e5", "--1", "+-1", "1.5.2", ".inf", "NaN",
        "12:30", "١٢",
        "\"25\"", "'25'", "yes", "no", "on", "off", "tRUE", "Yes", "25 elma", "2026-13-01", "2026-02-30", "2026-1-2",
        "2026-10-02T10:00",
    ])
    func uncertainSpellingIsText(spelling: String) throws {
        let scalar = try Self.scalar(spelling)

        #expect(scalar.kind == .text)
        #expect(scalar.integerValue == nil)
        #expect(scalar.doubleValue == nil)
    }

    @Test func booleansAndEmptyValuesAreRecognizedInTheirYAMLSpellings() throws {
        for spelling in ["true", "True", "TRUE"] { #expect(try Self.scalar(spelling).kind == .boolean(true)) }
        for spelling in ["false", "False", "FALSE"] { #expect(try Self.scalar(spelling).kind == .boolean(false)) }
        for spelling in ["", "~", "null", "Null", "NULL", "# yorum"] {
            let scalar = try Self.scalar(spelling)
            #expect(scalar.kind == .empty)
            #expect(scalar.text == "")
        }
        #expect(try Self.scalar("2024-02-29").kind == .date(try #require(CalendarDate(year: 2024, month: 2, day: 29))))
    }

    @Test func lookupComparesKeysByteForByte() throws {
        let composed = "do\u{11F}um"
        let decomposed = "dog\u{306}um"
        let frontmatter = try Self.frontmatter("---\nname: ilk\n\(decomposed): 1\n\(composed): 2\n---\n")

        #expect(composed == decomposed, "Swift compares the two spellings as equal; the vault does not")
        #expect(frontmatter.fields.count == 3)
        #expect(frontmatter.field(named: "name")?.lineRange == 1..<2)
        #expect(frontmatter.field(named: decomposed)?.lineRange == 2..<3)
        #expect(frontmatter.field(named: composed)?.lineRange == 3..<4)
        #expect(frontmatter.field(named: "Name") == nil)
    }

    @Test func keyThatOccursTwiceMakesTheBlockUnreadable() {
        for text in ["---\na: 1\nb: 2\na: 3\n---\n", "---\n\"a\": 1\n'a': 2\n---\n", "---\ng:\n  a: 1\n  a: 2\n---\n"] {
            #expect(RawDocument(bytes: Array(text.utf8)).frontmatter == .unreadable, "\(text.debugDescription)")
        }
    }

    @Test func listItemsSeeASingleValueAsAListOfOne() throws {
        let frontmatter = try Self.frontmatter(
            "---\na: tek\nb:\nc: [x, y]\nd:\n  - z\ne:\n  k: v\nf: |\n  metin\ng: ~\n---\n"
        )

        #expect(frontmatter.field(named: "a")?.value.listItems?.map(\.text) == ["tek"])
        #expect(frontmatter.field(named: "b")?.value.listItems?.map(\.text) == [])
        #expect(frontmatter.field(named: "c")?.value.listItems?.map(\.text) == ["x", "y"])
        #expect(frontmatter.field(named: "d")?.value.listItems?.map(\.text) == ["z"])
        #expect(frontmatter.field(named: "e")?.value.listItems == nil)
        #expect(frontmatter.field(named: "f")?.value.listItems == nil)
        #expect(frontmatter.field(named: "g")?.value.listItems?.map(\.text) == [])
    }

    @Test func calendarDateAcceptsOnlyDaysThatExist() throws {
        #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil)
        #expect(CalendarDate(year: 2023, month: 2, day: 29) == nil)
        #expect(CalendarDate(year: 1900, month: 2, day: 29) == nil)
        #expect(CalendarDate(year: 2000, month: 2, day: 29) != nil)
        #expect(CalendarDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CalendarDate(year: 2026, month: 12, day: 31) != nil)
        #expect(CalendarDate(year: 2026, month: 13, day: 1) == nil)
        #expect(CalendarDate(year: 2026, month: 0, day: 1) == nil)
        #expect(CalendarDate(year: 2026, month: 1, day: 0) == nil)
        #expect(CalendarDate(year: 99, month: 12, day: 31) == nil)
        #expect(CalendarDate(year: 100, month: 1, day: 1) != nil)
        #expect(CalendarDate(year: 10000, month: 1, day: 1) == nil)
    }

    @Test func calendarDateIsWrittenAndParsedAsYearMonthDay() throws {
        let date = try #require(CalendarDate("2026-10-02"))

        #expect((date.year, date.month, date.day) == (2026, 10, 2))
        #expect(date.description == "2026-10-02")
        #expect(try #require(CalendarDate(year: 307, month: 3, day: 9)).description == "0307-03-09")
        #expect(CalendarDate("0099-01-01") == nil)
        for text in [
            "2026-10-2", "2026-10-02 ", " 2026-10-02", "2026/10/02", "26-10-02", "2026-10-0２", "", "2026-10-021",
        ] {
            #expect(CalendarDate(text) == nil, "\(text)")
        }
    }

    @Test func calendarDatesAreOrderedByDay() throws {
        let dates = try ["2026-10-02", "2025-12-31", "2026-09-30", "2026-10-01"].map { try #require(CalendarDate($0)) }

        #expect(dates.sorted().map(\.description) == ["2025-12-31", "2026-09-30", "2026-10-01", "2026-10-02"])
    }
}
