import Foundation

extension GraphLayout {
    /// Search neighboring spatial cells after relaxation so every circle has at least 8 points of clearance.
    static func separated(nodes: [GraphNode], points: [GraphPoint]) -> [String: GraphPoint] {
        struct Cell: Hashable {
            let x: Int
            let y: Int
        }
        let pitch = (nodes.map(\.radius).max() ?? 10) * 2 + 10
        var occupied: [Cell: [(GraphPoint, Double)]] = [:]
        var result: [String: GraphPoint] = [:]
        func cell(_ point: GraphPoint) -> Cell { Cell(x: Int(floor(point.x / pitch)), y: Int(floor(point.y / pitch))) }
        func fits(_ point: GraphPoint, radius: Double) -> Bool {
            let center = cell(point)
            for x in (center.x - 1)...(center.x + 1) {
                for y in (center.y - 1)...(center.y + 1) {
                    for (other, size) in occupied[Cell(x: x, y: y)] ?? [] {
                        if point.distance(to: other) < radius + size + 8 { return false }
                    }
                }
            }
            return true
        }
        for (index, node) in nodes.enumerated() {
            let origin = points[index]
            var candidate = origin
            var ring = 0
            while ring <= nodes.count && !fits(candidate, radius: node.radius) {
                ring += 1
                let offsets = (-ring...ring).flatMap { x in
                    (-ring...ring).filter { abs(x) == ring || abs($0) == ring }.map { (x, $0) }
                }
                if let point = offsets.map({
                    GraphPoint(x: origin.x + Double($0.0) * pitch, y: origin.y + Double($0.1) * pitch)
                })
                .first(where: { fits($0, radius: node.radius) }) {
                    candidate = point
                }
            }
            occupied[cell(candidate), default: []].append((candidate, node.radius))
            result[node.id] = candidate
        }
        return result
    }
}
