import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Custom entity types in the whole graph (off by default, one switch per type), the day layer's
/// period switch and the custom node's spoken label.
@MainActor struct GraphCustomTypeTests {
    let book = "books/Örnek Kitap.md"
    let today = CalendarDate("2026-10-04")!

    private func graphVault() async throws -> TaskTestContext {
        let context = try TaskTestContext()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
        try FileManager.default.copyItem(at: root, to: context.root)
        await context.start()
        return context
    }

    @Test func customTypesAreOffByDefaultAndSwitchOnPerType() async throws {
        let context = try await graphVault()
        defer { context.clean() }
        let input = try await context.store.computeGraphInput(customTypes: ["book", "film"])
        #expect(input.typeNames.keys.sorted() == ["book"])
        #expect(input.entities.contains { $0.id == book })
        #expect(!GraphModel.compute(input: input, filter: GraphFilter(), today: today).nodes.contains { $0.id == book })
        #expect(!GraphFilterMenu.isActive(GraphFilter()))
        var filter = GraphFilter()
        filter.setCustomType("book", true)
        #expect(GraphFilterMenu.isActive(filter))
        let graph = GraphModel.compute(input: input, filter: filter, today: today)
        let node = try #require(graph.nodes.first { $0.id == book })
        #expect(node.kind == .custom("book") && node.count == 1)
        // People and places as without the type, plus the book.
        #expect(
            graph.nodes.count == GraphModel.compute(input: input, filter: GraphFilter(), today: today).nodes.count + 1)
        // The book shares no block: no entity edge, but the day layer ties it to its day.
        #expect(graph.neighbors(of: book).isEmpty)
        filter.setDays(true)
        filter.period = .all
        let withDays = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(withDays.neighbors(of: book) == [GraphModel.dayNodeID(CalendarDate("2026-10-01")!)])
        // People and places are read without asking for any type.
        let plain = try await context.store.computeGraphInput()
        #expect(plain.typeNames.isEmpty && !plain.entities.contains { $0.id == book })
    }

    @Test func dayLayerNarrowsTheWholePeriodOnceAndKeepsOtherChoices() {
        var filter = GraphFilter()
        filter.setDays(true)
        #expect(filter.days && filter.period == .quarter)
        // The user may choose "Tümü" again; the layer staying on does not undo that.
        filter.period = .all
        filter.setDays(true)
        #expect(filter.period == .all)
        filter.setDays(false)
        #expect(!filter.days && filter.period == .all)
        var month = GraphFilter(period: .month)
        month.setDays(true)
        #expect(month.days && month.period == .month)
    }

    @Test func focusedCustomEntitySwitchesItsTypeOn() {
        #expect(GraphView.initialFilter(scope: .all, focusKind: "book").customTypes == ["book"])
        #expect(GraphView.initialFilter(scope: .all, focusKind: "person") == GraphFilter())
        #expect(GraphView.initialFilter(scope: .all, focusKind: nil) == GraphFilter())
        let day = CalendarDate("2026-10-01")!
        #expect(GraphView.initialFilter(scope: .day(day), focusKind: nil).scope == .day(day))
    }

    @Test func customNodeSpeaksItsTypeName() {
        let nodes = [
            GraphNode(id: "books/a.md", name: "Örnek Kitap", kind: .custom("book"), count: 1, typeName: "Kitap"),
            GraphNode(id: "films/b.md", name: "Uzun Film", kind: .custom("film"), count: 1),
        ]
        let list = GraphAccessibleNode.list(from: GraphModel(nodes: nodes, edges: []))
        #expect(list[0].accessibilityLabel() == "Örnek Kitap, Kitap, " + String(localized: "\(0) komşu"))
        #expect(list[1].accessibilityLabel().contains(String(localized: "Varlık")))
        #expect(GraphLegend.customTypeNames(in: GraphModel(nodes: nodes, edges: [])) == ["film", "Kitap"])
        #expect(
            GraphLegend.customTypeNames(in: GraphModel(nodes: nodes, edges: []), plurals: ["book": "Kitaplar"])
                == ["film", "Kitaplar"])
    }
}
