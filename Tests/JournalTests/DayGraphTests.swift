import ForceLayout
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// A day's own graph (`GraphFilter.scope == .day`): the query, the model, the screen model and the
/// day page's icon rule, on a copy of the graph fixture vault.
@MainActor struct DayGraphTests {
    let book = "books/Örnek Kitap.md"
    let deniz = "people/Deniz Arıkan.md"
    let selin = "people/Selin Korkmaz.md"
    let kafe = "places/Çınaraltı Kafe.md"
    let ofis = "places/Liman Ofis.md"
    let first = CalendarDate("2026-10-01")!
    let second = CalendarDate("2026-10-02")!

    /// Copies the graph fixture vault and adds a day whose only link resolves to nothing.
    private func graphVault() async throws -> TaskTestContext {
        let context = try TaskTestContext()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
        try FileManager.default.copyItem(at: root, to: context.root)
        try "## Events\n- 09:00 [[Olmayan Kayıt]] aradı.\n".write(
            to: context.root.appendingPathComponent("journal/2026-10-05.md"), atomically: true, encoding: .utf8)
        await context.start()
        return context
    }

    @Test func dayGraphTiesEveryKindToTheDayAndIgnoresTheFilter() async throws {
        let context = try await graphVault()
        defer { context.clean() }
        let input = try await context.store.computeDayGraphInput(on: first)
        let dayID = GraphModel.dayNodeID(first)
        let graph = GraphModel.compute(input: input, filter: GraphFilter(scope: .day(first)), today: second)
        #expect(Set(graph.nodes.map(\.id)) == [dayID, book, deniz, selin, kafe, ofis])
        #expect(graph.nodes.first { $0.id == book }?.kind == .custom("book"))
        #expect(graph.nodes.first { $0.id == dayID }?.kind == .day)
        // Named as the day page's headline (menu, label, VoiceOver), never the ISO text.
        let dayName = try #require(graph.nodes.first { $0.id == dayID }?.name)
        #expect(dayName == TodayPresentation.dayTitles(today: second)(first) && dayName != first.description)
        #expect(
            !dayName.contains("2026")
                && TodayPresentation.dayTitles(today: CalendarDate("2027-01-01")!)(first).contains("2026"))
        let typeName = EntityTypeChoices.choices(context.store.entityTypes).first { $0.id == "book" }?.name
        #expect(graph.nodes.first { $0.id == book }?.typeName == typeName)
        // The day is tied to all five; only the event pairs are tied to each other.
        #expect(graph.neighbors(of: dayID) == [book, deniz, selin, kafe, ofis])
        #expect(
            graph.edges.filter { $0.first != dayID && $0.second != dayID } == [
                GraphEdge(first: deniz, second: kafe, weight: 1),
                GraphEdge(first: selin, second: ofis, weight: 1),
            ])
        #expect(graph.edges.allSatisfy { $0.weight == 1 })
        // Period, kind switches and the threshold belong to the whole graph only.
        var narrowed = GraphFilter(
            people: false, places: false, days: false, period: .month, minimumWeight: 3, scope: .day(first))
        narrowed.setCustomType("book", false)
        let same = GraphModel.compute(input: input, filter: narrowed, today: CalendarDate("2027-01-01")!)
        #expect(same.nodes.map(\.id) == graph.nodes.map(\.id))
        #expect(same.edges == graph.edges)
    }

    @Test func dayGraphOfABusyDayCountsBlocksOncePerPair() async throws {
        let context = try await graphVault()
        defer { context.clean() }
        let input = try await context.store.computeDayGraphInput(on: second)
        let graph = GraphModel.compute(input: input, filter: GraphFilter(scope: .day(second)), today: second)
        let dayID = GraphModel.dayNodeID(second)
        #expect(graph.nodes.count == 5)
        #expect(graph.nodes.first { $0.id == deniz }?.count == 4)
        #expect(graph.nodes.first { $0.id == dayID }?.count == 13)
        // Event, task and paragraph: Deniz–Selin twice, still one day.
        #expect(
            graph.edges.filter { $0.first != dayID } == [
                GraphEdge(first: deniz, second: selin, weight: 1),
                GraphEdge(first: deniz, second: ofis, weight: 1),
                GraphEdge(first: deniz, second: kafe, weight: 1),
                GraphEdge(first: selin, second: ofis, weight: 1),
                GraphEdge(first: selin, second: kafe, weight: 1),
            ])
        #expect(graph.edges.count == 9)
    }

    @Test func iconIsOfferedOnlyOnDaysLinkingAnEntity() async throws {
        let context = try await graphVault()
        defer { context.clean() }
        let store = context.store
        #expect(DayGraphEntry.isOffered(try await store.computeDayGraphInput(on: first), on: first))
        let unresolved = CalendarDate("2026-10-05")!
        #expect(!DayGraphEntry.isOffered(try await store.computeDayGraphInput(on: unresolved), on: unresolved))
        let empty = CalendarDate("2026-09-30")!
        #expect(!DayGraphEntry.isOffered(try await store.computeDayGraphInput(on: empty), on: empty))
        // An input of another day offers nothing for this one.
        #expect(!DayGraphEntry.isOffered(try await store.computeDayGraphInput(on: first), on: second))
    }

    @Test func screenModelLoadsTheDayGraph() async throws {
        let context = try await graphVault()
        defer { context.clean() }
        let model = GraphScreenModel(
            store: context.store, filter: GraphView.initialFilter(scope: .day(first), focusKind: nil))
        await model.load(today: second, live: false)
        #expect(model.graph.nodes.count == 6)
        #expect(model.graph.neighbors(of: GraphModel.dayNodeID(first)).count == 5)
        // The day settles in the middle: nearest of all nodes to their center.
        let points = model.positions
        let center = GraphPoint(
            x: points.values.map(\.x).reduce(0, +) / Double(points.count),
            y: points.values.map(\.y).reduce(0, +) / Double(points.count))
        let nearest = points.min { $0.value.distance(to: center) < $1.value.distance(to: center) }?.key
        #expect(nearest == GraphModel.dayNodeID(first))
        let empty = GraphScreenModel(
            store: context.store,
            filter: GraphView.initialFilter(scope: .day(CalendarDate("2026-10-05")!), focusKind: nil))
        await empty.load(today: second, live: false)
        #expect(empty.graph.nodes.isEmpty)
    }
}
