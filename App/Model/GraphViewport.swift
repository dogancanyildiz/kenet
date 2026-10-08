import CoreGraphics
import ForceLayout
import Foundation

/// Where the graph is looked at from: a fixed point in layout space and the size to fit.
/// It is captured when a layout loads or the user recenters, never per frame, so moving nodes
/// do not drag the view around with them.
struct GraphCamera: Equatable, Sendable {
    var center = GraphPoint.zero
    var width = 120.0
    var height = 120.0

    static func fitting(_ points: [GraphPoint], focus: GraphPoint? = nil) -> Self {
        guard let first = points.first else { return Self() }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return Self(
            center: focus ?? GraphPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            width: max(120, maxX - minX + 80), height: max(120, maxY - minY + 80))
    }

    func scale(in size: CGSize) -> Double {
        min(max(1, Double(size.width) - 40) / width, max(1, Double(size.height) - 40) / height)
    }
}

/// Maps between layout space and the canvas, and finds the node under a touch.
struct GraphViewport: Equatable {
    let size: CGSize
    let center: GraphPoint
    let scale: Double
    let offset: CGSize

    init(size: CGSize, camera: GraphCamera, zoom: Double, pan: CGSize) {
        self.size = size
        center = camera.center
        scale = max(1e-6, camera.scale(in: size) * zoom)
        offset = pan
    }

    func screen(_ point: GraphPoint) -> CGPoint {
        let x: Double = Double(size.width) / 2 + (point.x - center.x) * scale + Double(offset.width)
        let y: Double = Double(size.height) / 2 + (point.y - center.y) * scale + Double(offset.height)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    func layout(_ location: CGPoint) -> GraphPoint {
        let x: Double = Double(location.x) - Double(size.width) / 2 - Double(offset.width)
        let y: Double = Double(location.y) - Double(size.height) / 2 - Double(offset.height)
        return GraphPoint(x: x / scale + center.x, y: y / scale + center.y)
    }

    func radius(of node: GraphNode) -> Double { max(5, node.radius * scale) }

    /// The nearest node whose hit circle contains `location`. `minimumRadius` keeps small or
    /// zoomed-out nodes touchable.
    func nodeIndex(at location: CGPoint, nodes: [GraphNode], points: [GraphPoint], minimumRadius: Double) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, node) in nodes.enumerated() where index < points.count {
            let position = screen(points[index])
            let distance: Double = hypot(Double(position.x - location.x), Double(position.y - location.y))
            guard distance <= max(minimumRadius, node.radius * scale) else { continue }
            if best.map({ distance < $0.distance }) ?? true { best = (index, distance) }
        }
        return best?.index
    }
}

/// What a drag took hold of where it began: a node (the node follows the pointer) or empty
/// canvas (the view pans).
enum GraphGrab: Equatable {
    /// `offset` is the node center minus the grab point, so the node does not jump under the finger.
    case node(index: Int, offset: GraphPoint)
    case canvas

    static func begin(
        at start: CGPoint, viewport: GraphViewport, nodes: [GraphNode], points: [GraphPoint], minimumRadius: Double
    ) -> Self {
        guard
            let index = viewport.nodeIndex(at: start, nodes: nodes, points: points, minimumRadius: minimumRadius)
        else { return .canvas }
        let touch = viewport.layout(start)
        return .node(index: index, offset: GraphPoint(x: points[index].x - touch.x, y: points[index].y - touch.y))
    }

    /// Where the grabbed node belongs while the pointer is at `location`.
    func target(for location: CGPoint, viewport: GraphViewport) -> GraphPoint? {
        guard case .node(_, let offset) = self else { return nil }
        let touch = viewport.layout(location)
        return GraphPoint(x: touch.x + offset.x, y: touch.y + offset.y)
    }
}
