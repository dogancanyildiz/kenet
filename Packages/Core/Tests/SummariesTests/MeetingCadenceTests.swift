import Foundation
import Summaries
import Testing
import VaultFormat

struct MeetingCadenceTests {
    @Test func positiveDaySpellingsMatchFixture() throws {
        let fixture = try load()
        let spellings = try #require(fixture["spellings"] as? [[String: Any]])
        #expect(spellings.count == 15)
        for row in spellings {
            let value = try #require(row["value"] as? String)
            let parsed = PersonCadence.positiveDays(spelling: value)
            if row["days"] is NSNull || row["days"] == nil {
                #expect(parsed == nil, Comment(rawValue: value))
            } else {
                #expect(parsed == row["days"] as? Int, Comment(rawValue: value))
            }
        }
    }

    @Test func listsMatchHandWrittenCases() throws {
        let cases = try cases()
        #expect(cases.count == 6)
        for fixture in cases {
            let listed = try list(fixture)
            let overdue = try #require(fixture["overdue"] as? [[String: Any]])
            let never = try #require(fixture["never"] as? [String])
            #expect(listed.overdue.map(\.id) == overdue.map { $0["id"] as? String }, Comment(rawValue: id(fixture)))
            #expect(
                listed.overdue.map(\.elapsedDays) == overdue.map { $0["elapsedDays"] as? Int },
                Comment(rawValue: id(fixture)))
            #expect(
                listed.overdue.map(\.overdueDays) == overdue.map { $0["overdueDays"] as? Int },
                Comment(rawValue: id(fixture)))
            #expect(listed.never.map(\.id) == never, Comment(rawValue: id(fixture)))
        }
    }

    /// The snooze date itself stays hidden; the next day the person returns.
    @Test func snoozeIncludesTheUntilDay() throws {
        let cases = try cases()
        let hidden = try #require(cases.first { id($0) == "on-snooze-day" })
        let returned = try #require(cases.first { id($0) == "day-after-snooze" })
        let fela = "people/Fela Narin.md"
        let hiddenList = try list(hidden)
        let returnedList = try list(returned)
        #expect(hiddenList.overdue.map(\.id).contains(fela) == false)
        #expect(hiddenList.never.map(\.id).contains(fela) == false)
        #expect(returnedList.overdue.map(\.id).contains(fela))
    }

    @Test func pausedPersonIsOmitted() throws {
        for fixture in try cases() where fixture["source"] as? String == "vault" {
            let listed = try list(fixture)
            let ids = listed.overdue.map(\.id) + listed.never.map(\.id)
            #expect(!ids.contains("people/Hakan Eren.md"), Comment(rawValue: id(fixture)))
            #expect(!ids.contains("people/Jale Kurt.md"), Comment(rawValue: id(fixture)))
            #expect(!ids.contains("people/Vera Lale.md"), Comment(rawValue: id(fixture)))
        }
    }

    /// The order is a property of the people, not of the array they arrive in.
    @Test func inputOrderDoesNotChangeTheList() throws {
        for fixture in try cases() {
            let today = try #require((fixture["today"] as? String).flatMap { CalendarDate($0) })
            let threshold = try #require(fixture["threshold"] as? Int)
            let source = try people(for: fixture)
            let forward = MeetingCadence.list(people: source, today: today, fallbackThreshold: threshold)
            let backward = MeetingCadence.list(
                people: Array(source.reversed()), today: today, fallbackThreshold: threshold)
            #expect(forward == backward, Comment(rawValue: id(fixture)))
        }
    }

    private func list(_ fixture: [String: Any]) throws -> CadenceList {
        let today = try #require((fixture["today"] as? String).flatMap { CalendarDate($0) })
        let threshold = try #require(fixture["threshold"] as? Int)
        let source = try people(for: fixture)
        return MeetingCadence.list(people: source, today: today, fallbackThreshold: threshold)
    }

    private func people(for fixture: [String: Any]) throws -> [CadencePerson] {
        let rows: [[String: Any]]
        if fixture["source"] as? String == "inline" {
            rows = try #require(fixture["people"] as? [[String: Any]])
        } else {
            rows = try #require(load()["people"] as? [[String: Any]])
        }
        return try rows.map { row in
            let fields = try #require(row["fields"] as? [[String: Any]]).map { field in
                PersonCadenceField(
                    key: try #require(field["key"] as? String),
                    kind: try #require(field["kind"] as? String),
                    value: try #require(field["value"] as? String))
            }
            let last = (row["lastDay"] as? String).flatMap { CalendarDate($0) }
            return CadencePerson(
                id: try #require(row["id"] as? String),
                name: try #require(row["name"] as? String),
                lastDay: last,
                cadence: PersonCadence.parse(fields))
        }
    }

    private func cases() throws -> [[String: Any]] {
        try #require(load()["cases"] as? [[String: Any]])
    }

    private func load() throws -> [String: Any] {
        let data = try Data(contentsOf: fixtureDirectory().appendingPathComponent("summaries/cadence.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func id(_ fixture: [String: Any]) -> String { fixture["id"] as? String ?? "" }
}
