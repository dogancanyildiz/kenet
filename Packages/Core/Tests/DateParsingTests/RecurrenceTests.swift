import DateParsing
import Foundation
import Testing
import VaultFormat

struct RecurrenceDateFixture: Decodable, Sendable {
    let rule: String, after: String, completedOn: String
    let expected: String?
}
func recurrenceDateCases() throws -> [RecurrenceDateFixture] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("Fixtures").path) {
        root.deleteLastPathComponent()
    }
    return try JSONDecoder().decode(
        [RecurrenceDateFixture].self,
        from: Data(contentsOf: root.appendingPathComponent("Fixtures/dates/recurrence.json")))
}
@Test(arguments: try recurrenceDateCases())
func recurrenceDates(_ fixture: RecurrenceDateFixture) throws {
    let rule = try #require(TaskRecurrence(fixture.rule))
    #expect(
        rule.nextOccurrence(
            after: try #require(CalendarDate(fixture.after)),
            completedOn: try #require(CalendarDate(fixture.completedOn)))?.description == fixture.expected)
}

struct RecurrenceExpressionTests {
    @Test func trEnWordsAndCompletionSuffix() throws {
        for (input, rule, remainder) in [
            ("Plan her hafta", "every week", "Plan"), ("her 3 gün oku", "every 3 days", "oku"),
            ("Call every week on monday", "every monday", "Call"),
            ("Plan her ay tamamlanınca", "every month when done", "Plan"),
            ("Go every 2 years when done", "every 2 years when done", "Go"),
            ("Ara HER SALI", "every tuesday", "Ara"),
        ] {
            let result = try #require(RecurrenceExpressionParser.parse(input, language: [.turkish, .english]))
            #expect(result.recurrence.rule == rule)
            #expect(result.remainder == remainder)
        }
    }
    @Test func protectedAndUnsupportedTextStayIntact() {
        for text in [
            "`her gün`", "[[every week]]", "[her hafta](https://example.test)", "@Her Gün", "#every/week",
            "every weekday", "every 0 days", "every week on last", "Task 🔁 every day",
        ] {
            #expect(RecurrenceExpressionParser.parse(text, language: [.turkish, .english]) == nil, "\(text)")
        }
    }
    @Test func writtenRecurrenceAndDatesAreNotNaturalExpressions() {
        let day = CalendarDate("2026-10-04")!
        for text in [
            "Task 🔁 every monday", "Task 🔁 every week on friday", "Task 🔁 every month on the first monday",
            "Task 📅 2026-10-05",
        ] {
            #expect(DateExpressionParser.parse(text, today: day, language: [.english, .turkish]) == nil)
        }
    }

    @Test func standalonePriorityOnly() {
        for (text, priority, remainder) in [
            ("! Call", TaskPriority.medium, "Call"), ("Call !!", .high, "Call"), ("! Call !!", .high, "Call"),
            ("!! Call !", .high, "Call"),
        ] {
            let result = PriorityExpressionParser.parse(text)
            #expect(result?.priority == priority)
            #expect(result?.remainder == remainder)
        }
        for text in [
            "Call!!!", "!!! Call", "`! Call`", "[[Call !!]]", "Call!", "a !! b", "[Call !!](https://example.test)",
        ] { #expect(PriorityExpressionParser.parse(text) == nil) }
    }
}
