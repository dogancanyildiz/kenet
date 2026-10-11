import Testing
import VaultFormat

@testable import EntityRecognition

private func place(_ name: String, aliases: [String] = []) -> KnownEntity {
    KnownEntity(file: "places/\(name).md", kind: .place, name: name, aliases: aliases)
}

private let digitNames = ["12", "2026", "7", "34", "1907", "10", "30", "5", "14", "1", "250", "75"].map {
    place($0)
}

private func linked(_ text: String, _ entities: [KnownEntity] = digitNames) throws -> String {
    try EntityRecognizer.linking(text, mentions: EntityRecognizer.recognize(text, entities: entities))
}

@Test(arguments: [
    "saat 12:30'da", "12.10.2026", "12,5 km", "12:30", "12.30", "12,5", "1.250,75", "2026-10-12", "10/12/2026",
    "10/12", "12-14", "12–14", "12'30", "12’30", "12:30:14", "12.30'da", "saat 12:30.", "(12:30)",
])
func digitNameInsideNumericExpressionIsNotAMention(_ text: String) throws {
    #expect(EntityRecognizer.recognize(text, entities: digitNames).isEmpty)
    #expect(try linked(text) == text)
}

@Test(arguments: ["v12", "12x", "123", "12TL", "x12", "#12", "07:05", "[12]"])
func digitNameInsideAWordOrTagStaysProtected(_ text: String) throws {
    #expect(try linked(text) == text)
}

@Test(arguments: [
    ("34 plakalı araç", "[[34]] plakalı araç"), ("Bugün 12 kişi geldi", "Bugün [[12]] kişi geldi"),
    ("Hedef yıl 2026.", "Hedef yıl [[2026]]."), ("12'de", "[[12]]'de"), ("12’de", "[[12]]’de"),
    ("2026’da", "[[2026]]’da"), ("(12)", "([[12]])"), ("12.", "[[12]]."), ("12...", "[[12]]..."),
    ("12", "[[12]]"), ("12 ve 7", "[[12]] ve [[7]]"), ("12:", "[[12]]:"), (":12", ":[[12]]"), ("-12", "-[[12]]"),
    ("12 :30", "[[12]] :[[30]]"), ("12: 30", "[[12]]: [[30]]"), ("12 - 14", "[[12]] - [[14]]"),
    ("12.\n30", "[[12]].\n[[30]]"), ("12. madde", "[[12]]. madde"), ("12:a", "[[12]]:a"),
])
func standaloneDigitNameIsStillLinked(_ text: String, _ expected: String) throws {
    #expect(try linked(text) == expected)
    #expect(EntityRecognizer.recognize(expected, entities: digitNames).isEmpty)
}

@Test func explicitDigitNameIsAlwaysLinkedAndTheRestOfTheExpressionStaysPlain() throws {
    #expect(try linked("@12") == "[[12]]")
    #expect(try linked("@12:30") == "[[12]]:30")
    #expect(try linked("@2026-10-12") == "[[2026]]-10-12")
    // The digit a link ends with still joins what follows it, so a second pass adds nothing.
    for text in ["[[12]]:30", "[[2026]]-10-12", "[[Daire 12]].10", "[[places/x|12]],5"] {
        #expect(EntityRecognizer.recognize(text, entities: digitNames).isEmpty)
    }
    #expect(try linked("[[Deniz]]:12") == "[[Deniz]]:[[12]]")
}

@Test func mixedNamesAreReadAsBefore() throws {
    let entities =
        digitNames + [place("Daire 12"), place("3. Kat"), place("2. Dünya Savaşı"), place("Yedi", aliases: ["7/24"])]
    #expect(try linked("Daire 12:30", entities) == "[[Daire 12]]:30")
    #expect(try linked("Daire 12.10.2026", entities) == "[[Daire 12]].10.2026")
    #expect(try linked("3. Kat.6 ve 2.3. Kat", entities) == "[[3. Kat]].6 ve 2.[[3. Kat]]")
    #expect(try linked("1.2. Dünya Savaşı", entities) == "1.[[2. Dünya Savaşı]]")
    #expect(try linked("7/24/7 açık", entities) == "[[Yedi|7/24]]/7 açık")
}

@Test func everyDecimalDigitScriptFollowsTheRule() throws {
    let entities = [place("Rakamlar", aliases: ["١٢", "１２", "12"])]
    for text in ["١٢:٣٠", "١٢/١٠", "١٢٫٥", "١٢٬٥٠٠", "１２：３０", "１２:３０", "１２．３０", "12:٣٠", "٣٠:12", "12/１２"] {
        #expect(try linked(text, entities) == text)
    }
    #expect(try linked("١٢ kişi", entities) == "[[Rakamlar|١٢]] kişi")
    #expect(try linked("１２ kişi", entities) == "[[Rakamlar|１２]] kişi")
    // A fraction or a keycap is not a digit-only name: it is read as any other name.
    #expect(try linked("½:30 ve 1️⃣:30", [place("½"), place("1️⃣")]) == "[[½]]:30 ve [[1️⃣]]:30")
    // Decomposed neighbours change nothing.
    #expect(try linked("s\u{0327}ehirde 12:30 ve 12", entities) == "s\u{0327}ehirde 12:30 ve [[Rakamlar|12]]")
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
    let text = "## Journal\n- [ ] Deniz ile 12 kişi 📅 2026-10-12 ⏳ 2026-10-11 🔁 every week ⏫ ^t1\n"
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
    #expect(try linked("1. [ ] 1 kişi", fieldNames) == "1. [ ] [[1]] kişi")
}

@Test func eventClockIsNeverAMention() throws {
    let text = "## Events\n- 12:30 Vapuru kalktı\n- 9:05 12 kişi ^12\n- 12:30 Vapuru\n"
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

/// The numeric expression rule switched off is the recognizer as it was; names that are not
/// digit-only must read the same either way, on every input.
@Test func namesThatAreNotDigitOnlyReadAsWithoutTheNumericRule() {
    var random = DigitRandom()
    let mixed = [
        place("Daire 12", aliases: ["D12"]), place("3. Kat", aliases: ["Kat 3"]),
        place("2. Dünya Savaşı", aliases: ["7/24", "1.250", "12:30 Vapuru"]),
        KnownEntity(
            file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz", "R2-D2", "½", "1️⃣"]),
    ]
    var mentionCount = 0
    var digitDifferences = 0
    for _ in 0..<1500 {
        let text = randomText(&random)
        let entities = mixed.filter { _ in random.next() % 4 != 0 }
        let current = EntityRecognizer.scan(text, entities: entities, context: .init())
        let previous = EntityRecognizer.scan(text, entities: entities, context: .init(), numericRule: false)
        #expect(current.known == previous.known)
        #expect(current.unknown == previous.unknown)
        mentionCount += current.known.count
        // The same texts do tell the two apart once a digit-only name is known.
        let digits = entities + [place("12"), place("2026")]
        if EntityRecognizer.scan(text, entities: digits, context: .init()).known
            != EntityRecognizer.scan(text, entities: digits, context: .init(), numericRule: false).known
        {
            digitDifferences += 1
        }
    }
    #expect(mentionCount > 1500)
    #expect(digitDifferences > 100)
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
