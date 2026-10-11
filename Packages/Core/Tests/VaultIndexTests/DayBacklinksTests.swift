import Foundation
import Testing
import VaultFormat
import VaultIndex

struct DayBacklinksTests {
    @Test func backlinksFixtureMatchesAllRules() throws {
        let fixtures = try Fixtures.root()
        let vaultURL = fixtures.appendingPathComponent("vaults/backlinks")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: vaultURL)

        let targetDay = try #require(CalendarDate("2026-10-02"))
        let links = try index.dayBacklinks(for: targetDay)

        // 1. Total count: note (3 lines), person (1 line), place (1 line), other day (1 line) = 6
        #expect(links.count == 6)

        // 2. The day itself (journal/2026-10-02.md) MUST be excluded.
        #expect(!links.contains { $0.file == "journal/2026-10-02.md" })

        // 3. Another day is included with its date as name and day as kind.
        let otherDay = try #require(links.first { $0.file == "journal/2026-10-01.md" })
        #expect(otherDay.kind == "day")
        #expect(otherDay.name == "2026-10-01")
        #expect(otherDay.text.contains("[[2026-10-02]]"))

        // 4. Person entity is included with entity name and person kind.
        let person = try #require(links.first { $0.file == "people/Deniz Arıkan.md" })
        #expect(person.kind == "person")
        #expect(person.name == "Deniz Arıkan")
        #expect(person.text == "[[2026-10-02]] günü toplantı yapılacak.")

        // 5. Place entity is included with entity name and place kind.
        let place = try #require(links.first { $0.file == "places/Liman Ofis.md" })
        #expect(place.kind == "place")
        #expect(place.name == "Liman Ofis")
        #expect(place.text == "Liman Ofis ziyareti [[2026-10-02]] tarihinde.")

        // 6. Note with two separate lines produces two separate rows.
        let noteLinks = links.filter { $0.file == "notes/Proje Fikirleri.md" }
        #expect(noteLinks.count == 3)
        #expect(noteLinks[0].line == 3)
        #expect(noteLinks[0].text == "[[2026-10-02]] için ilk plan satırı.")
        #expect(noteLinks[0].kind == "note")
        #expect(noteLinks[0].name == "Proje Fikirleri")

        #expect(noteLinks[1].line == 6)
        #expect(noteLinks[1].text == "[[2026-10-02]] için ikinci satır.")

        // 7. Same line with two wikilinks produces exactly one row.
        #expect(noteLinks[2].line == 7)
        #expect(noteLinks[2].text == "Tek satırda iki bağlantı [[2026-10-02]] ve yine [[2026-10-02]].")

        // 8. Inline code (`[[2026-10-02]]`) does not appear as a backlink.
        #expect(!links.contains { $0.text.contains("Kod içinde") })

        // 9. Unresolved link ([[2026-10-05]]) does not appear when querying for 2026-10-05.
        let unresolvedDay = try #require(CalendarDate("2026-10-05"))
        let unresolvedLinks = try index.dayBacklinks(for: unresolvedDay)
        #expect(unresolvedLinks.isEmpty)

        // 10. Query for a day with no backlinks returns empty list.
        let emptyDay = try #require(CalendarDate("2026-10-01"))
        let emptyLinks = try index.dayBacklinks(for: emptyDay)
        #expect(emptyLinks.isEmpty)
    }
}
