import DateParsing
import Foundation
import Testing
import VaultFormat

struct QuickEntryFixture: Decodable, Sendable {
    struct ExpectedToken: Decodable, Sendable {
        let range: [Int]
        let expression: String
        let kind: String
        let value: String
        let confidence: String
    }
    let id: String
    let today: String
    let language: [String]
    let input: String
    let suppressed: [[Int]]
    let remainder: String
    let tokens: [ExpectedToken]
}

func quickEntryCases() throws -> [QuickEntryFixture] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Fixtures").path) {
        root.deleteLastPathComponent()
    }
    let fixtures =
        ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.appendingPathComponent("Fixtures")
    return try JSONDecoder().decode(
        [QuickEntryFixture].self, from: Data(contentsOf: fixtures.appendingPathComponent("dates/quick-entry.json")))
}

@Test(arguments: try quickEntryCases())
func quickEntryFixtures(_ fixture: QuickEntryFixture) throws {
    let result = QuickEntryAnalysis.analyze(
        fixture.input, today: try #require(CalendarDate(fixture.today)),
        language: try fixture.language.map { try #require(Language(rawValue: $0)) },
        suppressedRanges: fixture.suppressed.map { $0[0]..<$0[1] })
    #expect(result.remainder == fixture.remainder, "\(fixture.id)")
    #expect(result.tokens.count == fixture.tokens.count)
    for (token, expected) in zip(result.tokens, fixture.tokens) {
        #expect(token.byteRange == expected.range[0]..<expected.range[1])
        #expect(Array(fixture.input.utf8)[token.byteRange].elementsEqual(expected.expression.utf8))
        #expect(String(describing: token.kind) == expected.kind)
        #expect(token.confidence.rawValue == expected.confidence)
        switch token.value {
        case .recurrence(let rule): #expect(rule.rule == expected.value)
        case .priority(let priority): #expect(String(describing: priority) == expected.value)
        case .date(let date): #expect(date.description == expected.value)
        }
    }
    #expect(removingQuickEntryTokens(result.tokens, from: fixture.input) == result.remainder)
}

// Reconstruct independently from original ranges with the documented whitespace policy.
private func removingQuickEntryTokens(_ tokens: [QuickEntryAnalysis.Token], from text: String) -> String {
    var bytes = Array(text.utf8)
    for range in tokens.map(\.byteRange).sorted(by: { $0.lowerBound > $1.lowerBound }) {
        guard range.upperBound <= bytes.count else { return "Invalid removal range" }
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower > 0 && [UInt8(32), 9].contains(bytes[lower - 1]) { lower -= 1 }
        while upper < bytes.count && [UInt8(32), 9].contains(bytes[upper]) { upper += 1 }
        let join =
            lower > 0 && upper < bytes.count && ![UInt8(10), 13].contains(bytes[lower - 1])
            && ![UInt8(10), 13].contains(bytes[upper])
            && (lower < range.lowerBound || upper > range.upperBound)
        bytes.replaceSubrange(lower..<upper, with: join ? [32] : [])
    }
    return String(decoding: bytes, as: UTF8.self)
}

@Test func quickEntryRandomMatchesExistingChain() throws {
    var state: UInt64 = 73
    func next(_ count: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Int((state >> 32) % UInt64(count))
    }
    let pieces = [
        "her hafta", "every day", "her salı", "yarın", "tomorrow", "next", "week", "haftaya salı", "2.5 kg", "5/10",
        "!", "!!", "@Cuma", "[[yarın]]", "`every week`", "[tomorrow](x)", "😊", "çığ", "İ", " ", "  ", "\t", "\r\n",
    ]
    let today = try #require(CalendarDate("2026-10-05"))
    for iteration in 0..<2000 {
        let text = (0..<next(20)).map { _ in pieces[next(pieces.count)] }.joined()
        let language: [Language] = iteration.isMultiple(of: 2) ? [.turkish, .english] : [.english, .turkish]
        let recurrence = RecurrenceExpressionParser.parse(text, language: language)
        let priority = PriorityExpressionParser.parse(recurrence?.remainder ?? text)
        let date = DateExpressionParser.parse(
            priority?.remainder ?? recurrence?.remainder ?? text, today: today, language: language)
        let result = QuickEntryAnalysis.analyze(text, today: today, language: language)
        #expect(result.remainder == date?.remainder ?? priority?.remainder ?? recurrence?.remainder ?? text)
        let rules = result.tokens.compactMap { token -> TaskRecurrence? in
            if case .recurrence(let rule) = token.value { return rule }
            return nil
        }
        #expect(rules.allSatisfy { $0 == recurrence?.recurrence })
        #expect(rules.isEmpty == (recurrence == nil))
        let priorities = result.tokens.compactMap { token -> TaskPriority? in
            if case .priority(let value) = token.value { return value }
            return nil
        }
        #expect(priorities.isEmpty == (priority == nil))
        #expect((priorities.contains(.high) ? TaskPriority.high : priorities.first) == priority?.priority)
        let dates = result.tokens.compactMap { token -> CalendarDate? in
            if case .date(let value) = token.value { return value }
            return nil
        }
        #expect(dates.allSatisfy { $0 == date?.date })
        #expect(dates.isEmpty == (date == nil))
        for (index, token) in result.tokens.enumerated() {
            #expect(token.byteRange.lowerBound >= 0 && token.byteRange.upperBound <= text.utf8.count)
            #expect(!token.byteRange.isEmpty)
            #expect(index == 0 || result.tokens[index - 1].byteRange.upperBound <= token.byteRange.lowerBound)
            if case .date = token.value { #expect(token.confidence == date?.confidence) }
        }
        #expect(removingQuickEntryTokens(result.tokens, from: text) == result.remainder)
        #expect(QuickEntryAnalysis.analyze(text, today: today, language: language) == result)
    }
}
