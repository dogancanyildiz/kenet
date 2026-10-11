import Testing
import VaultFormat

@testable import EntityRecognition

private func place(_ name: String, aliases: [String] = []) -> KnownEntity {
    KnownEntity(file: "places/\(name).md", kind: .place, name: name, aliases: aliases)
}

private let digitNames = [
    "12", "2026", "7", "34", "1907", "10", "30", "5", "14", "1", "250", "75", "0212", "555",
].map { place($0) }

private func linked(_ text: String, _ entities: [KnownEntity] = digitNames) throws -> String {
    try EntityRecognizer.linking(text, mentions: EntityRecognizer.recognize(text, entities: entities))
}

/// A digit-only name written plainly is never a mention, whatever stands next to it.
@Test(arguments: [
    "12 Ekim 2026", "12 Ekim 2026'da", "1. Elma", "Tel: 0212 555 12 12", "12—14", "12+5", "34 plakalı araç", "12'de",
    "12’de", "2026’da", "(12)", "Bugün 12 kişi geldi", "Hedef yıl 2026.", "12", "12.", "12...", "12 ve 7", "12:",
    ":12", "-12", "12 :30", "12: 30", "12 - 14", "12.\n30", "12. madde", "12.madde", "12:a", "%12", "12%", "12°",
    "№12", "No:12", "12/A", "A-12", "saat 12'yi 5 geçe", "12 500", "\"12\"", "12!", "12?", "| 12 | 2026 |", "x@12",
    "## Journal\n- 12 kişi\n1. Elma\n", "## Tasks\n- [ ] 12 kişi 📅 2026-10-12 ^t1\n",
    "## Events\n- 9:05 12 kişi ^12\n- 12 kişi saatsiz\n",
    // Times, dates, decimals and ranges.
    "saat 12:30'da", "12.10.2026", "12,5 km", "12:30", "1.250,75", "2026-10-12", "10/12/2026", "12-14", "12–14",
    "12'30", "12’30", "12:30:14", "12.30'da", "(12:30)",
    // Inside a word, a tag or brackets.
    "v12", "12x", "123", "12TL", "x12", "#12", "07:05", "[12]",
])
func plainDigitNameIsNeverAMention(_ text: String) throws {
    #expect(EntityRecognizer.recognize(text, entities: digitNames).isEmpty)
    #expect(try linked(text) == text)
}

/// The at sign is the one way to mention a digit-only name; what follows the name stays as written.
@Test(arguments: [
    ("@12", "[[12]]"), ("@12 kişi geldi", "[[12]] kişi geldi"), ("@12:30", "[[12]]:30"),
    ("@2026-10-12", "[[2026]]-10-12"), ("(@12)", "([[12]])"), ("@12'de", "[[12]]'de"), ("@2026’da", "[[2026]]’da"),
    ("@12 Ekim @2026", "[[12]] Ekim [[2026]]"), ("@12 ve 12", "[[12]] ve 12"), ("@34 plakalı", "[[34]] plakalı"),
    ("1. @1 Elma", "1. [[1]] Elma"), ("Tel: @0212 555 12 12", "Tel: [[0212]] 555 12 12"),
    ("## Tasks\n- [ ] @12 kişi 📅 2026-10-12 ^t1\n", "## Tasks\n- [ ] [[12]] kişi 📅 2026-10-12 ^t1\n"),
    ("## Events\n- 12:30 @12 kişi ^12\n", "## Events\n- 12:30 [[12]] kişi ^12\n"),
])
func explicitDigitNameIsLinked(_ text: String, _ expected: String) throws {
    let mentions = EntityRecognizer.recognize(text, entities: digitNames)
    #expect(mentions.allSatisfy { $0.isExplicit && $0.isCertain })
    #expect(try linked(text) == expected)
    // Linked text has nothing left to link: the digits beside a link are plain writing too.
    #expect(EntityRecognizer.recognize(expected, entities: digitNames).isEmpty)
}

/// The one definition callers use to keep a picked name's at sign: decimal digits of any script, nothing else.
@Test(arguments: [
    ("12", true), ("2026", true), ("0", true), ("١٢", true), ("１２", true), ("१२", true), ("", false), ("12a", false),
    ("Daire 12", false), ("12 5", false), ("12.", false), ("-12", false), ("½", false), ("²", false), ("Ⅻ", false),
    ("1️⃣", false), ("3\u{0301}", false), ("Deniz", false), ("IV", false), ("Ⅳ", false), ("12:30", false),
    ("12.10", false), ("12/10", false), ("１２a", false),
])
func needsExplicitMentionIsTheDigitOnlyRule(_ spelling: String, _ expected: Bool) throws {
    #expect(EntityRecognizer.needsExplicitMention(spelling) == expected)
    // Whatever the helper says is what the recognizer does with a plainly written spelling.
    let entities = [place("Ad", aliases: spelling.isEmpty ? [] : [spelling])]
    #expect(EntityRecognizer.recognize(spelling, entities: entities).isEmpty == (expected || spelling.isEmpty))
}

@Test func existingLinksToDigitNamesAreLeftAlone() throws {
    for text in ["[[12]]", "[[12]]:30", "[[Hedef|12]] kişi", "[[places/12|12]],5", "[[Deniz]]:12", "[[2026]]-10-12"] {
        #expect(EntityRecognizer.recognize(text, entities: digitNames).isEmpty)
        #expect(try linked(text) == text)
    }
}

@Test func explicitDigitNameSharedByTwoEntitiesStaysAmbiguous() throws {
    let twelve = place("12")
    let other = KnownEntity(file: "people/Oniki.md", kind: .person, name: "Oniki", aliases: ["12"])
    let text = "@12 ve 12"
    let mentions = EntityRecognizer.recognize(text, entities: [twelve, other])
    #expect(mentions.count == 1)
    let mention = try #require(mentions.first)
    #expect(mention.isExplicit && mention.isAmbiguous && !mention.isCertain)
    #expect(Set(mention.candidates.map(\.file)) == [twelve.file, other.file])
    #expect(try EntityRecognizer.linking(text, mentions: mentions) == text)
    #expect(
        try EntityRecognizer.linking(text, mentions: mentions, choices: [mention.position: other.file])
            == "[[Oniki|12]] ve 12")
}

/// The rule is about a spelling, not about an entity: every other spelling of the same entity reads as before.
@Test func onlyTheDigitOnlySpellingOfAnEntityNeedsTheAtSign() throws {
    let entities = [place("Otoyol", aliases: ["34", "E5"]), place("06", aliases: ["Başkent"])]
    #expect(try linked("34 plakalı, E5 ve Otoyol", entities) == "34 plakalı, [[Otoyol|E5]] ve [[Otoyol]]")
    #expect(try linked("@34 plakalı, @E5", entities) == "[[Otoyol|34]] plakalı, [[Otoyol|E5]]")
    #expect(try linked("06 ve Başkent", entities) == "06 ve [[06|Başkent]]")
    #expect(try linked("@06 ve @Başkent", entities) == "[[06]] ve [[06|Başkent]]")
}

@Test func mixedNamesAreReadAsBefore() throws {
    let entities =
        digitNames + [
            place("Daire 12"), place("3. Kat"), place("2. Dünya Savaşı"),
            place("Yedi", aliases: ["7/24", "12 5", "12a", "1.250", "12:30", "12."]),
        ]
    for (text, expected) in [
        ("Daire 12:30", "[[Daire 12]]:30"), ("Daire 12.10.2026", "[[Daire 12]].10.2026"),
        ("3. Kat.6 ve 2.3. Kat", "[[3. Kat]].6 ve 2.[[3. Kat]]"), ("1.2. Dünya Savaşı", "1.[[2. Dünya Savaşı]]"),
        ("7/24/7 açık", "[[Yedi|7/24]]/7 açık"), ("Daire 12 ve 12", "[[Daire 12]] ve 12"),
        ("12 Daire 12", "12 [[Daire 12]]"), ("daire 12", "daire 12"), ("@daire 12", "[[Daire 12|daire 12]]"),
        ("12 5 ve 12a, 1.250 lira, 12:30", "[[Yedi|12 5]] ve [[Yedi|12a]], [[Yedi|1.250]] lira, [[Yedi|12:30]]"),
        ("12. madde", "[[Yedi|12.]] madde"),
    ] {
        #expect(try linked(text, entities) == expected)
    }
}

@Test func everyDecimalDigitScriptFollowsTheRule() throws {
    let entities = [place("Rakamlar", aliases: ["١٢", "１２", "12"])]
    for text in ["١٢ kişi", "１２ kişi", "12 kişi", "١٢:٣٠", "１２：３０", "١٢٫٥", "(١٢)", "１２."] {
        #expect(try linked(text, entities) == text)
    }
    #expect(try linked("@١٢ kişi", entities) == "[[Rakamlar|١٢]] kişi")
    #expect(try linked("@１２ kişi", entities) == "[[Rakamlar|１２]] kişi")
    // A fraction, a superscript, a Roman numeral or a keycap is not a digit: such a name is read as any other.
    #expect(
        try linked("½ ve 1️⃣, ² ile Ⅻ", [place("½"), place("1️⃣"), place("²"), place("Ⅻ")])
            == "[[½]] ve [[1️⃣]], [[²]] ile [[Ⅻ]]")
    // Decomposed neighbours change nothing.
    #expect(try linked("s\u{0327}ehirde 12 ve @12", entities) == "s\u{0327}ehirde 12 ve [[Rakamlar|12]]")
}

/// Names that collide with field spellings without being digit-only, so only the structure rule protects them.
private let fieldNames = [
    place("2026-10-12", aliases: ["every", "week", "📅", "⏳", "➕", "⏫", "12:30 Vapuru", "t1"]),
    place("2026"), place("12"), place("10"), place("1"),
    KnownEntity(file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz"]),
]

@Test(arguments: [
    "- [ ] ara 📅 2026-10-12", "- [ ] ara 🛫 2026-10-12 ⏫ ^t1", "- [x] ara ✅ 2026-10-12", "- [ ] ara ⏳ 2026-10-12",
    "- [ ] ara ➕ 2026-10-12 🔼", "- [ ] su 🔁 every week", "- [ ] su 🔁 every week Deniz ile",
    "1. [ ] ara 📅 2026-10-12", "> - [ ] ara 📅 2026-10-12", "  * [/] ara 📅 2026-10-12 📅 2026-10-12",
])
func taskFieldsAreNeverMentionsInAnySection(_ line: String) throws {
    for text in [
        line, "## Journal\n\(line)\n", "## Tasks\n\(line)\r\nson", "## Events\n- 12:30 olay\n\(line)", "x\n\n\(line)",
    ] {
        #expect(try linked(text, fieldNames) == text)
        #expect(EntityRecognizer.recognize(text, entities: fieldNames).isEmpty)
    }
}

@Test func journalSectionTaskKeepsItsDueDateWhileItsTextIsLinked() throws {
    let text = "## Journal\n- [ ] Deniz ile @12 kişi 📅 2026-10-12 ⏳ 2026-10-11 🔁 every week ⏫ ^t1\n"
    let result = try linked(text, fieldNames)
    #expect(
        result
            == "## Journal\n- [ ] [[Deniz Arıkan|Deniz]] ile [[12]] kişi 📅 2026-10-12 ⏳ 2026-10-11 🔁 every week ⏫ ^t1\n"
    )
    let before = try #require(RawDocument(bytes: text.utf8).bodyLines.tasks.first)
    let after = try #require(RawDocument(bytes: result.utf8).bodyLines.tasks.first)
    #expect(after.dueDate == CalendarDate("2026-10-12"))
    #expect(after.dueDate == before.dueDate)
    #expect(after.priority == before.priority)
    #expect(after.recurrence == before.recurrence)
    #expect(after.block.id == before.block.id)
}

@Test func fieldSpellingsOutsideAFieldRemainText() throws {
    #expect(try linked("- [ ] 📅 gün every", fieldNames) == "- [ ] [[2026-10-12|📅]] gün [[2026-10-12|every]]")
    #expect(try linked("- [ ] ara 📅 2026-13-40", fieldNames) == "- [ ] ara [[2026-10-12|📅]] 2026-13-40")
    #expect(try linked("ara 📅 2026-10-12", fieldNames) == "ara [[2026-10-12|📅]] [[2026-10-12]]")
    #expect(try linked("1. [ ] @1 kişi", fieldNames) == "1. [ ] [[1]] kişi")
}

@Test func eventClockIsNeverAMention() throws {
    let text = "## Events\n- 12:30 Vapuru kalktı\n- 9:05 @12 kişi ^12\n- 12:30 Vapuru\n"
    #expect(
        try linked(text, fieldNames) == "## Events\n- 12:30 Vapuru kalktı\n- 9:05 [[12]] kişi ^12\n- 12:30 Vapuru\n")
    // Outside the Events section the same line is no event and reads as before.
    #expect(
        try linked("## Journal\n- 12:30 Vapuru kalktı\n", fieldNames)
            == "## Journal\n- [[2026-10-12|12:30 Vapuru]] kalktı\n")
}

private struct DigitRandom: RandomNumberGenerator {
    var state: UInt64 = 0x0D16_175
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private let randomPieces = [
    "Daire 12", "Daire 12", "3. Kat", "2. Dünya Savaşı", "Deniz", "Deniz Arıkan", "R2-D2", "7/24", "1.250",
    "12:30 Vapuru", "D12", "Kat 3", "@Daire 12", "@Deniz", "@3. Kat", "daire 12", "12", "2026", "7", "3", ":30",
    "@12", "@2026", "@7", "(@12)",
    ".10.2026", ",5", "-14", "/12", "'de", "’da", "'30", ".", "...", "(", ")", ":", ",", "-", "/", "saat", "x", "–14",
    "١٢", "１２", "：３０", "[[Daire 12]]", "[[12]]", "`12:30`", "- [ ] ", "- ", "📅 2026-10-12", "⏳ 2026-10-11",
    "🔁 every week",
    "⏫", "^t1", "\n", "\n", "\r\n", "## Events\n", "## Journal\n", "\t", "\u{00a0}",
]

private func randomText(_ random: inout DigitRandom) -> String {
    var text = ""
    for _ in 0..<Int(random.next() % 40) {
        text += randomPieces[Int(random.next() % UInt64(randomPieces.count))]
        text += random.next() % 2 == 0 ? " " : ""
    }
    return text
}

/// Digit-only names are invisible in plain writing: knowing them changes nothing but their own `@` mentions.
@Test func knowingDigitOnlyNamesChangesNothingButTheirExplicitMentions() {
    var random = DigitRandom()
    let mixed = [
        place("Daire 12", aliases: ["D12"]), place("3. Kat", aliases: ["Kat 3"]),
        place("2. Dünya Savaşı", aliases: ["7/24", "1.250", "12:30 Vapuru"]),
        KnownEntity(
            file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz", "R2-D2", "½", "1️⃣"]),
    ]
    let digits = [place("12"), place("2026"), place("3"), place("Sayılar", aliases: ["7", "30", "١٢", "１２"])]
    var mentionCount = 0
    var explicitCount = 0
    for _ in 0..<1500 {
        let text = randomText(&random)
        let entities = mixed.filter { _ in random.next() % 4 != 0 }
        let without = EntityRecognizer.scan(text, entities: entities, context: .init())
        let with = EntityRecognizer.scan(text, entities: entities + digits, context: .init())
        let digitMentions = with.known.filter { $0.spelling.allSatisfy(RecognitionLine.digit) }
        #expect(digitMentions.allSatisfy { $0.isExplicit }, "\(text)")
        let others = with.known.filter { !digitMentions.contains($0) }
        #expect(others == without.known, "\(text)")
        #expect(with.unknown == without.unknown, "\(text)")
        mentionCount += without.known.count
        explicitCount += digitMentions.count
    }
    #expect(mentionCount > 1500)
    #expect(explicitCount > 100)
}

@Test func randomDigitNameLinkingIsStableAndKeepsEveryTaskField() throws {
    var random = DigitRandom()
    let entities = digitNames + fieldNames + [place("Daire 12"), place("3. Kat")]
    for _ in 0..<800 {
        let text = randomText(&random)
        let mentions = EntityRecognizer.recognize(text, entities: entities)
        let choices = Dictionary(uniqueKeysWithValues: mentions.map { ($0.position, $0.candidates[0].file) })
        let result = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
        // A second pass finds no digit-only name the first one left behind.
        let again = EntityRecognizer.recognize(result, entities: entities)
        #expect(again.allSatisfy { mention in !mention.spelling.allSatisfy(\.isNumber) })
        let before = RawDocument(bytes: text.utf8).bodyLines
        let after = RawDocument(bytes: result.utf8).bodyLines
        #expect(after.tasks.map(\.dueDate) == before.tasks.map(\.dueDate))
        #expect(after.tasks.map(\.priority) == before.tasks.map(\.priority))
        #expect(after.tasks.map(\.recurrenceSource) == before.tasks.map(\.recurrenceSource))
        #expect(after.tasks.map(\.block.id) == before.tasks.map(\.block.id))
        #expect(after.events.map(\.time) == before.events.map(\.time))
    }
}
