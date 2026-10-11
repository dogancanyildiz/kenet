import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct OnThisDayTests {
    @Test func historyFixturesMatchHandWrittenExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/on-this-day.json")))
                as? [[String: Any]])
        #expect(cases.count == 9)
        for fixture in cases {
            let vault = try #require(fixture["vault"] as? String)
            let today = try #require((fixture["today"] as? String).flatMap { CalendarDate($0) })
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/" + vault))
            let result = OnThisDay.select(today: today, data: try index.onThisDayInput(for: today))
            let expected = fixture["expected"] as? [String: Any]
            #expect(
                try result.map { try canonical(snapshot($0)) } == expected.map { try canonical($0) },
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }

    @Test func todayAndLaterYearsNeverCount() throws {
        let today = try #require(CalendarDate("2026-09-20"))
        let later = try #require(CalendarDate("2027-09-20"))
        let data = OnThisDayInput(
            days: [today, later],
            mentions: [
                .init(day: today, entity: "people/Deniz Arıkan.md", name: "Deniz Arıkan", kind: .person),
                .init(day: later, entity: "places/Ev.md", name: "Ev", kind: .place),
            ])
        #expect(OnThisDay.select(today: today, data: data) == nil)
    }

    @Test func otherMonthDaysAndRepeatedDayFilesAreIgnored() throws {
        let today = try #require(CalendarDate("2026-09-20"))
        let same = try #require(CalendarDate("2025-09-20"))
        let other = try #require(CalendarDate("2025-09-19"))
        let person = OnThisDay.Entity(id: "people/Ece Yalın.md", name: "Ece Yalın")
        let data = OnThisDayInput(
            days: [same, same, other],
            mentions: [
                .init(day: other, entity: "places/Ev.md", name: "Ev", kind: .place),
                .init(day: same, entity: person.id, name: person.name, kind: .person),
                .init(day: same, entity: person.id, name: person.name, kind: .person),
            ])
        #expect(
            OnThisDay.select(today: today, data: data)
                == OnThisDay(day: same, people: [person], place: nil, otherYears: 0))
    }
}

private func snapshot(_ value: OnThisDay) -> [String: Any] {
    func entity(_ value: OnThisDay.Entity) -> [String: Any] { ["id": value.id, "name": value.name] }
    return [
        "day": value.day.description, "people": value.people.map(entity),
        "place": value.place.map(entity) as Any? ?? NSNull(), "otherYears": value.otherYears,
    ]
}
