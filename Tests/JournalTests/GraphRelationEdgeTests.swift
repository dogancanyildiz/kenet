import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct GraphRelationEdgeTests {
    @Test func explicitPairsSurviveAPeriodWithoutDaysAndStayUnique() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        var input = try await context.store.computeGraphInput(customTypes: ["book"])
        let relations = try await context.store.computeExplicitRelations()
        input.relations = relations + relations
        let graph = GraphModel.compute(
            input: input,
            filter: GraphFilter(period: .month, customTypes: ["book"]),
            today: CalendarDate("2027-10-01")!)
        let edges = graph.edges.filter { $0.kind == .relation }
        #expect(edges.count == 2)
        #expect(Set(edges.map { [$0.first, $0.second].sorted() }).count == edges.count)
        #expect(edges.allSatisfy { $0.weight == 1 })
        // No day of the period: the relations are all there is.
        #expect(graph.edges.count == edges.count && !graph.nodes.contains { $0.kind == .day })
    }

    @Test func dayGraphAlsoIncludesExplicitPairs() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        let date = CalendarDate("2026-10-01")!
        var input = try await context.store.computeDayGraphInput(on: date)
        input.relations = try await context.store.computeExplicitRelations()
        let graph = GraphModel.compute(input: input, filter: GraphFilter(scope: .day(date)), today: date)
        #expect(graph.edges.filter { $0.kind == .relation }.count == 2)
        #expect(graph.edges.contains { $0.kind == .day })
        #expect(graph.edges.filter { $0.kind == .relation }.allSatisfy { $0.weight == 1 })
        let screen = GraphScreenModel(store: context.store, filter: GraphFilter(scope: .day(date)))
        await screen.load(today: date, live: false)
        #expect(screen.graph.edges == graph.edges)
    }

    @Test func lineWeightsDistinguishKindsWithoutColor() {
        #expect(GraphEdgeStyle.width(.relation, scale: 3) == InkStroke.highPriority)
        #expect(GraphEdgeStyle.width(.day, scale: 3) == InkStroke.hairline(scale: 3))
        #expect(GraphEdgeStyle.width(.relation, scale: 1) > GraphEdgeStyle.width(.day, scale: 1))
        #expect(VoiceOverCopy.graphRelationLabel(first: "A", second: "B") == String(localized: "Bağ: \("A"), \("B")"))
    }

    @Test func relationEdgesJoinOnlyVisibleNodes() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        var input = try await context.store.computeGraphInput()
        input.relations = try await context.store.computeExplicitRelations()
        // The book type is off: its relation to Deniz has no node to land on.
        #expect(input.relations.contains { $0.source == "books/Örnek Kitap.md" })
        let graph = GraphModel.compute(input: input, filter: GraphFilter(), today: CalendarDate("2026-10-05")!)
        let ids = Set(graph.nodes.map(\.id))
        #expect(graph.edges.allSatisfy { ids.contains($0.first) && ids.contains($0.second) })
        #expect(graph.edges.filter { $0.kind == .relation }.count == 1)
        var hidden = GraphFilter()
        hidden.people = false
        let places = GraphModel.compute(input: input, filter: hidden, today: CalendarDate("2026-10-05")!)
        #expect(!places.edges.contains { $0.kind == .relation })
    }

    @Test func dayGraphDrawsOnlyTheDaysRelations() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        // Deniz and Selin are mentioned on this day; the book is not.
        let date = CalendarDate("2026-10-04")!
        var input = try await context.store.computeDayGraphInput(on: date)
        input.relations = try await context.store.computeExplicitRelations()
        let graph = GraphModel.compute(input: input, filter: GraphFilter(scope: .day(date)), today: date)
        let pairs = graph.edges.filter { $0.kind == .relation }.map { [$0.first, $0.second] }
        #expect(pairs == [["people/Deniz Arıkan.md", "people/Selin Korkmaz.md"]])
        #expect(!graph.edges.contains { $0.first == "books/Örnek Kitap.md" || $0.second == "books/Örnek Kitap.md" })
    }

    @Test func aRelationIsTheOnlyEdgeBetweenTwoEntities() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        var input = try await context.store.computeGraphInput()
        input.relations = try await context.store.computeExplicitRelations()
        let filter = GraphFilter(period: .all)
        let today = CalendarDate("2026-10-05")!
        // Deniz and Selin share blocks on three days: without the relation nothing ties them.
        var unrelated = input
        unrelated.relations = []
        let plain = GraphModel.compute(input: unrelated, filter: filter, today: today)
        let pair = { (edge: GraphEdge) in
            [edge.first, edge.second] == ["people/Deniz Arıkan.md", "people/Selin Korkmaz.md"]
        }
        #expect(plain.edges.filter(pair).isEmpty)
        #expect(plain.edges.allSatisfy { $0.kind == .day })
        // Written in both pages and twice in one: still one heavy edge, and the only entity pair.
        let graph = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(graph.edges.filter(pair).map(\.kind) == [.relation])
        #expect(graph.edges.filter { $0.kind != .day }.count == 1)
        #expect(graph.edges.count == plain.edges.count + 1)
    }
}
