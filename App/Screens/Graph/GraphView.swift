import SwiftUI

struct GraphView: View {
    let store: IndexStore
    @State private var model: GraphScreenModel
    @Environment(\.clockNow) private var clockNow
    init(store: IndexStore, focus: String? = nil) {
        self.store = store
        _model = State(initialValue: GraphScreenModel(store: store, focus: focus))
    }
    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let today = LocalDay.today(at: clockNow())
            VStack(spacing: 0) {
                GraphControls(
                    maximumWeight: max(365, model.graph.edges.map(\.weight).max() ?? 1), filter: $model.filter)
                if model.isLoading {
                    InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                        .padding(.horizontal, InkSpacing.margin)
                }
                if model.graph.nodes.isEmpty && !model.isLoading {
                    EmptyState("Gösterilecek düğüm yok")
                } else {
                    GraphCanvas(graph: model.graph, positions: model.positions, selected: $model.selected)
                }
                HStack(spacing: 12) {
                    legendMark(kind: .person, title: "Kişiler")
                    legendMark(kind: .place, title: "Konumlar")
                    if model.filter.days {
                        legendMark(kind: .day, title: "Günler")
                    }
                    Spacer()
                    Menu("Düğüm seç") {
                        ForEach(model.graph.nodes) { node in
                            Button {
                                model.selected = node.id
                            } label: {
                                Text(verbatim: node.name)
                            }
                        }
                    }
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.accent)
                }
                .font(.ink.meta)
                .padding(.horizontal, InkSpacing.margin)
                if let node = model.graph.nodes.first(where: { $0.id == model.selected }) {
                    HStack {
                        Text(verbatim: node.name)
                            .font(.ink.content)
                            .foregroundStyle(Color.ink.text)
                        Spacer()
                        if let date = node.date {
                            NavigationLink("Sayfayı aç") { DayView(store: store, date: date) }
                        } else if let entity = store.content.entities.first(where: { $0.id == node.id }) {
                            NavigationLink("Sayfayı aç") { EntityView(store: store, entity: entity) }
                        }
                    }
                    .padding(InkSpacing.margin)
                }
                Text("Çizgiler aynı gün geçen kayıtları bağlar.")
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.bottom, 8)
            }
            .inkPage()
            .task(
                id: String(describing: model.filter) + today.description + String(describing: store.lastUpdated)
                    + (store.vaultURL?.path ?? "")
            ) {
                await model.load(today: today)
            }
        }
        .navigationTitle("Graph").toolbar { SearchButton() }
        .onChange(of: store.vaultURL) { model.reset() }
    }

    private func legendMark(kind: GraphNode.Kind, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            GraphNodeShape(kind: kind)
                .fill(GraphNodeStyle.fill(kind))
                .frame(width: 10, height: 10)
            Text(title)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shared node silhouette: person = circle, place = diamond, day = rounded square.
struct GraphNodeShape: Shape {
    var kind: GraphNode.Kind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .person:
            return Path(ellipseIn: rect)
        case .place:
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        case .day:
            return Path(roundedRect: rect, cornerRadius: max(1, min(rect.width, rect.height) * 0.2))
        }
    }
}

enum GraphNodeStyle {
    static func fill(_ kind: GraphNode.Kind) -> Color {
        switch kind {
        case .person: Color.ink.person
        case .place: Color.ink.place
        case .day: Color.ink.secondaryText
        }
    }
}
