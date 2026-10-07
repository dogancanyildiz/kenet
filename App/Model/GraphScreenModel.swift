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
        // A live layout that is already on screen rearranges from where it is; anything else
        // starts from the seed and is always the same picture.
        let rearranges = live && motion.isLive && !motion.nodes.isEmpty
        isLoading = true
        defer { if request == id { isLoading = false } }
        let worker = Task.detached { () -> (GraphModel, GraphScene, [GraphPoint]?)? in
            let graph = GraphModel.compute(input: input, filter: filter, today: today)
            var scene = GraphScene(graph)
            // Rearranging starts from the positions at install time, which are not known yet.
            guard !rearranges else { return Task.isCancelled ? nil : (graph, scene, nil) }
            var settled = scene.simulation
            settled.settle(shouldCancel: { Task.isCancelled })
            if Task.isCancelled { return nil }
            if !live { scene.simulation = settled }
            return (graph, scene, settled.positions)
        }
        let result = await Self.value(of: worker)
        guard request == id, root == store.vaultURL, self.filter == filter, !Task.isCancelled, let result else {
            return
        }
        // An index refresh that leaves the graph as it was must not restart a layout the user
        // may have arranged by hand; only names and kinds are taken over.
        let unchanged = motion.isLive == live && !motion.nodes.isEmpty && result.0.hasSameShape(as: graph)
        graph = result.0
        if !graph.nodes.contains(where: { $0.id == selected }) { selected = nil }
        guard !unchanged else {
            motion.refresh(nodes: graph.nodes)
            return
        }
        guard let settled = result.2 else {
            await rearrange(to: graph, request: id)
            return
        }
        motion.install(result.1, live: live)
        frame(settled)
    }

    /// Moves the layout on screen to a changed graph, starting from where the nodes are now
    /// (not where they were when loading began), then frames the view for where it will settle.
    private func rearrange(to graph: GraphModel, request id: UUID) async {
        let scene = GraphScene(graph, carrying: motion.positions)
        motion.install(scene, live: true)
        let worker = Task.detached { () -> [GraphPoint]? in
            var settled = scene.simulation
            settled.settle(shouldCancel: { Task.isCancelled })
            return Task.isCancelled ? nil : settled.positions
        }
        guard let settled = await Self.value(of: worker), request == id, !Task.isCancelled,
            settled.count == motion.nodes.count
        else { return }
        frame(settled)
    }

    /// The view is framed for the settled layout, so a live layout grows into its frame.
    private func frame(_ settled: [GraphPoint]) {
        let focus = selected.flatMap { motion.index(of: $0) }.map { settled[$0] }
        camera = GraphCamera.fitting(settled, focus: focus)
    }

    private static func value<Value: Sendable>(of worker: Task<Value, Never>) async -> Value {
        await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
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
