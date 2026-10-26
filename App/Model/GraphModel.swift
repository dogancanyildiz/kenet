import Foundation
import VaultFormat
import VaultIndex

enum GraphPeriod: Int, CaseIterable, Sendable {
    case month = 30
    case quarter = 90
    case year = 365
    case all = 0
}
/// What the graph shows: the whole vault, or one day's own graph (the day page's Graph icon).
enum GraphScope: Hashable, Sendable {
    case all
    case day(CalendarDate)
}
struct GraphFilter: Equatable, Sendable {
    var people = true
    var places = true
    var days = false
    var period = GraphPeriod.all
    var minimumWeight = 1
    /// Custom entity types drawn as nodes, by type ID; none by default.
    var customTypes: Set<String> = []
    var scope = GraphScope.all

    /// Turns the day layer on or off. Turned on over the whole vault, the period narrows to the
    /// last 90 days (one node per written day would crowd the graph); "Tümü" stays selectable.
    mutating func setDays(_ isOn: Bool) {
        if isOn, !days, period == .all { period = .quarter }
        days = isOn
    }

    func showsCustomType(_ id: String) -> Bool { customTypes.contains(id) }

    /// Whether the custom type is drawn; switching it never touches the other kinds.
    mutating func setCustomType(_ id: String, _ isOn: Bool) {
        if isOn { customTypes.insert(id) } else { customTypes.remove(id) }
    }
}
struct GraphNode: Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case person, place, day
        /// A custom entity type, by type ID.
        case custom(String)

        init(entityKind: String) {
            switch entityKind {
            case "person": self = .person
            case "place": self = .place
            default: self = .custom(entityKind)
            }
        }
    }
    let id: String
    let name: String
    let kind: Kind
    let count: Int
    var date: CalendarDate? = nil
    /// The singular name of a custom type node's type.
    var typeName: String? = nil
    var radius: Double { 10 + min(14, sqrt(Double(max(0, count))) * 2) }
}
struct GraphEdge: Sendable, Equatable {
    let first: String
    let second: String
    let weight: Int
    enum Kind: Sendable, Equatable { case cooccurrence, day, relation }
    var kind: Kind = .cooccurrence
}
struct GraphModel: Sendable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    func neighbors(of id: String) -> Set<String> {
        Set(edges.compactMap { $0.first == id ? $0.second : $0.second == id ? $0.first : nil })
    }
    /// Same nodes (and sizes) and same links: the layout does not need to change.
    func hasSameShape(as other: Self) -> Bool {
        edges == other.edges && nodes.count == other.nodes.count
            && zip(nodes, other.nodes).allSatisfy { $0.id == $1.id && $0.radius == $1.radius }
    }
    static func dayNodeID(_ date: CalendarDate) -> String { "day:" + date.description }

    static func compute(input: GraphInput, filter: GraphFilter, today: CalendarDate) -> Self {
        if case .day(let date) = filter.scope { return computeDay(date, input: input, today: today) }
        let days = input.days.filter {
            filter.period == .all || ($0.date <= today && today.ordinal - $0.date.ordinal < filter.period.rawValue)
        }
        var totals = filter.period == .all ? input.totals : [:]
        if filter.period != .all {
            for day in days { for (id, count) in day.mentions { totals[id, default: 0] += count } }
        }
        var nodes = input.entities.filter {
            switch GraphNode.Kind(entityKind: $0.kind) {
            case .person: filter.people
            case .place: filter.places
            case .day: false
            case .custom(let type): filter.showsCustomType(type)
            }
        }.map { node(for: $0, count: totals[$0.id] ?? 0, typeNames: input.typeNames) }
        let ids = Set(nodes.map(\.id))
        // Entity links come from shared blocks (Core); a day node links to everything it mentions.
        var weights = GraphMentions.cooccurrenceWeights(days: days, including: ids)
        if filter.days {
            let title = TodayPresentation.dayTitles(today: today)
            for day in days {
                let id = dayNodeID(day.date)
                nodes.append(
                    GraphNode(
                        id: id, name: title(day.date), kind: .day,
                        count: day.mentions.values.reduce(0, +), date: day.date))
                for member in day.mentions.keys where ids.contains(member) {
                    weights[GraphMentions.Pair(first: id, second: member)] = 1
                }
            }
        }
        var edges = weights.filter { $0.value >= max(1, filter.minimumWeight) }.map {
            GraphEdge(
                first: $0.key.first, second: $0.key.second, weight: $0.value,
                kind: $0.key.first.hasPrefix("day:") || $0.key.second.hasPrefix("day:") ? .day : .cooccurrence)
        }.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
        edges = addingRelations(input.relations, to: edges, including: ids)
        return Self(nodes: nodes.sorted { $0.id < $1.id }, edges: edges)
    }

    /// One day's graph: the day node and every entity the day mentions, whatever its kind, each
    /// tied to the day; entities sharing one of the day's blocks are tied to each other. Period,
    /// kind switches and the weight threshold do not apply. A day without a mention has no graph.
    private static func computeDay(_ date: CalendarDate, input: GraphInput, today: CalendarDate) -> Self {
        guard let day = input.days.first(where: { $0.date == date }) else { return Self(nodes: [], edges: []) }
        var nodes = input.entities.compactMap { entity in
            day.mentions[entity.id].map { node(for: entity, count: $0, typeNames: input.typeNames) }
        }
        guard !nodes.isEmpty else { return Self(nodes: [], edges: []) }
        let ids = Set(nodes.map(\.id))
        var weights = GraphMentions.cooccurrenceWeights(days: [day], including: ids)
        let id = dayNodeID(date)
        nodes.append(
            GraphNode(
                id: id, name: TodayPresentation.dayTitles(today: today)(date), kind: .day,
                count: ids.reduce(0) { $0 + (day.mentions[$1] ?? 0) }, date: date))
        for member in ids { weights[GraphMentions.Pair(first: id, second: member)] = 1 }
        var edges = weights.map {
            GraphEdge(
                first: $0.key.first, second: $0.key.second, weight: $0.value,
                kind: $0.key.first.hasPrefix("day:") || $0.key.second.hasPrefix("day:") ? .day : .cooccurrence)
        }
        .sorted { ($0.first, $0.second) < ($1.first, $1.second) }
        edges = addingRelations(input.relations, to: edges, including: ids)
        return Self(nodes: nodes.sorted { $0.id < $1.id }, edges: edges)
    }

    private static func addingRelations(_ relations: [Relation], to edges: [GraphEdge], including ids: Set<String>)
        -> [GraphEdge]
    {
        var result = edges
        for relation in relations where ids.contains(relation.source) && ids.contains(relation.target) {
            let pair = [relation.source, relation.target].sorted()
            guard pair[0] != pair[1] else { continue }
            // Removing whatever the pair already has keeps one edge per pair, repeats included.
            result.removeAll { [$0.first, $0.second].sorted() == pair }
            result.append(GraphEdge(first: pair[0], second: pair[1], weight: 1, kind: .relation))
        }
        return result.sorted {
            ($0.first, $0.second, $0.kind == .relation ? 1 : 0) < ($1.first, $1.second, $1.kind == .relation ? 1 : 0)
        }
    }

    private static func node(for entity: EntitySummary, count: Int, typeNames: [String: String]) -> GraphNode {
        let kind = GraphNode.Kind(entityKind: entity.kind)
        var typeName: String?
        if case .custom(let type) = kind { typeName = typeNames[type] }
        return GraphNode(
            id: entity.id, name: entity.name + (entity.qualifier.map { " (" + $0 + ")" } ?? ""),
            kind: kind, count: count, typeName: typeName)
    }
}
