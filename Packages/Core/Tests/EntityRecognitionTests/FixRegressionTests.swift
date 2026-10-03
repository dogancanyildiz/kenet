import Testing
import VaultFormat

@testable import EntityRecognition

@Test func emailDomainsTagsIdentifiersAndUrlsStayUntouched() throws {
    let text = "ali@deniz.com e@Deniz deniz.com www.deniz.com.tr #project/Deniz #Deniz ^Deniz ftp://Deniz x.y.z @Deniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.spelling) == ["Deniz"])
    #expect(mentions[0].isExplicit)
    #expect(
        EntityRecognizer.unknownMentions("e@Baran www.Baran.Tunc #project/@Baran ftp://@Baran", entities: []).isEmpty)
    #expect(
        try EntityRecognizer.linking(text, mentions: mentions)
            == "ali@deniz.com e@Deniz deniz.com www.deniz.com.tr #project/Deniz #Deniz ^Deniz ftp://Deniz x.y.z [[Deniz Arıkan|Deniz]]"
    )
}

@Test func markdownLinksProtectLabelsTargetsAndBalancedParentheses() throws {
    let text = "[not Deniz burada](notes/Deniz.md) [Deniz ile toplantı](notlar(1).md) [Su](Deniz.md) Deniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.spelling) == ["Deniz"])
    #expect(mentions[0].byteRange.lowerBound == text.utf8.count - 5)
    let linked = try EntityRecognizer.linking(text, mentions: mentions)
    #expect(EntityRecognizer.recognize(linked, entities: [deniz]).isEmpty)
}

@Test func syntaxPrefixesAndBracketSuffixNeverBecomeLinks() throws {
    let text = "Bravo!Deniz \\Deniz [Deniz] [[Deniz |Deniz #Deniz ^Deniz Deniz] \\[[Deniz]] Deniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.count == 1)
    #expect(mentions[0].byteRange.lowerBound == text.utf8.count - 5)
    let linked = try EntityRecognizer.linking(text, mentions: mentions)
    #expect(EntityRecognizer.recognize(linked, entities: [deniz]).isEmpty)
}

@Test func initialCaseMismatchIsASuggestionUntilExplicitOrChosen() throws {
    let text = "deniz kenarı ev temizliği Deniz Ev @deniz"
    let home = KnownEntity(file: "places/Ev.md", kind: .place, name: "Ev")
    let entities = [deniz, home]
    let mentions = EntityRecognizer.recognize(text, entities: entities)
    #expect(mentions.map(\.isCaseMismatch) == [true, true, false, false, true])
    #expect(mentions.map(\.isCertain) == [false, false, true, true, true])
    #expect(mentions.allSatisfy { !$0.isAmbiguous })
    #expect(
        try EntityRecognizer.linking(text, mentions: mentions)
            == "deniz kenarı ev temizliği [[Deniz Arıkan|Deniz]] [[Ev]] [[Deniz Arıkan|deniz]]")
    let choices = Dictionary(uniqueKeysWithValues: mentions.map { ($0.position, $0.candidates[0].file) })
    let linked = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
    #expect(EntityRecognizer.recognize(linked, entities: entities).isEmpty)
    let lowercaseAlias = KnownEntity(file: "places/Liman Ofis.md", kind: .place, name: "Liman Ofis", aliases: ["ofis"])
    #expect(!EntityRecognizer.recognize("Ofis", entities: [lowercaseAlias])[0].isCertain)
    #expect(EntityRecognizer.recognize("ofis", entities: [lowercaseAlias])[0].isCertain)
}

@Test func frontmatterAndItsFenceSpellingDoNotAffectBodyRecognition() throws {
    let text = "---\nname: Deniz\naliases: [Deniz]\nnote: '~~~'\n---\nDeniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.map(\.line) == [5])
    #expect(EntityRecognizer.unknownMentions("---\nname: '@Baran Tunç'\n---\nSu", entities: []).isEmpty)
    #expect(
        try EntityRecognizer.linking(text, mentions: mentions)
            == "---\nname: Deniz\naliases: [Deniz]\nnote: '~~~'\n---\n[[Deniz Arıkan|Deniz]]")
}

@Test func tableDisplaySeparatorIsEscapedAndIdempotent() throws {
    let text = "  | Deniz | ofis |\r\n"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz, office])
    let linked = try EntityRecognizer.linking(text, mentions: mentions)
    #expect(linked == "  | [[Deniz Arıkan\\|Deniz]] | [[Liman Ofis\\|ofis]] |\r\n")
    #expect(EntityRecognizer.recognize(linked, entities: [deniz, office]).isEmpty)
    #expect(RawDocument(bytes: linked.utf8).links.map(\.target) == ["Deniz Arıkan", "Liman Ofis"])
}

@Test func changedSpellingWithSameLengthIsStale() throws {
    let mentions = EntityRecognizer.recognize("Deniz", entities: [deniz])
    #expect(throws: EntityLinkError.staleMention) { try EntityRecognizer.linking("Deniy", mentions: mentions) }
}

@Test func equalLengthOverlapPrefersFirstStart() {
    let first = KnownEntity(file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Ece")
    let second = KnownEntity(file: "people/Ece Yalın.md", kind: .person, name: "Ece Selin")
    let mentions = EntityRecognizer.recognize("Deniz Ece Selin", entities: [second, first])
    #expect(mentions.map(\.spelling) == ["Deniz Ece"])
}

@Test func equalLengthOverlapPrefersNameOverEarlierAlias() {
    let first = KnownEntity(file: "people/Deniz Arıkan.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz Ece"])
    let second = KnownEntity(file: "people/Ece Yalın.md", kind: .person, name: "Ece Selin")
    let mentions = EntityRecognizer.recognize("Deniz Ece Selin", entities: [first, second])
    #expect(mentions.map(\.spelling) == ["Ece Selin"])
}

@Test func missingDateRanksAfterDatedCandidateRegardlessOfFrequency() {
    let mentions = EntityRecognizer.recognize(
        "Mert Aksu", entities: [mert, workMert],
        usage: [
            .init(file: mert.file, totalCount: 0, lastDate: CalendarDate("2026-09-14")),
            .init(file: workMert.file, totalCount: .max),
        ])
    #expect(mentions[0].candidates.map(\.file) == [mert.file, workMert.file])
}

@Test func aliasEqualToFilenameDoesNotNeedDisplayText() throws {
    let entity = KnownEntity(file: "people/Deniz.md", kind: .person, name: "Deniz Arıkan", aliases: ["Deniz"])
    let mentions = EntityRecognizer.recognize("Deniz", entities: [entity])
    #expect(try EntityRecognizer.linking("Deniz", mentions: mentions) == "[[Deniz]]")
}

@Test func unicodeLineSeparatorsCannotJoinNamesOrUnknownMentions() {
    let text = "Deniz\u{2028}Arıkan Deniz\u{0085}Arıkan"
    let fullOnly = KnownEntity(file: deniz.file, kind: .person, name: deniz.name)
    #expect(EntityRecognizer.recognize(text, entities: [fullOnly]).isEmpty)
    #expect(
        EntityRecognizer.unknownMentions("@Baran\u{2028}Tunç @Ece\u{0085}Yalın", entities: []).map(\.spelling) == [
            "Baran", "Ece",
        ])
}

@Test func excludedAtSignCannotMakeMentionExplicit() {
    let line = RecognitionLine(Array("@Deniz".utf8), excluded: [true, false, false, false, false, false])
    #expect(!line.isExplicit(at: 1))
    let visible = RecognitionLine(Array("@Deniz".utf8), excluded: Array(repeating: false, count: 6))
    #expect(visible.isExplicit(at: 1))
}

@Test func caseSuggestionsDoNotProvideCertainRankingContext() {
    let usage: [EntityUsage] = [.init(file: mert.file, cooccurrences: [deniz.file: 100])]
    let mentions = EntityRecognizer.recognize("Mert Aksu deniz", entities: [mert, workMert, deniz], usage: usage)
    #expect(mentions[0].candidates.map(\.file) == [workMert.file, mert.file])
}

@Test func rankingComputesEachCandidateScoreOnceAcrossRepeatedMentions() {
    let mention = EntityRecognizer.recognize("Mert Aksu", entities: [mert, workMert])[0]
    var scored: [String] = []
    let ranked = EntityRecognizer.ranked(
        Array(repeating: mention, count: 200), usage: [], context: .init(entities: [office]),
        onScoring: { scored.append($0.file) })
    #expect(scored.count == 2)
    #expect(Set(scored) == Set([mert.file, workMert.file]))
    #expect(ranked.count == 200)
    #expect(ranked.allSatisfy { $0.candidates.map(\.file) == [workMert.file, mert.file] })
}

@Test func unsafePrefixBeforeExplicitMarkerIsAlsoExcluded() throws {
    let text = "\\@Deniz !@Deniz [@Deniz |@Deniz @Deniz"
    let mentions = EntityRecognizer.recognize(text, entities: [deniz])
    #expect(mentions.count == 1)
    #expect(mentions[0].byteRange.lowerBound == text.utf8.count - 5)
    #expect(EntityRecognizer.unknownMentions("\\@Baran !@Baran [@Baran |@Baran @Baran]", entities: []).isEmpty)
    let linked = try EntityRecognizer.linking(text, mentions: mentions)
    #expect(EntityRecognizer.recognize(linked, entities: [deniz]).isEmpty)
}
