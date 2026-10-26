import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct GraphRelationEdgeTests {
    @Test func explicitPairsSurvivePeriodAndThresholdAndStayUnique() async throws {
        let context = try await EntityRelationsModelTests.context()
        defer { context.clean() }
        var input = try await context.store.computeGraphInput(customTypes: ["book"])
        let relations = try await context.store.computeExplicitRelations()
        input.relations = relations + relations
        let graph = GraphModel.compute(
            input: input,
            filter: GraphFilter(period: .month, minimumWeight: 999, customTypes: ["book"]),
            today: CalendarDate("2027-10-01")!)
        let edges = graph.edges.filter { $0.kind == .relation }
        #expect(edges.count == 2)
        #expect(Set(edges.map { [$0.first, $0.second].sorted() }).count == edges.count)
        #expect(edges.allSatisfy { $0.weight == 1 })
        #expect(graph.edges.count == edges.count)
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
        #expect(GraphEdgeStyle.width(.relation, scale: 3) > GraphEdgeStyle.width(.cooccurrence, scale: 3))
        #expect(GraphEdgeStyle.width(.cooccurrence, scale: 3) > GraphEdgeStyle.width(.day, scale: 3))
        #expect(VoiceOverCopy.graphRelationLabel(first: "A", second: "B") == String(localized: "Bağ: \("A"), \("B")"))
    }
}
