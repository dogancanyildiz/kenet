import Foundation

struct GraphPoint: Sendable, Equatable {
    var x: Double
    var y: Double
    static let zero = Self(x: 0, y: 0)
    func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

/// Bounded Fruchterman-Reingold; stable ID order and seed make layouts reproducible.
enum GraphLayout {
    static func compute(_ graph: GraphModel, seed: UInt64 = 42, shouldCancel: @Sendable () -> Bool = { false })
        -> [String: GraphPoint]
    {
        let nodes = graph.nodes.sorted { $0.id < $1.id }
        guard !nodes.isEmpty else { return [:] }
        let extent = max(600, sqrt(Double(nodes.count)) * 75)
        let ideal = extent / sqrt(Double(nodes.count))
        var state = seed
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        var points = nodes.indices.map { index in
            let angle = Double(index) * 2.399963229728653
            let radius = extent * 0.4 * sqrt(Double(index + 1) / Double(nodes.count))
            return GraphPoint(x: cos(angle) * radius + random(), y: sin(angle) * radius + random())
        }
        let indices = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        let edges = graph.edges.sorted { ($0.first, $0.second, $0.weight) < ($1.first, $1.second, $1.weight) }
        let iterations = min(80, max(20, 8_000 / nodes.count))
        for step in 0..<iterations {
            if shouldCancel() { return [:] }
            var forces = Array(repeating: GraphPoint.zero, count: nodes.count)
            for first in nodes.indices {
                for second in (first + 1)..<nodes.count {
                    let dx = points[first].x - points[second].x
                    let dy = points[first].y - points[second].y
                    let distance = max(0.1, hypot(dx, dy))
                    let force = ideal * ideal / (distance * distance)
                    forces[first].x += dx * force
                    forces[first].y += dy * force
                    forces[second].x -= dx * force
                    forces[second].y -= dy * force
                }
            }
            for edge in edges {
                guard let first = indices[edge.first], let second = indices[edge.second] else { continue }
                let dx = points[first].x - points[second].x
                let dy = points[first].y - points[second].y
                let distance = max(0.1, hypot(dx, dy))
                let force = distance / ideal * (1 + log(Double(max(1, edge.weight))))
                forces[first].x -= dx * force
                forces[first].y -= dy * force
                forces[second].x += dx * force
                forces[second].y += dy * force
            }
            let temperature = extent * 0.04 * (1 - Double(step) / Double(iterations))
            for index in nodes.indices {
                forces[index].x -= points[index].x * 0.05
                forces[index].y -= points[index].y * 0.05
                let magnitude = max(0.1, hypot(forces[index].x, forces[index].y))
                points[index].x += forces[index].x / magnitude * min(magnitude, temperature)
                points[index].y += forces[index].y / magnitude * min(magnitude, temperature)
                points[index].x = min(extent, max(-extent, points[index].x))
                points[index].y = min(extent, max(-extent, points[index].y))
            }
        }
        return shouldCancel() ? [:] : separated(nodes: nodes, points: points)
    }
}
