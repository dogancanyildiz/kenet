import SwiftUI

struct GraphCanvas: View {
    let graph: GraphModel
    let positions: [String: GraphPoint]
    @Binding var selected: String?
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @State private var zoom = 1.0
    @GestureState private var magnification = 1.0

    var body: some View {
        GeometryReader { geometry in
            let scale = fittedScale(geometry.size) * zoom * magnification
            let center = origin
            Canvas { context, size in
                let neighbors = selected.map { graph.neighbors(of: $0) } ?? []
                for edge in graph.edges {
                    guard let first = positions[edge.first], let second = positions[edge.second] else { continue }
                    var path = Path()
                    path.move(to: screen(first, size: size, origin: center, scale: scale))
                    path.addLine(to: screen(second, size: size, origin: center, scale: scale))
                    let highlighted = edge.first == selected || edge.second == selected
                    context.stroke(
                        path, with: .color(highlighted ? .accentColor : .secondary.opacity(0.3)),
                        lineWidth: highlighted ? 2 : min(3, 0.5 + Double(edge.weight) * 0.3))
                }
                for node in graph.nodes {
                    guard let point = positions[node.id] else { continue }
                    let position = screen(point, size: size, origin: center, scale: scale)
                    let radius = max(5, node.radius * scale)
                    let rect = CGRect(
                        x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
                    let color: Color = node.kind == .person ? .blue : node.kind == .place ? .green : .secondary
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(
                            color.opacity(
                                selected == nil || neighbors.contains(node.id) || node.id == selected ? 1 : 0.25)))
                    if node.id == selected {
                        context.stroke(
                            Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.accentColor), lineWidth: 2)
                        context.draw(
                            Text(verbatim: node.name).font(.caption),
                            at: CGPoint(x: position.x, y: position.y + radius + 14))
                    }
                }
            }
            #if os(macOS)
                .background(GraphScrollZoom { delta in zoom = min(5, max(0.2, zoom * exp(delta * 0.01))) })
            #endif
            .contentShape(Rectangle())
            .onTapGesture { location in
                selected =
                    graph.nodes.filter { node in
                        guard let point = positions[node.id] else { return false }
                        let position = screen(point, size: geometry.size, origin: center, scale: scale)
                        let hitRadius: CGFloat
                        #if os(iOS)
                            hitRadius = max(TapTarget.minimumLength / 2, node.radius * scale)
                        #else
                            hitRadius = max(14, node.radius * scale)
                        #endif
                        return hypot(position.x - location.x, position.y - location.y) <= hitRadius
                    }.min { left, right in
                        let a = screen(positions[left.id]!, size: geometry.size, origin: center, scale: scale)
                        let b = screen(positions[right.id]!, size: geometry.size, origin: center, scale: scale)
                        return hypot(a.x - location.x, a.y - location.y) < hypot(b.x - location.x, b.y - location.y)
                    }?.id
            }
            .gesture(
                DragGesture().updating($drag) { value, state, _ in state = value.translation }
                    .onEnded {
                        pan.width += $0.translation.width
                        pan.height += $0.translation.height
                    }
            )
            .simultaneousGesture(
                MagnifyGesture().updating($magnification) { value, state, _ in
                    state = min(5 / zoom, max(0.2 / zoom, value.magnification))
                }.onEnded { zoom = min(5, max(0.2, zoom * $0.magnification)) }
            )
            .overlay(alignment: .topTrailing) {
                HStack {
                    Button {
                        zoom = max(0.2, zoom / 1.25)
                    } label: {
                        Label("Uzaklaştır", systemImage: "minus.magnifyingglass")
                            .tapTarget()
                    }
                    Button {
                        zoom = min(5, zoom * 1.25)
                    } label: {
                        Label("Yakınlaştır", systemImage: "plus.magnifyingglass")
                            .tapTarget()
                    }
                    Button {
                        zoom = 1
                        pan = .zero
                    } label: {
                        Label("Ortala", systemImage: "scope")
                            .tapTarget()
                    }
                }.labelStyle(.iconOnly).padding()
            }
        }.onChange(of: selected) { pan = .zero }
    }
    private var origin: GraphPoint {
        if let selected, let point = positions[selected] { return point }
        let points = Array(positions.values)
        return GraphPoint(
            x: ((points.map(\.x).min() ?? 0) + (points.map(\.x).max() ?? 0)) / 2,
            y: ((points.map(\.y).min() ?? 0) + (points.map(\.y).max() ?? 0)) / 2)
    }
    private func fittedScale(_ size: CGSize) -> Double {
        let points = Array(positions.values)
        let width = max(120, (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0) + 80)
        let height = max(120, (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0) + 80)
        return min(max(1, size.width - 40) / width, max(1, size.height - 40) / height)
    }
    private func screen(_ point: GraphPoint, size: CGSize, origin: GraphPoint, scale: Double) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (point.x - origin.x) * scale + pan.width + drag.width,
            y: size.height / 2 + (point.y - origin.y) * scale + pan.height + drag.height)
    }
}
