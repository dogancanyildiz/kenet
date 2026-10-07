import Foundation
import VaultFormat

enum GraphPeriod: Int, CaseIterable, Sendable {
    case month = 30
    case quarter = 90
    case year = 365
    case all = 0
}
struct GraphFilter: Equatable, Sendable {
    var people = true
    var places = true
    var days = false
    var period = GraphPeriod.all
    var minimumWeight = 1
}
struct GraphNode: Identifiable, Sendable {
    enum Kind: Sendable { case person, place, day }
    let id: String
    let name: String
    let kind: Kind
    let count: Int
    var date: CalendarDate? = nil
    var radius: Double { 10 + min(14, sqrt(Double(max(0, count))) * 2) }
}
struct GraphEdge: Sendable, Equatable {
    let first: String
    let second: String
    let weight: Int
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
    static func compute(input: GraphInput, filter: GraphFilter, today: CalendarDate) -> Self {
        let days = input.days.filter {
            filter.period == .all || ($0.date <= today && today.ordinal - $0.date.ordinal < filter.period.rawValue)
        }
        var totals = filter.period == .all ? input.totals : [:]
        if filter.period != .all {
            for day in days { for (id, count) in day.mentions { totals[id, default: 0] += count } }
        }
        var nodes = input.entities.filter { $0.kind == "person" ? filter.people : filter.places }.map {
            GraphNode(
                id: $0.id, name: $0.name + ($0.qualifier.map { " (" + $0 + ")" } ?? ""),
                kind: $0.kind == "person" ? .person : .place, count: totals[$0.id] ?? 0)
        }
        let ids = Set(nodes.map(\.id))
        struct Pair: Hashable {
            let first: String
            let second: String
        }
        var weights: [Pair: Int] = [:]
        for day in days {
            let members = day.mentions.keys.filter { ids.contains($0) }.sorted()
            for (index, first) in members.enumerated() {
                for second in members.dropFirst(index + 1) {
                    weights[Pair(first: first, second: second), default: 0] += 1
                }
            }
            if filter.days {
                let id = "day:" + day.date.description
                nodes.append(
                    GraphNode(
                        id: id, name: day.date.description, kind: .day,
                        count: day.mentions.values.reduce(0, +), date: day.date))
                for member in members { weights[Pair(first: id, second: member)] = 1 }
            }
        }
        let edges = weights.filter { $0.value >= max(1, filter.minimumWeight) }.map {
            GraphEdge(first: $0.key.first, second: $0.key.second, weight: $0.value)
        }.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
        return Self(nodes: nodes.sorted { $0.id < $1.id }, edges: edges)
    }
}
