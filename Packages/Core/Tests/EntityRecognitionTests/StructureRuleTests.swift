import Testing
import VaultFormat

@testable import EntityRecognition

private func place(_ name: String, aliases: [String] = []) -> KnownEntity {
    KnownEntity(file: "places/\(name).md", kind: .place, name: name, aliases: aliases)
}

private let numbers = ["12", "2026", "30", "5", "14", "1", "2", "3", "168", "192", "0212", "555", "13", "00"].map {
    place($0)
}

private func linked(_ text: String, _ entities: [KnownEntity]) throws -> String {
    try EntityRecognizer.linking(
        text, mentions: EntityRecognizer.recognize(text, entities: entities).filter(\.isCertain))
}

/// Addresses, versions, clock ranges and measures are numbers too: none of their parts is a mention.
@Test(arguments: [
    "192.168.12.1", "sürüm 1.2.3", "12:30-13:00 arası", "12.5km", "A1-12", "Bölüm 3:12", "1/2/3", "5,12,30",
])
func longerNumericExpressionsStayPlain(_ text: String) throws {
    #expect(try linked(text, numbers) == text)
}

/// A number next to a symbol, a unit, a letter or a month name stands alone and is read as before.
@Test(arguments: [
    ("%12", "%[[12]]"), ("12%", "[[12]]%"), ("12°", "[[12]]°"), ("№12", "№[[12]]"), ("No:12", "No:[[12]]"),
    ("12/A", "[[12]]/A"), ("A-12", "A-[[12]]"), ("12.madde", "[[12]].madde"),
    ("Tel: 0212 555 12 12", "Tel: [[0212]] [[555]] [[12]] [[12]]"), ("12 Ekim 2026", "[[12]] Ekim [[2026]]"),
    ("12 Ekim 2026'da", "[[12]] Ekim [[2026]]'da"), ("saat 12'yi 5 geçe", "saat [[12]]'yi [[5]] geçe"),
    ("12+5", "[[12]]+[[5]]"), ("12 500", "[[12]] 500"),
])
func numberBesideASymbolOrAWordIsStillLinked(_ text: String, _ expected: String) throws {
    #expect(try linked(text, numbers) == expected)
    #expect(try linked(expected, numbers) == expected)
}

private let people = [
    KnownEntity(file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz"]),
    KnownEntity(file: "people/Elif.md", kind: .person, name: "Elif"), place("Ev"),
]

/// What the structure rule changes for an everyday name: only a name inside a recurrence rule
/// the app cannot read, which ends at the next field, at a link or at the end of the line.
@Test(arguments: [
    ("- [ ] su iç 🔁 her hafta Deniz ile", "- [ ] su iç 🔁 her hafta Deniz ile"),
    ("- [ ] su iç 🔁 her hafta @Deniz ile", "- [ ] su iç 🔁 her hafta @Deniz ile"),
    ("- [ ] su iç 🔁 her hafta ⏫ Deniz ile", "- [ ] su iç 🔁 her hafta ⏫ [[Deniz Arıkan|Deniz]] ile"),
    ("- [ ] su iç 🔁 her hafta 📅 2026-10-12 Elif", "- [ ] su iç 🔁 her hafta 📅 2026-10-12 [[Elif]]"),
    ("- [ ] su iç 🔁 her hafta [[Ev]] Elif", "- [ ] su iç 🔁 her hafta [[Ev]] [[Elif]]"),
    ("- [ ] Elif 🔁 every week Ev", "- [ ] [[Elif]] 🔁 every week Ev"),
    ("- [ ] Elif 🔁 every week ⏫ Ev #project/Ev ^Ev", "- [ ] [[Elif]] 🔁 every week ⏫ [[Ev]] #project/Ev ^Ev"),
    ("- [ ] 📅 almanak al Elif ⏳ sonra Ev", "- [ ] 📅 almanak al [[Elif]] ⏳ sonra [[Ev]]"),
    ("- [ ] Elif'e a^b sor ^not kimlik Ev", "- [ ] [[Elif]]'e a^b sor ^not kimlik [[Ev]]"),
    ("su iç 🔁 her hafta Deniz ile", "su iç 🔁 her hafta [[Deniz Arıkan|Deniz]] ile"),
    ("- su iç 🔁 her hafta Deniz ile", "- su iç 🔁 her hafta [[Deniz Arıkan|Deniz]] ile"),
])
func everydayNameIsHeldOnlyByAnUnreadRecurrenceRule(_ text: String, _ expected: String) throws {
    for prefix in ["", "## Journal\n", "## Tasks\n", "## Events\n"] {
        #expect(try linked(prefix + text, people + numbers) == prefix + expected)
    }
}

private struct StructureRandom: RandomNumberGenerator {
    var state: UInt64 = 0x5EED_2026
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

private let structureNames =
    people + numbers + [
        place("Takvim", aliases: ["every", "week", "📅", "⏳", "➕", "🔁", "✅", "🛫", "her", "hafta", "days"]),
        place("Öncelik", aliases: ["⏫", "🔼", "x", "-", "*", "1.", "[ ]", "project", "project/Ev", "#project/Ev"]),
        place(
            "2026-10-12", aliases: ["12:30 Vapuru", "9:05", "t1", "ara 📅", "⏫ ^t1", "- Elif", "12:30 Elif", "Ev ^t1"]),
    ]

private let structurePieces = [
    "Deniz", "Deniz Arıkan", "Elif", "Ev", "@Elif", "@Ev", "Elif'e", "Ev’de", "12", "2026", "1", "2", "12:30", "9:05",
    "2026-10-12", "12.10.2026", "every", "week", "her", "hafta", "ara", "x", "Vapuru", "project", "t1", "-", "*", "1.",
    "📅 2026-10-12", "🛫 2026-10-10", "✅ 2026-10-08", "⏳ 2026-10-11", "➕ 2026-10-01", "🔁 every week",
    "🔁 every 2 days", "🔁 her hafta", "🔁", "⏫", "🔼", "#project/Ev", "#project/", "📅", "⏳", "📅 2026-13-40",
    "^t1", "^12", "[[Ev]]", "[[Deniz Arıkan|Deniz]]", "`Elif`", "[Elif](x)", ",", ".", ":", "(", ")",
]

private let structureMarkers = [
    "- [ ] ", "- [x] ", "* [/] ", "1. [ ] ", "12) [ ] ", "> - [ ] ", "  - [ ] ", "\t- [-] ", "- ", "* ", "- 12:30 ",
    "- 9:05 ", "+ 12:30 ", "  - 12:30 ", "1. ", "> ", "", "", "## Events\n- ", "## Tasks\n", "## Journal\n",
]

/// Whatever the recognizer offers, linking all of it leaves every task and event reading as it did.
@Test func linkingEveryMentionKeepsEveryTaskAndEventAsItWas() throws {
    var random = StructureRandom()
    var mentionCount = 0
    var taskCount = 0
    var eventCount = 0
    for _ in 0..<1200 {
        var text = ""
        for _ in 0..<Int.random(in: 1...6, using: &random) {
            text += structureMarkers.randomElement(using: &random)!
            for _ in 0..<Int.random(in: 1...8, using: &random) {
                text += structurePieces.randomElement(using: &random)!
                text += Bool.random(using: &random) || Bool.random(using: &random) ? " " : ""
            }
            text += Bool.random(using: &random) ? " ^t1\n" : "\n"
        }
        let mentions = EntityRecognizer.recognize(text, entities: structureNames)
        let choices = Dictionary(uniqueKeysWithValues: mentions.map { ($0.position, $0.candidates[0].file) })
        let result = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
        let before = RawDocument(bytes: text.utf8).bodyLines
        let after = RawDocument(bytes: result.utf8).bodyLines
        mentionCount += mentions.count
        taskCount += before.tasks.count
        eventCount += before.events.count
        #expect(after.tasks.map(\.block.lineRange) == before.tasks.map(\.block.lineRange), "\(text)")
        #expect(after.tasks.map(\.block.id) == before.tasks.map(\.block.id), "\(text)")
        #expect(after.tasks.map(\.rawStatus) == before.tasks.map(\.rawStatus), "\(text)")
        #expect(after.tasks.map(\.dueDate) == before.tasks.map(\.dueDate), "\(text)")
        #expect(after.tasks.map(\.startDate) == before.tasks.map(\.startDate), "\(text)")
        #expect(after.tasks.map(\.doneDate) == before.tasks.map(\.doneDate), "\(text)")
        #expect(after.tasks.map(\.priority) == before.tasks.map(\.priority), "\(text)")
        #expect(after.tasks.map(\.project) == before.tasks.map(\.project), "\(text)")
        #expect(after.tasks.map(\.recurrence) == before.tasks.map(\.recurrence), "\(text)")
        #expect(after.tasks.map(\.recurrenceSource) == before.tasks.map(\.recurrenceSource), "\(text)")
        #expect(after.tasks.map(\.fieldRanges.count) == before.tasks.map(\.fieldRanges.count), "\(text)")
        #expect(after.events.map(\.block.lineRange) == before.events.map(\.block.lineRange), "\(text)")
        #expect(after.events.map(\.block.id) == before.events.map(\.block.id), "\(text)")
        #expect(after.events.map(\.time) == before.events.map(\.time), "\(text)")
    }
    #expect(mentionCount > 5000 && taskCount > 1000 && eventCount > 150)
}
