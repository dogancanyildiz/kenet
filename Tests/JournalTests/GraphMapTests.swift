import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct GraphMapTests {
    let today = CalendarDate("2026-10-04")!
    @Test func sampleGraphHasTenNodesAndDistinctDayEdgeWeights() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let graph = GraphModel.compute(input: context.store.content.graphInput, filter: GraphFilter(), today: today)
        #expect(graph.nodes.count == 10)
        func weight(_ first: String, _ second: String) -> Int? {
            graph.edges.first { Set([$0.first, $0.second]) == Set([first, second]) }?.weight
        }
        #expect(weight("people/Deniz Arıkan.md", "places/Liman Ofis.md") == 2)
        #expect(weight("people/Deniz Arıkan.md", "places/Tepe Spor Salonu.md") == 4)
        let neighbors = graph.neighbors(of: "people/Deniz Arıkan.md")
        #expect(neighbors.contains("places/Liman Ofis.md") && !neighbors.contains("people/Deniz Arıkan.md"))
        for usage in context.store.entityUsage {
            #expect(graph.nodes.first { $0.id == usage.file }?.count == usage.totalCount)
            for (other, count) in usage.cooccurrences { #expect(weight(usage.file, other) == count) }
        }
    }
    @Test func filtersIncludeMondayWindowBoundaryKindsDaysAndMinimumWeight() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let input = context.store.content.graphInput
        var filter = GraphFilter()
        filter.people = false
        let places = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(places.nodes.count == 4 && places.nodes.allSatisfy { $0.kind == .place })
        filter.people = true
        filter.days = true
        let withDays = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(withDays.nodes.filter { $0.kind == .day }.count == 14)
        #expect(
            withDays.edges.contains {
                $0.first == "day:2026-09-25" && $0.second == "people/Deniz Arıkan.md" && $0.weight == 1
            })
        filter.minimumWeight = 4
        let weighted = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(weighted.edges.allSatisfy { $0.weight >= 4 })
        filter.period = .month
        let old = GraphModel.compute(input: input, filter: filter, today: CalendarDate("2026-10-27")!)
        #expect(old.edges.isEmpty && old.nodes.filter { $0.kind == .day }.isEmpty)
        #expect(old.nodes.allSatisfy { $0.count == 0 })
    }
    @Test func windowIsInclusiveCountsRepeatMentionsButNotSharedDays() {
        var input = GraphInput()
        input.entities = [entity("a"), entity("b")]
        input.totals = ["a": 7, "b": 3]
        input.days = [
            .init(date: today.addingDays(-30)!, mentions: ["a": 1, "b": 1]),
            .init(date: today.addingDays(-29)!, mentions: ["a": 4, "b": 1]),
            .init(date: today, mentions: ["a": 1, "b": 1]),
            .init(date: today.addingDays(1)!, mentions: ["a": 1, "b": 1]),
        ]
        var filter = GraphFilter()
        filter.period = .month
        let graph = GraphModel.compute(input: input, filter: filter, today: today)
        #expect(graph.edges == [GraphEdge(first: "a", second: "b", weight: 2)])
        #expect(graph.nodes.first?.count == 5)
        for period in [GraphPeriod.quarter, .year] {
            filter.period = period
            #expect(GraphModel.compute(input: input, filter: filter, today: today).edges.first?.weight == 3)
        }
        filter.people = false
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
        #expect(screen.selected == "people/Deniz Arıkan.md" && screen.positions.count == 10)
        screen.filter.people = false
        await screen.load(today: today)
        #expect(screen.selected == nil && screen.graph.nodes.count == 4)
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
        #expect(GraphFilterMenu.isActive(GraphFilter(days: true)))
        #expect(!GraphFilterMenu.isActive(GraphFilter(period: .month, minimumWeight: 3)))
    }
    private func entity(_ id: String) -> EntitySummary {
        EntitySummary(id: id, kind: "person", name: id, qualifier: nil, aliases: [], incomingLinks: 0)
    }
}
