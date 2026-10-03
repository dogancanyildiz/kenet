import EntityRecognition
import Testing
import VaultFormat

let deniz = KnownEntity(
    file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz", "Deniz abi"])
let mert = KnownEntity(file: "people/Mert Aksu.md", kind: .person, name: "Mert Aksu")
let workMert = KnownEntity(
    file: "people/Mert Aksu (iş).md", kind: .person, name: "Mert Aksu", qualifier: "iş", aliases: ["Mert"])
let office = KnownEntity(file: "places/Liman Ofis.md", kind: .place, name: "Liman Ofis", aliases: ["ofis"])

@Test func ambiguityRequiresAnActualChoice() throws {
    let text = "@Mert Aksu’nun Deniz’e"
    let entities = [mert, workMert, deniz]
    let mentions = EntityRecognizer.recognize(text, entities: entities)
    #expect(mentions.map(\.isAmbiguous) == [true, false])
    #expect(try EntityRecognizer.linking(text, mentions: mentions) == "@Mert Aksu’nun [[Deniz Arıkan|Deniz]]’e")
    let choices = [mentions[0].position: workMert.file]
    let linked = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
    #expect(linked == "[[Mert Aksu (iş)|Mert Aksu]]’nun [[Deniz Arıkan|Deniz]]’e")
    #expect(EntityRecognizer.recognize(linked, entities: entities).isEmpty)
    #expect(throws: EntityLinkError.invalidChoice) {
        try EntityRecognizer.linking(text, mentions: mentions, choices: [mentions[0].position: deniz.file])
    }
    #expect(throws: EntityLinkError.staleMention) {
        try EntityRecognizer.linking("Su", mentions: mentions, choices: choices)
    }
}

@Test func rankingUsesPlaceWeightThenRecencyFrequencyAndPath() {
    let old = CalendarDate("2026-09-14")!
    let recent = CalendarDate("2026-09-27")!
    func order(_ usage: [EntityUsage], _ context: RecognitionContext = .init()) -> [String] {
        EntityRecognizer.recognize(
            "Mert Aksu Deniz ofis", entities: [mert, workMert, deniz, office], usage: usage, context: context)[0]
            .candidates.map(\.file)
    }
    #expect(
        order([
            .init(file: mert.file, totalCount: 100, lastDate: recent, cooccurrences: [deniz.file: 3]),
            .init(file: workMert.file, totalCount: 1, lastDate: old, cooccurrences: [office.file: 1]),
        ]) == [workMert.file, mert.file])
    #expect(
        order([.init(file: mert.file, lastDate: recent), .init(file: workMert.file, totalCount: 100, lastDate: old)])
            == [mert.file, workMert.file])
    #expect(
        order([.init(file: mert.file, totalCount: 2), .init(file: workMert.file, totalCount: 1)]) == [
            mert.file, workMert.file,
        ])
    #expect(order([]) == [workMert.file, mert.file])
    let context = RecognitionContext(entities: [office, office, mert])
    let usage: [EntityUsage] = [
        .init(file: mert.file, cooccurrences: [mert.file: 999, office.file: 1]),
        .init(file: workMert.file, cooccurrences: [office.file: 2]),
    ]
    #expect(order(usage, context) == [workMert.file, mert.file])
    #expect(order([.init(file: mert.file, cooccurrences: [office.file: .max])]) == [mert.file, workMert.file])
}

@Test func callerContextCanRankAbsentLocations() {
    let mentions = EntityRecognizer.recognize(
        "Mert Aksu", entities: [mert, workMert], usage: [.init(file: mert.file, cooccurrences: [office.file: 2])],
        context: .init(entities: [office]))
    #expect(mentions[0].candidates.first == mert)
    #expect(mentions[0].isAmbiguous)
}

@Test func codeFenceContextAndSharedEscapeRules() {
    let text = "\\[[Deniz]] `Deniz` ``Deniz ` Deniz`` Deniz\n- Su\n  ~~~\n  Deniz\n  ~~~\nDeniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.position.line) == [0, 5])
    #expect(EntityRecognizer.recognize(text, entities: [deniz], context: .init(insideFence: true)).isEmpty)
    #expect(EntityRecognizer.unknownMentions("@Baran Tunç", entities: [], context: .init(insideFence: true)).isEmpty)
}

@Test func unknownMentionsStopAtFourWordsAndPunctuation() {
    let text = "@Baran Tunç Ece Yalın Selin Korkmaz; @Baran Tunç’a @Ece, Yalın @Deniz\nArıkan @selin"
    let unknown = EntityRecognizer.unknownMentions(text, entities: [deniz])
    #expect(unknown.map(\.spelling) == ["Baran Tunç Ece Yalın", "Baran Tunç", "Ece"])
}

@Test func unicodeWordBoundariesAndFlexibleWhitespace() throws {
    let text = "Denizα ١Deniz Deniz٣ 🧭Deniz\t\tArıkan’s Deniz\u{00a0}abi"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.spelling) == ["Deniz\t\tArıkan", "Deniz\u{00a0}abi"])
    #expect(
        try EntityRecognizer.linking(text, mentions: mentions)
            == "Denizα ١Deniz Deniz٣ 🧭[[Deniz Arıkan|Deniz\t\tArıkan]]’s [[Deniz Arıkan|Deniz\u{00a0}abi]]")
}

@Test func bomAndMixedEndingsRemainByteExact() throws {
    let text = "\u{feff}Deniz\r\nDeniz\r@Deniz\nSu"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.position.line) == [0, 1, 2])
    #expect(mentions.map(\.position.byteRange) == [0..<5, 0..<5, 1..<6])
    let expected = "\u{feff}[[Deniz Arıkan|Deniz]]\r\n[[Deniz Arıkan|Deniz]]\r[[Deniz Arıkan|Deniz]]\nSu"
    #expect(Array(try EntityRecognizer.linking(text, mentions: mentions).utf8) == Array(expected.utf8))
}

@Test func aliasNameTieKeepsAllCandidatesAndPrefersName() throws {
    let alias = KnownEntity(
        file: "people/Selin Korkmaz.md", kind: .person, name: "Selin Korkmaz", aliases: ["Deniz Arıkan"])
    let mentions = EntityRecognizer.recognize("Deniz Arıkan", entities: [alias, deniz, deniz])
    #expect(mentions.count == 1)
    #expect(mentions[0].isAmbiguous)
    #expect(!mentions[0].isAlias)
    #expect(mentions[0].candidates.count == 2)
    #expect(
        try EntityRecognizer.linking("Deniz Arıkan", mentions: mentions, choices: [mentions[0].position: alias.file])
            == "[[Selin Korkmaz|Deniz Arıkan]]")
}

@Test func malformedDisplayAndOverlappingSelectionsAreRejected() throws {
    let entity = KnownEntity(file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz]Arıkan")
    let text = "Deniz]Arıkan"
    let mentions = EntityRecognizer.recognize(text, entities: [entity])
    #expect(throws: EntityLinkError.unrepresentableMention) { try EntityRecognizer.linking(text, mentions: mentions) }
    let valid = EntityRecognizer.recognize("Deniz", entities: [deniz])
    #expect(throws: EntityLinkError.staleMention) { try EntityRecognizer.linking("Deniz", mentions: valid + valid) }
}
