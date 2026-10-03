import DateParsing
import Foundation
import Testing
import VaultFormat

struct DateFixture: Decodable, Sendable {
    let today: String
    let language: [Language]
    let input: String
    let expectedDate: String?
    let remainder: String
    let confidence: String?
    let expression: String?
    let weekStartsOnMonday: Bool

    enum CodingKeys: String, CodingKey {
        case today, language, input, expectedDate, remainder, confidence, expression, weekStartsOnMonday
    }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode(String.self, forKey: .today)
        language = try container.decode([String].self, forKey: .language).map { try #require(Language(rawValue: $0)) }
        input = try container.decode(String.self, forKey: .input)
        expectedDate = try container.decodeIfPresent(String.self, forKey: .expectedDate)
        remainder = try container.decode(String.self, forKey: .remainder)
        confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        expression = try container.decodeIfPresent(String.self, forKey: .expression)
        weekStartsOnMonday = try container.decodeIfPresent(Bool.self, forKey: .weekStartsOnMonday) ?? true
    }
}

func dateCases() throws -> [DateFixture] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Fixtures").path) {
        root.deleteLastPathComponent()
    }
    let fixtures =
        ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.appendingPathComponent("Fixtures")
    return try JSONDecoder().decode(
        [DateFixture].self, from: Data(contentsOf: fixtures.appendingPathComponent("dates/cases.json")))
}

@Test(arguments: try dateCases())
func dateFixtures(_ fixture: DateFixture) throws {
    let result = DateExpressionParser.parse(
        fixture.input, today: try #require(CalendarDate(fixture.today)), language: fixture.language,
        weekStartsOnMonday: fixture.weekStartsOnMonday)
    #expect(result?.date.description == fixture.expectedDate)
    #expect((result?.remainder ?? fixture.input) == fixture.remainder)
    #expect(result?.confidence.rawValue == fixture.confidence)
    if let expression = fixture.expression {
        let range = try #require(result?.byteRange)
        #expect(Array(fixture.input.utf8)[range].elementsEqual(expression.utf8))
        let index = try #require(fixture.input.range(of: expression))
        let start = fixture.input[..<index.lowerBound].utf8.count
        #expect(range == start..<(start + expression.utf8.count))
    }
}
