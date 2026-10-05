import EntityRecognition
import Foundation
import Testing
import VaultFormat

struct RecognitionFixture: Decodable {
    struct Entity: Decodable {
        let file: String
        let kind: KnownEntity.Kind
        let name: String
        let qualifier: String?
        let aliases: [String]
        let linkTarget: String?
        var value: KnownEntity {
            .init(file: file, kind: kind, name: name, qualifier: qualifier, aliases: aliases, linkTarget: linkTarget)
        }
    }
    struct Usage: Decodable {
        let file: String
        let totalCount: Int
        let lastDate: String?
        let cooccurrences: [String: Int]
        var value: EntityUsage {
            .init(
                file: file, totalCount: totalCount, lastDate: lastDate.flatMap { CalendarDate($0) },
                cooccurrences: cooccurrences)
        }
    }
    let entities: [Entity]
    let usage: [Usage]?
}

struct ExpectedRecognition: Codable, Equatable {
    struct Known: Codable, Equatable {
        let line: Int
        let byteRange: [Int]
        let spelling: String
        let candidates: [String]
        let isAmbiguous: Bool
        let isCaseMismatch: Bool
        let isCertain: Bool
    }
    struct Unknown: Codable, Equatable {
        let line: Int
        let byteRange: [Int]
        let spelling: String
    }
    let mentions: [Known]
    let unknownMentions: [Unknown]
}

func fixtureRoot() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["FIXTURES_DIR"] {
        return URL(fileURLWithPath: override)
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let root = directory.appendingPathComponent("Fixtures")
        if FileManager.default.fileExists(atPath: root.path) { return root }
        directory.deleteLastPathComponent()
    }
    throw CocoaError(.fileNoSuchFile)
}

@Test(arguments: [
    "names", "unicode", "turkish", "suffix", "boundaries", "ignored", "unknown", "ambiguous", "alias-collision", "crlf",
    "empty", "nfd", "overlap", "escaped-code", "unclosed-fence", "unknown-four-words", "bom-mixed-line-endings",
    "alias-name-collision", "protected-addresses", "protected-tokens", "markdown-links", "syntax-affixes",
    "case-suggestions", "frontmatter", "table-crlf", "unicode-line-separators", "overlap-tie-first",
    "overlap-name-priority", "alias-filename", "path-link-target",
])
func recognitionFixtures(_ name: String) throws {
    let root = try fixtureRoot().appendingPathComponent("recognition/" + name)
    let input = String(decoding: try Data(contentsOf: root.appendingPathComponent("input.md")), as: UTF8.self)
    let fixture = try JSONDecoder().decode(
        RecognitionFixture.self, from: Data(contentsOf: root.appendingPathComponent("entities.json")))
    let entities = fixture.entities.map(\.value)
    let mentions = EntityRecognizer.recognize(input, entities: entities, usage: fixture.usage?.map(\.value) ?? [])
    let unknown = EntityRecognizer.unknownMentions(input, entities: entities)
    let actual = ExpectedRecognition(
        mentions: mentions.map {
            .init(
                line: $0.position.line,
                byteRange: [$0.position.byteRange.lowerBound, $0.position.byteRange.upperBound], spelling: $0.spelling,
                candidates: $0.candidates.map(\.file), isAmbiguous: $0.isAmbiguous, isCaseMismatch: $0.isCaseMismatch,
                isCertain: $0.isCertain)
        },
        unknownMentions: unknown.map {
            .init(
                line: $0.position.line,
                byteRange: [$0.position.byteRange.lowerBound, $0.position.byteRange.upperBound], spelling: $0.spelling)
        })
    let expected = try JSONDecoder().decode(
        ExpectedRecognition.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
    #expect(actual == expected)
    for (mention, item) in zip(mentions, expected.mentions) {
        #expect(Array(mention.spelling.utf8) == Array(item.spelling.utf8))
    }
    for (mention, item) in zip(unknown, expected.unknownMentions) {
        #expect(Array(mention.spelling.utf8) == Array(item.spelling.utf8))
    }
    let linked = try EntityRecognizer.linking(input, mentions: mentions)
    #expect(Array(linked.utf8) == Array(try Data(contentsOf: root.appendingPathComponent("linked.md"))))
    #expect(EntityRecognizer.recognize(linked, entities: entities).allSatisfy { !$0.isCertain })
    #expect(
        try EntityRecognizer.linking(linked, mentions: EntityRecognizer.recognize(linked, entities: entities)) == linked
    )
}
