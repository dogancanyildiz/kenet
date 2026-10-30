import EntityRecognition
import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@MainActor struct GraphMapTests {
    let today = CalendarDate("2026-10-04")!
    @Test func sampleGraphTiesEveryDayToItsEntitiesAndNoEntityToAnother() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let input = try await context.store.computeGraphInput()
        let graph = GraphModel.compute(input: input, filter: GraphFilter(), today: today)
        // Ten entities and the fourteen written days of the last 90 days.
        #expect(graph.nodes.filter { $0.kind != .day }.count == 10)
        #expect(graph.nodes.filter { $0.kind == .day }.count == 14)
        // Deniz and Tepe Spor Salonu share days and blocks; only their days tie them.
        let deniz = "people/Deniz Arıkan.md"
        #expect(!graph.neighbors(of: deniz).contains("places/Tepe Spor Salonu.md"))
        #expect(graph.neighbors(of: deniz).allSatisfy { $0.hasPrefix("day:") })
        #expect(graph.neighbors(of: deniz).contains("day:2026-09-25"))
        #expect(graph.edges.allSatisfy { $0.kind == .day && $0.weight == 1 && $0.first.hasPrefix("day:") })
        #expect(graph.edges.count == input.days.reduce(0) { $0 + $1.mentions.count })
        // Over the whole vault a node is sized by every link into its entity.
        let all = GraphModel.compute(input: input, filter: GraphFilter(period: .all), today: today)
        for usage in context.store.entityUsage {
            #expect(all.nodes.first { $0.id == usage.file }?.count == usage.totalCount)
        }
    }
    @Test func graphFixtureTiesDaysToEntitiesAndSharedBlocksToNothing() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
        try FileManager.default.copyItem(at: root, to: context.root)
        await context.start()
        let input = try await context.store.computeGraphInput()
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        #expect(input == GraphInput(snapshot: try index.snapshot(), entities: context.store.content.entities))
        let graph = GraphModel.compute(input: input, filter: GraphFilter(), today: today)
        #expect(graph.nodes.count == 9 + 4)
        // Deniz and Selin share an event, a task and a paragraph: still no edge between them.
        #expect(!graph.neighbors(of: "people/Deniz Arıkan.md").contains("people/Selin Korkmaz.md"))
        #expect(graph.edges.count == 18 && graph.edges.allSatisfy { $0.kind == .day && $0.weight == 1 })
        for day in input.days {
            #expect(graph.neighbors(of: GraphModel.dayNodeID(day.date)) == Set(day.mentions.keys))
        }
        let people = GraphModel.compute(input: input, filter: GraphFilter(places: false), today: today)
        #expect(people.nodes.allSatisfy { $0.kind == .person || $0.kind == .day })
        #expect(people.edges.count == 11 && people.edges.allSatisfy { $0.second.hasPrefix("people/") })
    }

    @Test func filtersNarrowDaysAndKinds() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let input = try await context.store.computeGraphInput()
        var filter = GraphFilter()
        filter.people = false
        // Two of the fourteen days mention only people: with people off they have no node.
        let places = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(places.nodes.filter { $0.kind == .place }.count == 4)
        #expect(places.nodes.filter { $0.kind == .day }.count == 12)
        #expect(places.nodes.allSatisfy { $0.kind == .place || $0.kind == .day })
        #expect(places.edges.allSatisfy { $0.second.hasPrefix("places/") })
        filter.people = true
        filter.period = .month
        let old = GraphModel.compute(input: input, filter: filter, today: CalendarDate("2026-10-27")!)
        #expect(old.edges.isEmpty && old.nodes.filter { $0.kind == .day }.isEmpty)
        #expect(old.nodes.allSatisfy { $0.count == 0 })
    }
    @Test func periodNarrowsDaysAndTheirEdgesButNeverARelation() throws {
        let (a, b, c) = ("people/a", "people/b", "places/c")
        var input = GraphInput()
        input.entities = [entity(a), entity(b), entity(c, kind: "place")]
        input.totals = [a: 8, b: 4, c: 1]
        input.days = [
            .init(date: today.addingDays(-120)!, mentions: [a: 1, b: 1]),
            .init(date: today.addingDays(-30)!, mentions: [a: 1, b: 1]),
            .init(date: today.addingDays(-29)!, mentions: [a: 4, b: 1]),
            .init(date: today, mentions: [a: 1, b: 1, c: 1]),
            .init(date: today.addingDays(1)!, mentions: [a: 1, b: 1]),
        ]
        input.relations = [try relation(c, a)]
        var filter = GraphFilter(period: .month)
        let graph = GraphModel.compute(input: input, filter: filter, today: today)
        let recent = [GraphModel.dayNodeID(today.addingDays(-29)!), GraphModel.dayNodeID(today)]
        #expect(graph.nodes.filter { $0.kind == .day }.map(\.id) == recent)
        // Days shared by a and b tie nothing; the written relation c–a is the one entity edge.
        let relation = GraphEdge(first: a, second: c, weight: 1, kind: .relation)
        #expect(
            graph.edges == [
                GraphEdge(first: recent[0], second: a, weight: 1),
                GraphEdge(first: recent[0], second: b, weight: 1),
                GraphEdge(first: recent[1], second: a, weight: 1),
                GraphEdge(first: recent[1], second: b, weight: 1),
                GraphEdge(first: recent[1], second: c, weight: 1),
                relation,
            ])
        #expect(graph.nodes.first { $0.id == a }?.count == 5)
        #expect(graph.nodes.first { $0.id == recent[0] }?.count == 5)
        // The default 90 days add the day a month back; the day 120 days back only "Tümü" shows.
        #expect(GraphModel.compute(input: input, filter: GraphFilter(), today: today).nodes.count == 3 + 3)
        #expect(GraphModel.compute(input: input, filter: GraphFilter(period: .all), today: today).nodes.count == 3 + 5)
        // A period without a written day keeps the relation.
        let empty = GraphModel.compute(input: input, filter: filter, today: today.addingDays(400)!)
        #expect(empty.edges == [relation])
        // A day mentioning no drawn entity has no node.
        filter.people = false
        let place = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(place.nodes.map(\.id) == [recent[1], c] && place.edges.map(\.kind) == [.day])
        filter.places = false
        #expect(GraphModel.compute(input: input, filter: filter, today: today).nodes.isEmpty)
    }
    @Test func layoutIsDeterministicFiniteSeparatedAndHandlesTwoHundredFiftyNodes() {
        let nodes = (0..<250).map { GraphNode(id: String(format: "%03d", $0), name: "Node", kind: .person, count: $0) }
        let edges = (1..<250).map { GraphEdge(first: nodes[$0 - 1].id, second: nodes[$0].id, weight: 2) }
        let graph = GraphModel(nodes: nodes, edges: edges)
        let start = ContinuousClock.now
        let positions = GraphLayout.compute(graph)
        let elapsed = start.duration(to: .now)
        print("Graph layout 250 nodes/249 edges: \(elapsed)")
        #expect(positions == GraphLayout.compute(GraphModel(nodes: nodes.reversed(), edges: edges.reversed())))
        #expect(positions.count == nodes.count && positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        for (index, first) in nodes.enumerated() {
            for second in nodes.dropFirst(index + 1) {
                #expect(positions[first.id]!.distance(to: positions[second.id]!) >= first.radius + second.radius + 8)
            }
        }
        #expect(GraphLayout.compute(GraphModel(nodes: [], edges: [])).isEmpty)
        #expect(GraphLayout.compute(GraphModel(nodes: [nodes[0]], edges: [])).count == 1)
        #expect(GraphLayout.compute(graph, shouldCancel: { true }).isEmpty)
    }
    @Test func focusedScreenSelectsEntityAndReloadsFilterThenResetsForVault() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let screen = GraphScreenModel(store: context.store, focus: "people/Deniz Arıkan.md")
        await screen.load(today: today)
        #expect(screen.selected == "people/Deniz Arıkan.md" && screen.positions.count == 24)
        screen.filter.people = false
        await screen.load(today: today)
        // Four places and the twelve days that mention one.
        #expect(screen.selected == nil && screen.graph.nodes.count == 16)
        screen.reset()
        #expect(screen.graph.nodes.isEmpty && screen.positions.isEmpty)
    }
    @Test func sampleMapHasTwoCoordinatePinsSizedByAllResolvedMentions() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let pins = PlacesMapModel.pins(places: context.store.mapPlaces, usage: context.store.entityUsage)
        #expect(pins.map(\.id) == ["places/Liman Ofis.md", "places/Tepe Spor Salonu.md"])
        #expect(pins.map(\.count) == [9, 10])
        #expect(pins[0].radius < pins[1].radius && pins[0].intensity == 0.9 && pins[1].intensity == 1)
        #expect(pins.allSatisfy { $0.radius.isFinite && $0.coordinate.isValid })
    }
    @Test func mapCoordinatesRemainUsableWithInvalidSuggestionRadiusAndInvalidPinsAreExcluded() {
        let document = RawDocument(bytes: Array("---\ncoordinates: [10, 20]\nradius: -1\n---\n".utf8))
        let place = KnownEntity(file: "places/Ev.md", kind: .place, name: "Ev")
        #expect(PlaceCoordinate(document: document) == PlaceCoordinate(latitude: 10, longitude: 20))
        #expect(NearbyPlace(entity: place, document: document) == nil)
        let invalid = MapPlace(entity: place, coordinate: PlaceCoordinate(latitude: 91, longitude: 20))
        #expect(PlacesMapModel.pins(places: [invalid], usage: []).isEmpty)
        let zero = PlacesMapModel.pins(
            places: [MapPlace(entity: place, coordinate: PlaceCoordinate(latitude: 0, longitude: 0))], usage: [])
        #expect(zero.first?.radius == 10 && zero.first?.intensity == 0)
    }
    @Test func mapLocationFixUsesExistingPermissionWithoutRequestingAccess() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let source = FakeLocationSource()
        let location = LocationService(source: source, defaults: defaults.defaults)
        location.requestLocationIfNeeded()
        #expect(source.accessRequests == 0 && source.locationRequests == 0)
        source.authorization = .authorized
        location.requestLocationIfNeeded()
        #expect(source.accessRequests == 0 && source.locationRequests == 1)
        #expect(location.currentCoordinate == source.fix)
    }
    /// Manşet-row filter icon turns accent only when the node kinds differ from the default.
    @Test func filterMenuIsActiveOnlyForNonDefaultNodeKinds() {
        #expect(!GraphFilterMenu.isActive(GraphFilter()))
        #expect(GraphFilterMenu.isActive(GraphFilter(people: false)))
        #expect(GraphFilterMenu.isActive(GraphFilter(places: false)))
        #expect(GraphFilterMenu.isActive(GraphFilter(customTypes: ["book"])))
        #expect(!GraphFilterMenu.isActive(GraphFilter(period: .month)))
        #expect(!GraphFilterMenu.isActive(GraphFilter(period: .all)))
    }
    /// A relation as the index reads it (the type has no public initializer).
    private func relation(_ source: String, _ target: String) throws -> Relation {
        let json = #"{"source":"\#(source)","target":"\#(target)","sourceName":"","targetName":"","targetKind":""}"#
        return try JSONDecoder().decode(Relation.self, from: Data(json.utf8))
    }
    private func entity(_ id: String, kind: String = "person") -> EntitySummary {
        EntitySummary(id: id, kind: kind, name: id, qualifier: nil, aliases: [], incomingLinks: 0)
    }
}
