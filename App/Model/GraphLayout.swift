import ForceLayout
import Foundation

typealias GraphPoint = ForcePoint

/// A link between two nodes of a ``GraphScene``, addressed by node index.
struct GraphLink: Sendable, Equatable {
    let first: Int
    let second: Int
    let weight: Int
}

/// A graph prepared for the force simulation: nodes in stable ID order, links by index.
struct GraphScene: Sendable {
    let nodes: [GraphNode]
    let links: [GraphLink]
    var simulation: ForceSimulation

    static let empty = Self(GraphModel(nodes: [], edges: []))

    /// - Parameter carrying: positions kept from the layout on screen, so a changed graph
    ///   rearranges from where it is instead of starting over.
    init(_ graph: GraphModel, seed: UInt64 = 42, carrying: [String: GraphPoint] = [:]) {
        let nodes = graph.nodes.sorted { $0.id < $1.id }
        let indices = Dictionary(nodes.enumerated().map { ($0.element.id, $0.offset) }) { first, _ in first }
        let links = graph.edges.sorted { ($0.first, $0.second, $0.weight) < ($1.first, $1.second, $1.weight) }
            .compactMap { edge -> GraphLink? in
                guard let first = indices[edge.first], let second = indices[edge.second], first != second else {
                    return nil
                }
                return GraphLink(first: first, second: second, weight: edge.weight)
            }
        self.nodes = nodes
        self.links = links
        simulation = ForceSimulation(
            radii: nodes.map(\.radius),
            links: links.map {
                // Heavier links sit closer: more shared days pull two nodes together.
                let slack = GraphLayout.linkSlack / (1 + 0.4 * log(Double(max(1, $0.weight))))
                return ForceLink(
                    source: $0.first, target: $0.second,
                    length: nodes[$0.first].radius + nodes[$0.second].radius + slack)
            },
            seed: seed, initial: carrying.isEmpty ? [] : nodes.map { carrying[$0.id] },
            // Mostly in place already: rearrange gently instead of shaking everything loose.
            alpha: nodes.filter { carrying[$0.id] != nil }.count * 2 > nodes.count ? 0.3 : 1,
            parameters: GraphLayout.parameters)
    }

    var positions: [String: GraphPoint] {
        Dictionary(zip(nodes.map(\.id), simulation.positions)) { first, _ in first }
    }
}

/// Graph layout is a live force simulation (`ForceLayout` in Core). Stable ID order and a fixed
/// seed make it reproducible: the same graph always settles into the same picture.
enum GraphLayout {
    /// Free length of a one-day link beyond the two radii.
    static let linkSlack = 110.0

    static var parameters: ForceParameters {
        var parameters = ForceParameters()
        // Roomy enough that links stay visible between nodes of radius 10...24.
        parameters.repulsion = 260
        // At rest every pair of circles keeps at least 8 points of clearance.
        parameters.collisionPadding = 10
        return parameters
    }

    /// The settled layout, computed in one go (no animation).
    static func compute(_ graph: GraphModel, seed: UInt64 = 42, shouldCancel: @Sendable () -> Bool = { false })
        -> [String: GraphPoint]
    {
        var scene = GraphScene(graph, seed: seed)
        scene.simulation.settle(shouldCancel: shouldCancel)
        return shouldCancel() ? [:] : scene.positions
    }
}
