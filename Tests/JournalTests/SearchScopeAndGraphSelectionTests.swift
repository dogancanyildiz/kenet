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
        // "Kişiler" also shows places and custom-type entities; notes stay in "Hepsi" only.
        let place = SearchItem(id: "place", group: .places, title: "Kafe", detail: "", destination: .entity("places/Kafe.md"))
        let book = SearchItem(id: "book", group: .entities, title: "Kitap", detail: "", destination: .entity("books/Kitap.md"))
        #expect(SearchScope.people.includes(place) && SearchScope.people.includes(book))
        #expect(SearchScope.allCases.filter { $0.includes(note) } == [.all])
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
        let tr = Locale(identifier: "tr")
        #expect(GraphSelectionPresentation.summary(name: "Ekin", links: 3, daysSince: 0, locale: tr) == "Ekin · 3 bağ · son bugün")
        #expect(GraphSelectionPresentation.summary(name: "1 Ekim", links: 2, daysSince: nil, locale: tr) == "1 Ekim · 2 bağ")
        // English plurals: one link, one day; the two counts vary independently.
        let en = Locale(identifier: "en")
        #expect(GraphSelectionPresentation.summary(name: "Ekin", links: 1, daysSince: 1, locale: en) == "Ekin · 1 link · 1 day ago")
        #expect(GraphSelectionPresentation.summary(name: "Ekin", links: 3, daysSince: 4, locale: en) == "Ekin · 3 links · 4 days ago")
    }

    /// The people list's card drawn across rows (D3's `inkListRow(cardSegment:)`): only its ends round.
    @Test func entityListCardRoundsOnlyItsEnds() {
        #expect(InkCardSegment.position(0, of: 1) == .single)
        #expect((0..<3).map { InkCardSegment.position($0, of: 3) } == [.first, .middle, .last])
        #expect(!InkCardSegment.middle.roundsTop && !InkCardSegment.middle.roundsBottom)
        #expect(InkCardSegment.first.roundsTop && InkCardSegment.last.roundsBottom)
    }

    /// Map and Graph bylines: each count has its own English plural.
    @Test func countBylinesPluralizeEachCountInEnglish() {
        let en = Locale(identifier: "en")
        let bundle = PresentationLocalization.bundle(en)
        let one = 1
        let three = 3
        #expect(String(localized: "\(one) konum · \(one) ziyaret", bundle: bundle, locale: en) == "1 place · 1 visit")
        #expect(String(localized: "\(three) konum · \(one) ziyaret", bundle: bundle, locale: en) == "3 places · 1 visit")
        #expect(String(localized: "\(one) kişi · \(three) konum", bundle: bundle, locale: en) == "1 person · 3 places")
        #expect(
            String(localized: "\(three) kişi · \(one) konum · \(one) gün", bundle: bundle, locale: en)
                == "3 people · 1 place · 1 day")
    }

    @Test func graphSelectionCountsOnlyExplicitRelations() {
        let day = GraphModel.dayNodeID(CalendarDate("2026-10-01")!)
        let graph = GraphModel(
            nodes: [
                GraphNode(id: "people/a", name: "A", kind: .person, count: 2),
                GraphNode(id: "people/b", name: "B", kind: .person, count: 1),
                GraphNode(id: "places/c", name: "C", kind: .place, count: 1),
                GraphNode(id: day, name: "1 Ekim", kind: .day, count: 3),
            ],
            edges: [
                GraphEdge(first: day, second: "people/a", weight: 1),
                GraphEdge(first: day, second: "people/b", weight: 1),
                GraphEdge(first: "people/a", second: "places/c", weight: 1, kind: .relation),
                GraphEdge(first: "people/b", second: "people/a", weight: 1, kind: .relation),
            ])
        #expect(GraphSelectionPresentation.relationCount(of: "people/a", in: graph) == 2)
        #expect(GraphSelectionPresentation.relationCount(of: "places/c", in: graph) == 1)
        #expect(GraphSelectionPresentation.relationCount(of: day, in: graph) == 0)
    }

    @Test func entityRowMetaNamesEncounterOrVisitAndExplicitLinks() {
        let today = CalendarDate("2026-10-10")!
        let tr = Locale(identifier: "tr")
        #expect(
            EntityRowPresentation.meta(
                kind: "person", lastDate: CalendarDate("2026-10-07"), links: 14, today: today, locale: tr)
                == "Son görüşme 3 gün önce · 14 bağ")
        #expect(
            EntityRowPresentation.meta(
                kind: "place", lastDate: CalendarDate("2026-10-07"), links: 0, today: today, locale: tr)
                == "Son ziyaret 3 gün önce · 0 bağ")
        // Never mentioned: no encounter text; links alone when there are any.
        #expect(EntityRowPresentation.meta(kind: "person", lastDate: nil, links: 2, today: today, locale: tr) == "2 bağ")
        #expect(EntityRowPresentation.meta(kind: "person", lastDate: nil, links: 0, today: today, locale: tr) == nil)
        #expect(
            EntityRowPresentation.meta(kind: "person", lastDate: nil, links: 1, today: today, locale: Locale(identifier: "en"))
                == "1 link")
    }
}
