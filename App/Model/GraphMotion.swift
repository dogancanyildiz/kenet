import ForceLayout
import Foundation
import Observation

/// Runs the graph's force simulation for the canvas: steps it once per frame while it moves,
/// stops when it rests (no work while idle) and wakes it when a node is dragged.
///
/// Only the canvas reads ``points`` and ``isRunning``, so a moving layout redraws the canvas and
/// nothing else on the page.
@MainActor @Observable
final class GraphMotion {
    private(set) var nodes: [GraphNode] = []
    private(set) var links: [GraphLink] = []
    /// Node positions in layout space, in ``nodes`` order.
    private(set) var points: [GraphPoint] = []
    /// `true` while frames are needed.
    private(set) var isRunning = false
    /// `false` with Reduce Motion: the layout is shown settled and never animates.
    private(set) var isLive = true
    private(set) var draggedIndex: Int?

    @ObservationIgnored private var simulation = GraphScene.empty.simulation
    @ObservationIgnored private var indices: [String: Int] = [:]
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var backlog = 0.0
    @ObservationIgnored private var generation = 0
    /// Background settle after a drag without live motion; tests await it.
    @ObservationIgnored private(set) var settling: Task<Void, Never>?

    /// The simulation advances in fixed steps so its result does not depend on the frame rate.
    static let stepInterval = 1.0 / 60
    /// After a stall the layout catches up at most this far per frame instead of freezing the app.
    static let maximumStepsPerFrame = 3

    var positions: [String: GraphPoint] { Dictionary(zip(nodes.map(\.id), points)) { first, _ in first } }
    var isAtRest: Bool { simulation.isAtRest }
    var stepCount: Int { simulation.stepCount }

    func index(of id: String) -> Int? { indices[id] }
    func point(of id: String?) -> GraphPoint? {
        guard let id, let index = indices[id], index < points.count else { return nil }
        return points[index]
    }

    /// Shows a new scene. With `live` the simulation animates from the scene's state; otherwise
    /// the scene is expected to be settled already and is shown as it is.
    ///
    /// A node that is being dragged stays in the hand if the new scene still has it: a graph
    /// that changes under the finger (index refresh, filter) must not drop the drag.
    func install(_ scene: GraphScene, live: Bool) {
        let held = draggedIndex.flatMap { index -> (id: String, point: GraphPoint)? in
            guard nodes.indices.contains(index), points.indices.contains(index) else { return nil }
            return (nodes[index].id, points[index])
        }
        generation += 1
        settling?.cancel()
        settling = nil
        nodes = scene.nodes
        links = scene.links
        indices = Dictionary(scene.nodes.enumerated().map { ($0.element.id, $0.offset) }) { first, _ in first }
        simulation = scene.simulation
        isLive = live
        draggedIndex = nil
        if let held, let index = indices[held.id] {
            simulation.pin(index, at: held.point)
            draggedIndex = index
        }
        points = simulation.positions
        lastFrame = nil
        backlog = 0
        isRunning = live && !simulation.isAtRest
    }

    /// Takes over names and kinds from a graph with the same shape, without touching the layout.
    func refresh(nodes fresh: [GraphNode]) {
        let byID = Dictionary(fresh.map { ($0.id, $0) }) { first, _ in first }
        nodes = nodes.map { byID[$0.id] ?? $0 }
    }

    // MARK: - Frames

    /// Called once per display frame while ``isRunning``.
    func advance(to date: Date) {
        guard isRunning else { return }
        let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? Self.stepInterval
        lastFrame = date
        backlog = min(backlog + max(0, elapsed), Self.stepInterval * Double(Self.maximumStepsPerFrame))
        var steps = 0
        // The tolerance keeps a display that ticks a hair early from skipping a step.
        while backlog >= Self.stepInterval * 0.99 {
            backlog = max(0, backlog - Self.stepInterval)
            steps += 1
        }
        advance(steps: steps)
    }

    func advance(steps: Int) {
        guard isRunning, steps > 0 else { return }
        for _ in 0..<steps { simulation.step() }
        points = simulation.positions
        if simulation.isAtRest {
            isRunning = false
            lastFrame = nil
            backlog = 0
        }
    }

    // MARK: - Dragging

    /// Takes hold of a node: it follows the pointer and its neighbors follow on their springs.
    func beginDrag(_ index: Int, at point: GraphPoint) {
        guard nodes.indices.contains(index) else { return }
        if let draggedIndex, draggedIndex != index { simulation.unpin(draggedIndex) }
        generation += 1
        settling?.cancel()
        settling = nil
        draggedIndex = index
        hold(index, at: point)
    }

    func drag(to point: GraphPoint) {
        guard let draggedIndex else { return }
        hold(draggedIndex, at: point)
    }

    /// Lets go: the node is free again and the layout settles.
    func endDrag() {
        guard let index = draggedIndex else { return }
        draggedIndex = nil
        simulation.unpin(index)
        if isLive {
            isRunning = !simulation.isAtRest
        } else {
            settleInBackground()
        }
    }

    private func hold(_ index: Int, at point: GraphPoint) {
        simulation.pin(index, at: point)
        // The node tracks the pointer at once, without waiting for the next step.
        if simulation.isPinned(index) { points[index] = point }
        if isLive { isRunning = true }
    }

    /// Reduce Motion: nothing moves on screen until the settled layout is ready, then it is
    /// shown in one go.
    private func settleInBackground() {
        let token = generation
        let pending = simulation
        settling = Task { [weak self] in
            let settled = await Task.detached {
                var copy = pending
                copy.settle()
                return copy
            }.value
            guard let self, self.generation == token, !Task.isCancelled else { return }
            self.simulation = settled
            self.points = settled.positions
        }
    }
}
