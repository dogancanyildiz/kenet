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
            TapTarget.minimumLength / 2
        #else
            14
        #endif
    }

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
            GraphDrawing(motion: motion, viewport: viewport, selected: model.selected)
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
                    ForEach(GraphAccessibleNode.list(from: model.graph)) { node in
                        Button {
                            model.select(node.id, recenter: true)
                        } label: {
                            Text(verbatim: node.accessibilityLabel())
                        }
                    }
                }
                .highPriorityGesture(dragGesture(viewport))
                .simultaneousGesture(
                    MagnifyGesture().updating($magnification) { value, state, _ in
                        state = min(5 / model.zoom, max(0.2 / model.zoom, value.magnification))
                    }.onEnded { model.zoom = min(5, max(0.2, model.zoom * $0.magnification)) }
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
                        minimumRadius: Self.minimumHitRadius)
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
    let motion: GraphMotion
    let viewport: GraphViewport
    let selected: String?

    var body: some View {
        TimelineView(.animation(paused: !motion.isRunning)) { timeline in
            GraphFrame(motion: motion, viewport: viewport, selected: selected)
                .onChange(of: timeline.date) { _, date in motion.advance(to: date) }
        }
    }
}

/// One drawn frame. Reads the live positions, so it alone redraws while the layout moves.
private struct GraphFrame: View {
    let motion: GraphMotion
    let viewport: GraphViewport
    let selected: String?

    var body: some View {
        let nodes = motion.nodes
        let links = motion.links
        let points = motion.points
        let chosen = selected.flatMap { motion.index(of: $0) }
        Canvas { context, size in
            guard points.count == nodes.count else { return }
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
                    lineWidth: highlighted ? 2 : min(3, 0.5 + Double(link.weight) * 0.3))
            }
            for (index, node) in nodes.enumerated() {
                let position = viewport.screen(points[index])
                let radius = viewport.radius(of: node)
                let rect = CGRect(
                    x: position.x - radius, y: position.y - radius, width: radius * 2,
                    height: radius * 2)
                guard rect.insetBy(dx: -4, dy: -4).intersects(CGRect(origin: .zero, size: size)) else { continue }
                let dimmed = chosen != nil && index != chosen && !neighbors.contains(index)
                let fill = GraphNodeStyle.fill(node.kind).opacity(dimmed ? 0.25 : 1)
                context.fill(GraphNodeShape(kind: node.kind).path(in: rect), with: .color(fill))
            }
            if let chosen {
                let node = nodes[chosen]
                let position = viewport.screen(points[chosen])
                let radius = viewport.radius(of: node)
                let ring = CGRect(
                    x: position.x - radius - 3, y: position.y - radius - 3, width: radius * 2 + 6,
                    height: radius * 2 + 6)
                context.stroke(
                    GraphNodeShape(kind: node.kind).path(in: ring),
                    with: .color(Color.ink.accent),
                    lineWidth: InkStroke.highPriority)
                Self.drawSelectedLabel(
                    node.name, at: position, radius: radius, canvasSize: size, in: &context)
            }
        }
    }

    private static func drawSelectedLabel(
        _ name: String, at position: CGPoint, radius: CGFloat, canvasSize: CGSize,
        in context: inout GraphicsContext
    ) {
        let label = Text(verbatim: name).font(.ink.content).foregroundStyle(Color.ink.text)
        let resolved = context.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: 240, height: 40))
        let padX: CGFloat = 4
        let padY: CGFloat = 2
        let width = textSize.width + padX * 2
        let height = textSize.height + padY * 2
        // Prefer below the node (clear of the accent ring); flip above if clipped.
        var originY = position.y + radius + 10
        if originY + height > canvasSize.height - 2 {
            originY = position.y - radius - height - 10
        }
        originY = min(max(2, originY), max(2, canvasSize.height - height - 2))
        var originX = position.x - width / 2
        originX = min(max(2, originX), max(2, canvasSize.width - width - 2))
        let labelRect = CGRect(x: originX, y: originY, width: width, height: height)
        context.fill(Path(roundedRect: labelRect, cornerRadius: 2), with: .color(Color.ink.paper))
        context.draw(resolved, at: CGPoint(x: labelRect.midX, y: labelRect.midY))
    }
}
