import Testing
import VaultFormat

/// Whatever is written must read back as the same value, however awkward the text.
struct FrontmatterWriteRoundTripTests {
    /// Text that means something else to YAML unless it is quoted or escaped, and text that
    /// must survive untouched.
    static let hardTexts: [String] = [
        "a: b", "a:b", "sonda iki nokta:", ": başta iki nokta", ":", "#etiket", "a #b", "a#b", "#", "[[Liman Ofis]]",
        "[a]", "a]b", "{a}", "a, b", "a,b", ",", "- madde", "-", "-5", "--- ", "---", "...", "\"tırnak\"", "'tek'",
        "Deniz'in", "it's \"x\"", "\"", "'", " baştaki boşluk", "sondaki boşluk ", " ", "\tsekme", "a\tb", "true",
        "True", "TRUE", "false", "yes", "No", "on", "OFF", "y", "N", "null", "Null", "~", "123", "+5", "1.5", "1e5",
        "0x1F", "0o17", "012", ".5", "5.", ".inf", "-.INF", ".NaN", "1_000", "12:30", "1:30:00", "2026-10-02",
        "2026-10-02T10:00:00", "2026-10-02 10:00:00", "2001-12-14 21:59:43.10 -5", "2026-1-2", "2026-13-45",
        "0001-01-01", "", "çğıöşü ÇĞİÖŞÜ", "😀 emoji 👨‍👩‍👧", "satır\nsonu", "cr\rlf\r\n",
        "\n", "\u{0}", "\u{7}zil", "\u{7F}", "\u{85}", "\u{A0}bölünmez", "\u{2028}", "\u{2029}", "\u{FEFF}bom",
        "\\ters", "a\\nb", "\\", "*yıldız", "&çapa", "!etiket", "|boru", ">büyük", "%yüzde", "@at", "`ters tırnak`",
        "?soru", "? soru", "=", "<<", "a  b", "nokta.", "https://example.com/a?b=c#d", "e\u{301}", "\u{E9}", "C#",
        "50%", "a | b", "x > y", "3 elma", "Deniz Arıkan", "Çınaraltı Kafe",
        "... devamı", "ne?", "a?b", "?", "1,000", "0b101", "+.5", "\u{FFFE}", "\u{FFFF}x", "\u{90}", "e5", "1e", "~x",
        "&", "*",
        "!!str x", "<<x", "a\u{2028}b", "http://example.com", ":sembol", "y\u{0}z",
    ]

    static let bases: [String] = [
        "",
        "Not.\n",
        "---\n---\n",
        "---\ntype: person\nhedef: eski\naliases: [a, b]\ntags:\n  - a\n  - b\ngoals:\n  spor: true\n---\nGövde.\n",
        "---\r\nhedef: \"eski\" # yorum\r\naliases: tek\r\ntags:\r\n- a\r\ngoals: # yorum\r\n---\r\nGövde.",
    ]

    static func check(_ operation: FrontmatterOperation, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for base in bases {
            let before = RawDocument(bytes: Array(base.utf8))
            let after = try operation.apply(to: before)
            let violations = frontmatterEditViolations(before: before, after: after, operation: operation)
            #expect(violations == [], "on \(base.debugDescription)", sourceLocation: sourceLocation)

            // The value must also be there for a reader that only has the bytes.
            let reread = RawDocument(bytes: after.serialized())
            try SampleWriter().add(reread)
            #expect(operation.isReadBack(from: reread.frontmatter), sourceLocation: sourceLocation)
            // Nothing written ever spans more than its line.
            #expect(reread.lines.count <= before.lines.count + 6, sourceLocation: sourceLocation)
        }
    }

    @Test(arguments: hardTexts)
    func textReadsBackAsAValue(text: String) throws {
        try Self.check(.setValue(key: "hedef", value: .text(text)))
        try Self.check(.setValue(key: "yeni", value: .text(text)))
    }

    @Test(arguments: hardTexts)
    func textReadsBackAsAListItem(text: String) throws {
        let items: [FrontmatterLiteral] = [.text(text), .text("orta"), .text(text + "x"), .text(text)]
        try Self.check(.setList(key: "aliases", items: items))
        try Self.check(.setList(key: "tags", items: items))
        try Self.check(.setList(key: "yeni", items: items))
    }

    @Test(arguments: hardTexts)
    func textReadsBackAsAnEntryValue(text: String) throws {
        try Self.check(.setEntry(key: "goals", entry: "spor", value: .text(text)))
        try Self.check(.setEntry(key: "goals", entry: "kitap", value: .text(text)))
    }

    @Test(arguments: hardTexts.filter { !$0.isEmpty && $0 != "<<" })
    func textReadsBackAsAKey(text: String) throws {
        try Self.check(.setValue(key: text, value: .text("değer")))
        try Self.check(.setList(key: text, items: [.text("a")]))
        try Self.check(.setEntry(key: "goals", entry: text, value: .integer(1)))
        try Self.check(.setEntry(key: text, entry: text, value: .boolean(true)))
    }

    @Test(arguments: [
        FrontmatterLiteral.boolean(true), .boolean(false), .integer(0), .integer(-1), .integer(.max), .integer(.min),
        .number("0"), .number("-0.0"), .number("0.1"), .number("29.0290"), .number("+100"), .number("-123456.789"),
        .number("0.0000001"), .number("1000000000000000000000"),
    ])
    func typedValueReadsBack(value: FrontmatterLiteral) throws {
        try Self.check(.setValue(key: "hedef", value: value))
        try Self.check(.setList(key: "aliases", items: [value, .text("a"), value]))
        try Self.check(.setEntry(key: "goals", entry: "spor", value: value))
    }

    @Test(arguments: [(2026, 10, 2), (2024, 2, 29), (100, 1, 1), (9999, 12, 31)])
    func dateReadsBack(year: Int, month: Int, day: Int) throws {
        let date = try #require(CalendarDate(year: year, month: month, day: day))
        try Self.check(.setValue(key: "hedef", value: .date(date)))
        try Self.check(.setList(key: "tags", items: [.date(date)]))
    }

    @Test(arguments: [
        "", "1e5", "1E-5", ".5", "5.", "012", "0x1F", "1_000", "1,5", "NaN", ".inf", "on iki", "--1", "1 ",
    ])
    func numberThatIsNotWrittenAsDigitsIsRefused(spelling: String) {
        let document = RawDocument(bytes: Array("---\nhedef: 1\n---\n".utf8))

        #expect(throws: EditError.invalidValue) {
            try document.settingFrontmatterValue(.number(spelling), forKey: "hedef")
        }
        #expect(throws: EditError.invalidValue) {
            try document.settingFrontmatterList([.number(spelling)], forKey: "yeni")
        }
        #expect(throws: EditError.invalidValue) {
            try document.settingFrontmatterEntry(.number(spelling), forKey: "a", inMapping: "goals")
        }
    }

    @Test func numberIsWrittenAsGivenAndComparedByItsDigits() throws {
        let document = RawDocument(bytes: Array("---\na: 20.0290\nb: +5\nc: -0\nd: 7\n---\n".utf8))

        // The same value in another spelling changes nothing.
        #expect(try document.settingFrontmatterValue(.number("20.029"), forKey: "a") == document)
        #expect(try document.settingFrontmatterValue(.number("20.02900"), forKey: "a") == document)
        #expect(try document.settingFrontmatterValue(.integer(5), forKey: "b") == document)
        #expect(try document.settingFrontmatterValue(.number("5.0"), forKey: "b") == document)
        #expect(try document.settingFrontmatterValue(.number("0"), forKey: "c") == document)
        #expect(try document.settingFrontmatterValue(.number("7.00"), forKey: "d") == document)

        // Another value is written exactly as spelled.
        let edited = try document.settingFrontmatterValue(.number("20.0300"), forKey: "a")
        #expect(String(decoding: edited.serialized(), as: UTF8.self) == "---\na: 20.0300\nb: +5\nc: -0\nd: 7\n---\n")
        #expect(try document.settingFrontmatterValue(.number("-20.029"), forKey: "a") != document)
        #expect(try document.settingFrontmatterValue(.number("70"), forKey: "d") != document)
    }

    @Test(arguments: ["", "<<"])
    func emptyKeyAndMergeKeyAreRefusedEverywhere(key: String) {
        let document = RawDocument(bytes: Array("---\ngoals:\n  spor: true\n---\n".utf8))

        #expect(throws: EditError.invalidKey) { try document.settingFrontmatterValue(.boolean(true), forKey: key) }
        #expect(throws: EditError.invalidKey) { try document.settingFrontmatterList([], forKey: key) }
        #expect(throws: EditError.invalidKey) {
            try document.settingFrontmatterEntry(.boolean(true), forKey: key, inMapping: "goals")
        }
        #expect(throws: EditError.invalidKey) {
            try document.settingFrontmatterEntry(.boolean(true), forKey: "spor", inMapping: key)
        }
    }
}
