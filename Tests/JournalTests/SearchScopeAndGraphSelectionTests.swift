import Foundation
import Testing
import VaultFormat

@testable import Journal

struct SearchScopeAndGraphSelectionTests {
    @Test func searchScopesFilterByResultKindAndDayDestination() {
        let person = SearchItem(id: "person", group: .people, title: "Ekin", detail: "", destination: .entity("people/Ekin.md"))
        let event = SearchItem(id: "event", group: .events, title: "Yürüyüş", detail: "", destination: .day(CalendarDate("2026-10-01")!))
        let task = SearchItem(id: "task", group: .tasks, title: "Ara", detail: "", destination: .day(CalendarDate("2026-10-02")!))
        let note = SearchItem(id: "note", group: .notes, title: "Okuma", detail: "", destination: .note("notes/Okuma.md"))

        #expect(SearchScope.all.includes(person) && SearchScope.all.includes(note))
        #expect(SearchScope.people.includes(person) && !SearchScope.people.includes(event))
        #expect(SearchScope.events.includes(event) && !SearchScope.events.includes(task))
        #expect(SearchScope.tasks.includes(task) && !SearchScope.tasks.includes(event))
        #expect(SearchScope.days.includes(event) && SearchScope.days.includes(task))
        #expect(!SearchScope.days.includes(note))
    }

    @Test func graphSelectionCardSummaryIncludesNameLinksAndLastSeenAge() {
        #expect(
            GraphSelectionPresentation.summary(
                name: "Ekin", links: 3, daysSince: 4, locale: Locale(identifier: "tr"))
                == "Ekin · 3 bağ · son 4 gün önce")
    }
}
