import Foundation
import Testing
import VaultFormat

struct PersonBirthdayFixture: Decodable, Sendable, CustomTestStringConvertible {
    struct Expected: Decodable, Sendable {
        let month: Int, day: Int
        let year: Int?
    }
    let key: String, value: String
    let expected: Expected?
    var testDescription: String { key + ": " + value }
}

func personBirthdayCases() throws -> [PersonBirthdayFixture] {
    try JSONDecoder().decode(
        [PersonBirthdayFixture].self, from: Data(try Fixtures.bytes(at: "dates/birthday.json")))
}

struct PersonBirthdayTests {
    @Test(arguments: try personBirthdayCases())
    func fixture(_ fixture: PersonBirthdayFixture) {
        // Read through the frontmatter parser, as a person file is.
        let text = "---\n\(fixture.key): \(fixture.value)\n---\n"
        guard case .parsed(let frontmatter) = RawDocument(bytes: Array(text.utf8)).frontmatter else {
            Issue.record("frontmatter not parsed")
            return
        }
        let found = PersonBirthday.find(in: frontmatter.fields.map { ($0.key, $0.value) })
        #expect(found?.month == fixture.expected?.month)
        #expect(found?.day == fixture.expected?.day)
        #expect(found?.year == fixture.expected?.year)
        #expect((found == nil) == (fixture.expected == nil))
    }

    /// The first readable field wins in file order: `birthday: bilinmiyor` is skipped, the quoted
    /// yearless value comes before the dated one.
    @Test func personFileReadsTheFirstReadableField() throws {
        let document = RawDocument(bytes: try Fixtures.bytes(at: "dates/birthday-person.md"))
        guard case .parsed(let frontmatter) = document.frontmatter else {
            Issue.record("frontmatter not parsed")
            return
        }
        let found = try #require(PersonBirthday.find(in: frontmatter.fields.map { ($0.key, $0.value) }))
        #expect(found.month == 6 && found.day == 21 && found.year == nil)
    }

    @Test func listsAndRawValuesAreNotRead() {
        #expect(PersonBirthday.find(in: [(key: "birthday", value: .list([], style: .inline))]) == nil)
        #expect(PersonBirthday.find(in: [(key: "birthday", value: .raw("1990-04-12"))]) == nil)
        let text = "---\nbirthday: [1990-04-12]\n---\n"
        guard case .parsed(let frontmatter) = RawDocument(bytes: Array(text.utf8)).frontmatter else { return }
        #expect(PersonBirthday.find(in: frontmatter.fields.map { ($0.key, $0.value) }) == nil)
    }

    @Test func firstDayOfTheYearlyEvent() {
        #expect(PersonBirthday.parse("1990-04-12")?.firstDay(currentYear: 2026) == CalendarDate("1990-04-12"))
        #expect(PersonBirthday.parse("--04-12")?.firstDay(currentYear: 2026) == CalendarDate("2026-04-12"))
        #expect(PersonBirthday.parse("--02-29")?.firstDay(currentYear: 2026) == CalendarDate("2024-02-29"))
        #expect(PersonBirthday.parse("--02-29")?.firstDay(currentYear: 2028) == CalendarDate("2028-02-29"))
        // A year still to come is a typo: read as yearless.
        #expect(PersonBirthday.parse("2090-04-12")?.firstDay(currentYear: 2026) == CalendarDate("2026-04-12"))
        #expect(PersonBirthday.parse("2026-04-12")?.firstDay(currentYear: 2026) == CalendarDate("2026-04-12"))
        #expect(PersonBirthday.parse("2092-02-29")?.firstDay(currentYear: 2026) == CalendarDate("2024-02-29"))
    }
}
