import Foundation
import Observation
import VaultFormat

@MainActor @Observable
final class GraphScreenModel {
    let store: IndexStore
    var filter = GraphFilter()
    var selected: String?
    private(set) var graph = GraphModel(nodes: [], edges: [])
    private(set) var positions: [String: GraphPoint] = [:]
    private(set) var isLoading = false
    @ObservationIgnored private var request = UUID()
    init(store: IndexStore, focus: String? = nil) {
        self.store = store
        selected = focus
    }
    func load(today: CalendarDate) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        let input = store.content.graphInput
        let filter = filter
        isLoading = true
        defer { if request == id { isLoading = false } }
        let worker = Task.detached {
            let graph = GraphModel.compute(input: input, filter: filter, today: today)
            return (graph, GraphLayout.compute(graph, shouldCancel: { Task.isCancelled }))
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard request == id, root == store.vaultURL, self.filter == filter, !Task.isCancelled else { return }
        graph = result.0
        positions = result.1
        if !graph.nodes.contains(where: { $0.id == selected }) { selected = nil }
    }
    func reset() {
        request = UUID()
        selected = nil
        graph = GraphModel(nodes: [], edges: [])
        positions = [:]
    }
}
