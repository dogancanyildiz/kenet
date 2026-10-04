import SwiftUI

struct GraphView: View {
    let store: IndexStore
    @State private var model: GraphScreenModel
    init(store: IndexStore, focus: String? = nil) {
        self.store = store
        _model = State(initialValue: GraphScreenModel(store: store, focus: focus))
    }
    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = LocalDay.today(at: context.date)
            VStack(spacing: 0) {
                GraphControls(
                    maximumWeight: max(365, model.graph.edges.map(\.weight).max() ?? 1), filter: $model.filter)
                if model.isLoading { ProgressView() }
                if model.graph.nodes.isEmpty && !model.isLoading {
                    ContentUnavailableView(
                        "Gösterilecek düğüm yok", systemImage: "point.3.connected.trianglepath.dotted")
                } else {
                    GraphCanvas(graph: model.graph, positions: model.positions, selected: $model.selected)
                }
                HStack {
                    Text("Kişiler").foregroundStyle(.blue)
                    Text("Konumlar").foregroundStyle(.green)
                    if model.filter.days { Text("Günler").foregroundStyle(.secondary) }
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
                }.font(.caption).padding(.horizontal)
                if let node = model.graph.nodes.first(where: { $0.id == model.selected }) {
                    HStack {
                        Text(verbatim: node.name)
                        Spacer()
                        if let date = node.date {
                            NavigationLink("Sayfayı aç") { DayView(store: store, date: date) }
                        } else if let entity = store.content.entities.first(where: { $0.id == node.id }) {
                            NavigationLink("Sayfayı aç") { EntityView(store: store, entity: entity) }
                        }
                    }.padding()
                }
                Text("Çizgiler aynı gün geçen kayıtları bağlar.").font(.caption).foregroundStyle(.secondary).padding(
                    .bottom, 8)
            }
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
}
