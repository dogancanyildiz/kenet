import EntityRecognition
import Testing
import VaultFormat

private struct RecognitionRandom: RandomNumberGenerator {
    var state: UInt64 = 0xDEA15
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Test func randomRecognitionPreservesRangesAndFullyLinkedIdempotence() throws {
    var random = RecognitionRandom()
    let cafe = KnownEntity(file: "places/Çınaraltı Kafe.md", kind: .place, name: "Çınaraltı Kafe")
    let entities = [deniz, mert, workMert, office, cafe]
    let pieces = [
        "Deniz", "Deniz abi", "Mert Aksu", "@Mert Aksu", "Liman  Ofis'te", "@Baran Tunç", "xDeniz", "Denizα", "١Deniz",
        "Denizli", "Çınaraltı Kafe", "Çınaraltı Kafe", "😀", "🧭", "[[Deniz Arıkan|Deniz]]", "`Deniz`",
        "https://Deniz/Mert", "~~~", " ", "\t", "\r\n", "\n", "\r", "#", "’e", "\u{0307}", "Su",
    ]
    for _ in 0..<500 {
        let known = entities.filter { _ in random.next() % 3 != 0 }
        var text = ""
        for _ in 0..<Int(random.next() % 60) {
            text += pieces[Int(random.next() % UInt64(pieces.count))]
            text += random.next() % 2 == 0 ? " " : ""
        }
        let mentions = EntityRecognizer.recognize(text, entities: known)
        let unknown = EntityRecognizer.unknownMentions(text, entities: known)
        let lines = RawDocument(bytes: text.utf8).lines
        for (position, spelling) in mentions.map({ ($0.position, $0.spelling) })
            + unknown.map({ ($0.position, $0.spelling) })
        {
            #expect(lines.indices.contains(position.line))
            let bytes = lines[position.line].content
            #expect(position.byteRange.lowerBound >= 0)
            #expect(position.byteRange.upperBound <= bytes.count)
            #expect(!position.byteRange.isEmpty)
            #expect(bytes[position.byteRange].elementsEqual(spelling.utf8))
        }
        let choices = Dictionary(uniqueKeysWithValues: mentions.map { ($0.position, $0.candidates[0].file) })
        let linked = try EntityRecognizer.linking(text, mentions: mentions, choices: choices)
        #expect(EntityRecognizer.recognize(linked, entities: known).isEmpty)
        #expect(try EntityRecognizer.linking(linked, mentions: []) == linked)
    }
}
