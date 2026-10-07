import CoreGraphics
import Foundation
import Observation
import VaultFormat

@MainActor @Observable
final class GraphScreenModel {
    let store: IndexStore
    let motion = GraphMotion()
    var filter = GraphFilter()
    var zoom = 1.0
    var pan = CGSize.zero
    private(set) var selected: String?
    private(set) var camera = GraphCamera()
    private(set) var graph = GraphModel(nodes: [], edges: [])
    private(set) var isLoading = false
    @ObservationIgnored private var request = UUID()
    init(store: IndexStore, focus: String? = nil) {
        self.store = store
        selected = focus
    }

    var positions: [String: GraphPoint] { motion.positions }

    /// - Parameter live: `true` animates the layout into place; `false` (Reduce Motion, image
    ///   tests) settles it in the background and shows the finished layout in one go.
    func load(today: CalendarDate, live: Bool = true) async {
        let id = UUID()
        request = id
        let root = store.vaultURL
        let input = store.content.graphInput
        let filter = filter
        // A live layout rearranges from where it is; a settled one is always the same picture.
        let carried = live ? motion.positions : [:]
        isLoading = true
        defer { if request == id { isLoading = false } }
        let worker = Task.detached { () -> (GraphModel, GraphScene, [GraphPoint])? in
            let graph = GraphModel.compute(input: input, filter: filter, today: today)
            var scene = GraphScene(graph, carrying: carried)
            var settled = scene.simulation
            settled.settle(shouldCancel: { Task.isCancelled })
            if Task.isCancelled { return nil }
            if !live { scene.simulation = settled }
            return (graph, scene, settled.positions)
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard request == id, root == store.vaultURL, self.filter == filter, !Task.isCancelled, let result else {
            return
        }
        // An index refresh that leaves the graph as it was must not restart a layout the user
        // may have arranged by hand.
        let unchanged = motion.isLive == live && !motion.nodes.isEmpty && result.0.hasSameShape(as: graph)
        graph = result.0
        if !graph.nodes.contains(where: { $0.id == selected }) { selected = nil }
        guard !unchanged else { return }
        motion.install(result.1, live: live)
        // The view is framed for the settled layout, so a live layout grows into its frame.
        let focus = selected.flatMap { motion.index(of: $0) }.map { result.2[$0] }
        camera = GraphCamera.fitting(result.2, focus: focus)
    }

    /// - Parameter recenter: `true` when the node may be off screen (menu, VoiceOver); a tap on
    ///   the canvas leaves the view where it is.
    func select(_ id: String?, recenter: Bool) {
        selected = id
        guard recenter, let point = motion.point(of: id) else { return }
        camera.center = point
        pan = .zero
    }

    /// Frames the layout as it is now (the "center" control).
    func recenter() {
        camera = GraphCamera.fitting(motion.points, focus: motion.point(of: selected))
        pan = .zero
    }

    func reset() {
        request = UUID()
        selected = nil
        graph = GraphModel(nodes: [], edges: [])
        motion.install(.empty, live: motion.isLive)
        camera = GraphCamera()
    }
}
