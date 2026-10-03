import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct SearchTests {
    @Test func personAndEventsNavigateToTheirSources() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Deniz"
        await model.search()
        #expect(model.errorText == nil)
        #expect(model.results.first?.destination == .entity(context.path))
        let events = model.results.filter { $0.group == .events }
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { if case .day = $0.destination { true } else { false } })
        #expect(model.selected == model.results.first)
    }

    @Test func sportFindsPlaceGoalAndEvents() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "spor"
        await model.search()
        #expect(model.results.contains { $0.group == .places && $0.title == "Tepe Spor Salonu" })
        #expect(model.results.contains { $0.group == .notes && $0.destination == .note("goals/Spor.md") })
        #expect(model.results.contains { $0.group == .events })
        #expect(
            model.results.map(\.group)
                == SearchGroup.allCases.flatMap { group in
                    model.results.filter { $0.group == group }.map(\.group)
                })
    }

    @Test func literalQueriesDoNotBecomeFTSOperators() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        try Data("Deniz'in AND spor planı".utf8).write(to: context.root.appendingPathComponent("notes/Literal.md"))
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        for query in ["Deniz'in", "AND", "Deniz'in AND", "\" OR *", "(", "   "] {
            model.query = query
            await model.search()
            #expect(model.errorText == nil)
            if query == "Deniz'in AND" {
                #expect(model.results.contains { $0.destination == .note("notes/Literal.md") })
            }
        }
    }

    @Test func prefixAndAliasMatchesComeBeforeOtherEntityFTSHits() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        for (file, name, aliases) in [
            ("Z.md", "Zeta", "[Sporcu]"), ("S.md", "Spor Alanı", "[]"),
        ] {
            try Data("---\ntype: place\nname: \(name)\naliases: \(aliases)\n---\n".utf8)
                .write(to: context.root.appendingPathComponent("places/" + file))
        }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "SPOR"
        await model.search()
        let places = model.results.filter { $0.group == .places }
        #expect(places.map(\.title) == ["Spor Alanı", "Zeta", "Tepe Spor Salonu"])
        #expect(places[1].detail.contains("Sporcu"))
        #expect(Set(model.results.map(\.id)).count == model.results.count)
        model.query = "salo"
        await model.search()
        #expect(model.results.first?.title == "Tepe Spor Salonu")
    }

    @Test func tasksAndJournalParagraphsHaveDayDestinations() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        try Data("## Tasks\n- [ ] Qunique görev\n\n## Journal\nQunique paragraf\n".utf8)
            .write(to: context.root.appendingPathComponent("journal/2026-10-01.md"))
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Quni"
        await model.search()
        #expect(model.results.map(\.group) == [.tasks, .notes])
        #expect(model.results.allSatisfy { $0.destination == .day(CalendarDate("2026-10-01")!) })
        #expect(model.results.allSatisfy { $0.detail == "2026-10-01" })
    }

    @Test func recentQueriesPersistDeduplicateAndKeepFive() throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        for query in ["one", "two", "three", "four", "five", "six", " TWO ", " "] {
            model.query = query
            model.rememberQuery()
        }
        #expect(model.recentQueries == ["TWO", "six", "five", "four", "three"])
        let reopened = SearchModel(store: context.store, defaults: context.defaults.defaults)
        #expect(reopened.recentQueries == model.recentQueries)
    }

    @Test func keyboardSelectionAndActivationRememberTheSearch() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Deniz"
        await model.search()
        model.moveSelection(by: -1)
        #expect(model.selected == model.results.first)
        model.moveSelection(by: 1)
        #expect(model.selected == model.results[1])
        #expect(model.activate(model.selected!) == model.results[1].destination)
        #expect(model.recentQueries == ["Deniz"])
        model.moveSelection(by: 10000)
        #expect(model.selected == model.results.last)
        model.query = ""
        #expect(model.results.isEmpty)
        #expect(model.selected == nil)
    }

    @Test func cancelledDebounceDoesNotPublishOldResults() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Deniz"
        let pending = Task { await model.search(debounce: true) }
        try await Task.sleep(for: .milliseconds(10))
        pending.cancel()
        model.query = "spor"
        await model.search()
        await pending.value
        #expect(model.errorText == nil)
        #expect(model.results.first?.group == .places)
        #expect(!model.isSearching)
    }

    @Test func aliasFTSHitShowsTheMatchingAlias() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        try Data("---\ntype: person\nname: Zeta\naliases: [Kaptan Deniz]\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("people/Zeta.md"))
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Deniz"
        await model.search()
        #expect(model.results.first?.title == "Deniz Arıkan")
        #expect(model.results.contains { $0.title == "Zeta" && $0.detail.contains("Kaptan Deniz") })
    }

    @Test func switchingVaultRejectsStaleSelection() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "Deniz"
        await model.search()
        let oldResult = try #require(model.selected)
        let other = context.directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(model.activate(oldResult) == nil)
        await model.search()
        #expect(model.results.isEmpty)
        #expect(model.errorText == nil)
    }

    @Test func accentPreservingLiteralHighlights() {
        let highlighted = SearchHighlight.text("Deniz Arıkan", query: "den")
        #expect(String(highlighted.characters) == "Deniz Arıkan")
        #expect(highlighted.runs.first?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(String(highlighted[highlighted.runs.first!.range].characters) == "Den")
    }

    @Test func unicodeTokenizerKeepsDotlessISeparate() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        try Data("Işık".utf8).write(to: context.root.appendingPathComponent("notes/Unicode.md"))
        await context.start()
        let model = SearchModel(store: context.store, defaults: context.defaults.defaults)
        model.query = "işık"
        await model.search()
        #expect(model.results.contains { $0.destination == .note("notes/Unicode.md") })
        model.query = "ışık"
        await model.search()
        #expect(!model.results.contains { $0.destination == .note("notes/Unicode.md") })
    }
}
