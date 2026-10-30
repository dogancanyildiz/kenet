import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Custom entity types in the whole graph (off by default, one switch per type), the opening
/// period and the custom node's spoken label.
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
        // The book is tied to the one day that mentions it, like every entity.
        #expect(graph.neighbors(of: book) == [GraphModel.dayNodeID(CalendarDate("2026-10-01")!)])
        let dayNode = try #require(graph.nodes.first { $0.id == GraphModel.dayNodeID(CalendarDate("2026-10-01")!) })
        #expect(dayNode.name == TodayPresentation.dayTitles(today: today)(CalendarDate("2026-10-01")!))
        // People and places are read without asking for any type.
        let plain = try await context.store.computeGraphInput()
        #expect(plain.typeNames.isEmpty && !plain.entities.contains { $0.id == book })
    }

    /// The whole graph opens on the last 90 days; any other period, "Tümü" included, stays chosen.
    @Test func wholeGraphOpensOnTheLastNinetyDays() async throws {
        #expect(GraphView.initialFilter(scope: .all, focusKind: nil).period == .quarter)
        #expect(GraphView.initialFilter(scope: .all, focusKind: "book").period == .quarter)
        let context = try await graphVault()
        defer { context.clean() }
        let input = try await context.store.computeGraphInput()
        // The fixture's last day, 2026-10-04, is the 90th day back from 2027-01-01 and gone a day later.
        let edge = GraphModel.compute(input: input, filter: GraphFilter(), today: CalendarDate("2027-01-01")!)
        #expect(edge.nodes.filter { $0.kind == .day }.map(\.id) == [GraphModel.dayNodeID(today)])
        let later = CalendarDate("2027-01-02")!
        let opening = GraphModel.compute(input: input, filter: GraphFilter(), today: later)
        #expect(!opening.nodes.contains { $0.kind == .day } && opening.edges.isEmpty)
        let all = GraphModel.compute(input: input, filter: GraphFilter(period: .all), today: later)
        #expect(all.nodes.filter { $0.kind == .day }.count == 4)
    }

    @Test func focusedCustomEntitySwitchesItsTypeOn() {
        #expect(GraphView.initialFilter(scope: .all, focusKind: "book").customTypes == ["book"])
        #expect(GraphView.initialFilter(scope: .all, focusKind: "person") == GraphFilter())
        #expect(GraphView.initialFilter(scope: .all, focusKind: nil) == GraphFilter())
        let day = CalendarDate("2026-10-01")!
        #expect(GraphView.initialFilter(scope: .day(day), focusKind: nil).scope == .day(day))
    }

    /// "Graph'ta göster" follows the Graph's own type choices: built-in and custom types of the
    /// catalog, nothing else.
    @Test func graphLinkFollowsTheGraphTypeChoices() {
        let book = EntityTypeDefinition(
            id: "book", folder: "books", name: .init(tr: "Kitap", en: "Book"),
            plural: .init(tr: "Kitaplar", en: "Books"), icon: "book")
        let catalog = EntityTypeCatalog(types: [book])
        #expect(EntityView.showsGraphLink(kind: "person", types: catalog))
        #expect(EntityView.showsGraphLink(kind: "place", types: catalog))
        #expect(EntityView.showsGraphLink(kind: "book", types: catalog))
        #expect(!EntityView.showsGraphLink(kind: "book", types: EntityTypeCatalog()))
        #expect(!EntityView.showsGraphLink(kind: "film", types: catalog))
        #expect(!EntityView.showsGraphLink(kind: "goal", types: catalog))
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
