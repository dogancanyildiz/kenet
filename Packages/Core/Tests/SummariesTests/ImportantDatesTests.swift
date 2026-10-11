import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct ImportantDatesTests {
    @Test func anniversaryFixturesMatchHandWrittenExpectations() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/important-dates.json")))
                as? [[String: Any]])
        #expect(cases.count == 10)
        for fixture in cases {
            let vault = try #require(fixture["vault"] as? String)
            let today = try #require((fixture["today"] as? String).flatMap { CalendarDate($0) })
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/" + vault))
            let fields = try index.anniversaryFields().map {
                ImportantDateField(file: $0.file, key: $0.key, value: $0.value)
            }
            let result = ImportantDates.select(today: today, fields: fields)
            let expected = try #require(fixture["expected"] as? [[String: Any]])
            #expect(
                try result.map { try canonical(snapshot($0)) } == expected.map { try canonical($0) },
                Comment(rawValue: fixture["id"] as? String ?? ""))
        }
    }
}

private func snapshot(_ value: ImportantDate) -> [String: Any] {
    [
        "date": value.date.description, "daysUntil": value.daysUntil, "year": value.year,
        "file": value.file, "key": value.key,
    ]
}
