import SwiftUI

/// The interactive graph: a drag that starts on a node moves that node (its neighbors follow
/// on springs), a drag that starts on empty canvas pans, a tap selects, a pinch zooms.
struct GraphCanvas: View {
    let model: GraphScreenModel
    @GestureState private var magnification = 1.0
    @GestureState private var isTouching = false
    @State private var grab: GraphGrab?
    @State private var panDrag = CGSize.zero

    /// A finger needs the full tap target around small nodes; a pointer is precise.
    static var minimumHitRadius: Double {
        #if os(iOS)
            Double(TapTarget.minimumLength / 2)
        #else
            14
        #endif
    }

    /// A drag takes hold of a node only close to what is drawn (nodes are never drawn smaller
    /// than 5 points). The generous tap target would leave no empty canvas to pan by once a
    /// graph is dense or zoomed in: measured on 300 nodes at 2x, 94% of the canvas with the tap
    /// target against 32% with this radius.
    static let minimumGrabRadius = 8.0

    /// Movement below this stays a tap.
    static var dragThreshold: CGFloat {
        #if os(iOS)
            10
        #else
            2
        #endif
    }

    var body: some View {
        let motion = model.motion
        GeometryReader { geometry in
            let viewport = GraphViewport(
                size: geometry.size, camera: model.camera, zoom: model.zoom * magnification,
                pan: CGSize(width: model.pan.width + panDrag.width, height: model.pan.height + panDrag.height))
            GraphDrawing(
                edges: model.graph.edges, motion: motion, viewport: viewport, selected: model.selected,
                labelsDays: model.filter.scope != .all
            )
            #if os(macOS)
                .background(
                    GraphScrollZoom { delta in
                        model.zoom = min(5, max(0.2, model.zoom * exp(delta * 0.01)))
                    })
            #endif
            .contentShape(Rectangle())
            .onTapGesture { location in
                let index = viewport.nodeIndex(
                    at: location, nodes: motion.nodes, points: motion.points,
                    minimumRadius: Self.minimumHitRadius)
                model.select(index.map { motion.nodes[$0].id }, recenter: false)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Graph")
            .accessibilityChildren {
                // Label-only elements: a text view here is laid out in the canvas's frame and
                // reported as clipped by the accessibility audit, though nothing draws it.
                ForEach(Array(model.graph.edges.filter { $0.kind == .relation }.enumerated()), id: \.offset) {
                    _, edge in
                    Color.clear.accessibilityElement()
                        .accessibilityLabel(
                            Text(
                                verbatim: VoiceOverCopy.graphRelationLabel(
                                    first: model.graph.nodes.first { $0.id == edge.first }?.name ?? edge.first,
                                    second: model.graph.nodes.first { $0.id == edge.second }?.name ?? edge.second)))
                }
                ForEach(GraphAccessibleNode.list(from: model.graph)) { node in
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: node.accessibilityLabel()))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.select(node.id, recenter: true) }
                }
            }
            .highPriorityGesture(dragGesture(viewport))
            .simultaneousGesture(
                MagnifyGesture().updating($magnification) { value, state, _ in
                    state = min(5 / model.zoom, max(0.2 / model.zoom, Double(value.magnification)))
                }.onEnded { model.zoom = min(5, max(0.2, model.zoom * Double($0.magnification))) }
            )
        }
        // A gesture the system cancels never reports its end: let go of the node anyway.
        // Deferred one turn so a normal end is handled by `onEnded` first.
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            Task { @MainActor in if grab != nil { release(translation: nil) } }
        }
    }

    private func dragGesture(_ viewport: GraphViewport) -> some Gesture {
        DragGesture(minimumDistance: Self.dragThreshold)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in
                let motion = model.motion
                let current =
                    grab
                    ?? GraphGrab.begin(
                        at: value.startLocation, viewport: viewport, nodes: motion.nodes, points: motion.points,
                        minimumRadius: Self.minimumGrabRadius)
                switch current {
                case .node(let index, _):
                    guard let target = current.target(for: value.location, viewport: viewport) else { return }
                    if grab == nil {
                        // Holding a node shows what it is tied to.
                        model.select(motion.nodes[index].id, recenter: false)
                        motion.beginDrag(index, at: target)
                    } else {
                        motion.drag(to: target)
                    }
                case .canvas:
                    panDrag = value.translation
                }
                grab = current
            }
            .onEnded { release(translation: $0.translation) }
    }

    private func release(translation: CGSize?) {
        if case .canvas = grab, let translation {
            model.pan = CGSize(
                width: model.pan.width + translation.width, height: model.pan.height + translation.height)
        }
        model.motion.endDrag()
        panDrag = .zero
        grab = nil
    }
}

/// Steps the simulation once per display frame while it moves; the timeline is paused at rest,
/// so an idle graph costs nothing.
private struct GraphDrawing: View {
    let edges: [GraphEdge]
    let motion: GraphMotion
    let viewport: GraphViewport
    let selected: String?
    let labelsDays: Bool

    var body: some View {
        TimelineView(.animation(paused: !motion.isRunning)) { timeline in
            GraphFrame(edges: edges, motion: motion, viewport: viewport, selected: selected, labelsDays: labelsDays)
                .onChange(of: timeline.date) { _, date in motion.advance(to: date) }
        }
    }
}

/// One drawn frame. Reads the live positions, so it alone redraws while the layout moves.
private struct GraphFrame: View {
    let edges: [GraphEdge]
    @Environment(\.displayScale) private var displayScale
    let motion: GraphMotion
    let viewport: GraphViewport
    let selected: String?
    /// A day's own graph names its day node ("17 Eyl"); the whole graph's day hubs stay unnamed.
    let labelsDays: Bool

    /// Above this many nodes only the selection and its neighbours carry a name: a dense graph
    /// would be covered by text (and every frame would lay out hundreds of labels).
    static let labelLimit = 80

    var body: some View {
        let nodes = motion.nodes
        let links = motion.links
        let points = motion.points
        let chosen = selected.flatMap { motion.index(of: $0) }
        let edgeKinds = Dictionary(edges.map { ([$0.first, $0.second], $0.kind) }) { first, _ in first }
        Canvas { context, size in
            guard points.count == nodes.count else { return }
            Self.drawDotGrid(size: size, in: &context)
            var neighbors = Set<Int>()
            for link in links {
                let highlighted = link.first == chosen || link.second == chosen
                if highlighted {
                    neighbors.insert(link.first)
                    neighbors.insert(link.second)
                }
                var path = Path()
                path.move(to: viewport.screen(points[link.first]))
                path.addLine(to: viewport.screen(points[link.second]))
                context.stroke(
                    path,
                    with: .color(highlighted ? Color.ink.control : Color.ink.rule),
                    lineWidth: GraphEdgeStyle.width(
                        edgeKinds[[nodes[link.first].id, nodes[link.second].id]] ?? .day,
                        scale: displayScale))
            }
            for (index, node) in nodes.enumerated() {
                let position = viewport.screen(points[index])
                let radius = CGFloat(viewport.radius(of: node))
                let rect = CGRect(
                    x: position.x - radius, y: position.y - radius, width: radius * 2,
                    height: radius * 2)
                guard rect.insetBy(dx: -4, dy: -4).intersects(CGRect(origin: .zero, size: size)) else { continue }
                let dimmed = chosen != nil && index != chosen && !neighbors.contains(index)
                let fill = GraphNodeStyle.fill(node.kind).opacity(dimmed ? 0.25 : 1)
                context.fill(GraphNodeShape(kind: node.kind).path(in: rect), with: .color(fill))
            }
            // Name under every node (Şafak drawing); the selected one in text ink, semibold.
            let labelsAll = nodes.count <= Self.labelLimit
            for (index, node) in nodes.enumerated() {
                let isChosen = index == chosen
                guard labelsAll || isChosen || neighbors.contains(index) else { continue }
                if node.kind == .day && !labelsDays && !isChosen { continue }
                let dimmed = chosen != nil && !isChosen && !neighbors.contains(index)
                let position = viewport.screen(points[index])
                let radius = CGFloat(viewport.radius(of: node))
                Self.drawLabel(
                    Self.label(for: node), at: position, radius: radius, canvasSize: size, emphasized: isChosen,
                    dimmed: dimmed, in: &context)
            }
            if let chosen {
                let node = nodes[chosen]
                let position = viewport.screen(points[chosen])
                let radius = CGFloat(viewport.radius(of: node))
                // Double ring in the accent colour (design.md "Graph düğümleri").
                for gap in [3.0, 7.0] as [CGFloat] {
                    let ring = CGRect(
                        x: position.x - radius - gap, y: position.y - radius - gap,
                        width: (radius + gap) * 2, height: (radius + gap) * 2)
                    context.stroke(
                        GraphNodeShape(kind: node.kind).path(in: ring),
                        with: .color(Color.ink.accent),
                        lineWidth: InkStroke.control)
                }
            }
        }
    }

    /// The node's name; a day node reads short ("17 Eyl").
    private static func label(for node: GraphNode) -> Text {
        if let date = node.date {
            return Text(LocalDay.instant(for: date), format: .dateTime.day().month(.abbreviated))
        }
        return Text(verbatim: node.name)
    }

    /// Screen-space dot grid in `rule` under the edges; it does not move with the graph.
    private static func drawDotGrid(size: CGSize, in context: inout GraphicsContext) {
        let step: CGFloat = 20
        let dot: CGFloat = 1.5
        var dots = Path()
        var y = step / 2
        while y < size.height {
            var x = step / 2
            while x < size.width {
                dots.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                x += step
            }
            y += step
        }
        context.fill(dots, with: .color(Color.ink.rule))
    }

    private static func drawLabel(
        _ text: Text, at position: CGPoint, radius: CGFloat, canvasSize: CGSize, emphasized: Bool, dimmed: Bool,
        in context: inout GraphicsContext
    ) {
        let label =
            text
            .font(emphasized ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(emphasized ? Color.ink.text : Color.ink.secondaryText)
        let resolved = context.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: 160, height: 40))
        // Below the node, clear of the selection ring; above it when the bottom edge is near.
        let gap: CGFloat = emphasized ? 10 : 4
        var originY = position.y + radius + gap
        if originY + textSize.height > canvasSize.height - 2 {
            originY = position.y - radius - textSize.height - gap
        }
        originY = min(max(2, originY), max(2, canvasSize.height - textSize.height - 2))
        var originX = position.x - textSize.width / 2
        originX = min(max(2, originX), max(2, canvasSize.width - textSize.width - 2))
        let rect = CGRect(origin: CGPoint(x: originX, y: originY), size: textSize)
        var layer = context
        layer.opacity = dimmed ? 0.35 : 1
        layer.draw(resolved, in: rect)
    }
}

/// A day's many ties draw as hairlines; a written relation stands out in a heavy line.
enum GraphEdgeStyle {
    static func width(_ kind: GraphEdge.Kind, scale: CGFloat) -> CGFloat {
        switch kind {
        case .relation: InkStroke.highPriority
        case .day: InkStroke.hairline(scale: scale)
        }
    }
}
