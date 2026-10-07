import CoreGraphics
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Live graph layout: frame pacing, dragging, Reduce Motion and the drag/pan split.
@MainActor struct GraphMotionTests {
    let today = CalendarDate("2026-10-04")!

    /// a-b-c chain plus an unconnected d.
    static let chain = GraphModel(
        nodes: ["a", "b", "c", "d"].map { GraphNode(id: $0, name: $0, kind: .person, count: 4) },
        edges: [GraphEdge(first: "a", second: "b", weight: 1), GraphEdge(first: "b", second: "c", weight: 1)])

    private func rest(_ motion: GraphMotion, limit: Int = 2_000) -> Int {
        var steps = 0
        while motion.isRunning && steps < limit {
            motion.advance(steps: 1)
            steps += 1
        }
        return steps
    }

    @Test func liveLayoutAnimatesIntoTheSamePictureAsTheSettledOneThenStops() {
        let motion = GraphMotion()
        motion.install(GraphScene(Self.chain), live: true)
        #expect(motion.isRunning && motion.points.count == 4)
        let start = motion.points
        motion.advance(steps: 1)
        #expect(motion.points != start, "the layout moves on screen")
        let steps = rest(motion)
        #expect(steps > 5 && !motion.isRunning && motion.isAtRest)
        #expect(motion.positions == GraphLayout.compute(Self.chain))

        // At rest a frame does no work.
        let count = motion.stepCount
        motion.advance(to: Date(timeIntervalSinceReferenceDate: 10))
        motion.advance(steps: 5)
        #expect(motion.stepCount == count)
    }

    @Test func framesAdvanceInFixedStepsWhateverTheFrameRate() {
        let motion = GraphMotion()
        motion.install(GraphScene(Self.chain), live: true)
        func frame(_ time: Double) { motion.advance(to: Date(timeIntervalSinceReferenceDate: time)) }
        frame(0)
        #expect(motion.stepCount == 1, "the first frame takes one step")
        frame(1.0 / 120)
        #expect(motion.stepCount == 1, "half a step has passed at 120 Hz")
        frame(2.0 / 120)
        #expect(motion.stepCount == 2)
        frame(2.0 / 120 + 1.0 / 60)
        #expect(motion.stepCount == 3, "one step per frame at 60 Hz")
        frame(5)
        #expect(motion.stepCount == 3 + GraphMotion.maximumStepsPerFrame, "a stall is not replayed step by step")
    }

    @Test func draggedNodeFollowsThePointerAndNeighborsFollowOnSprings() throws {
        let motion = GraphMotion()
        motion.install(GraphScene(Self.chain), live: true)
        _ = rest(motion)
        let before = motion.points
        let a = try #require(motion.index(of: "a"))
        let b = try #require(motion.index(of: "b"))
        let d = try #require(motion.index(of: "d"))

        var target = GraphPoint(x: before[a].x + 100, y: before[a].y)
        motion.beginDrag(a, at: target)
        #expect(motion.isRunning && motion.draggedIndex == a, "a drag wakes a resting layout")
        #expect(motion.points[a] == target)
        target.x += 200
        motion.drag(to: target)
        #expect(motion.points[a] == target, "the node tracks the pointer before the next frame")
        motion.advance(steps: 240)
        #expect(motion.isRunning, "the layout stays awake while a node is held")
        #expect(motion.points[a] == target)
        let pulled = motion.points[b].x - before[b].x
        let stray = motion.points[d].distance(to: before[d])
        #expect(pulled > 150, "the neighbor is pulled along, moved \(pulled)")
        #expect(stray < pulled / 2, "an unconnected node is only nudged aside, moved \(stray)")

        motion.endDrag()
        #expect(motion.draggedIndex == nil && motion.isRunning)
        let steps = rest(motion)
        #expect(steps < 600 && !motion.isRunning, "after release the layout settles and stops")
        #expect(motion.points[a] != target, "the released node is free again")
        motion.endDrag()
        motion.drag(to: .zero)
        #expect(!motion.isRunning, "stray gesture callbacks do not wake the layout")
    }

    @Test func reduceMotionShowsSettledLayoutsInOneGoEvenAfterADrag() async throws {
        var scene = GraphScene(Self.chain)
        scene.simulation.settle()
        let motion = GraphMotion()
        motion.install(scene, live: false)
        #expect(!motion.isRunning && motion.positions == GraphLayout.compute(Self.chain))
        let before = motion.points
        let a = try #require(motion.index(of: "a"))
        let target = GraphPoint(x: before[a].x + 300, y: before[a].y)

        motion.beginDrag(a, at: target)
        motion.advance(to: Date(timeIntervalSinceReferenceDate: 0))
        motion.advance(steps: 30)
        #expect(!motion.isRunning && motion.stepCount == scene.simulation.stepCount, "nothing animates")
        var expected = before
        expected[a] = target
        #expect(motion.points == expected, "only the held node moves")

        motion.endDrag()
        #expect(motion.points == expected, "the old layout stays until the new one is ready")
        await motion.settling?.value
        #expect(motion.isAtRest && !motion.isRunning)
        #expect(motion.points != expected, "the settled layout replaces it in one go")
    }

    /// A graph far larger than the sample vault: 300 nodes, 600 links.
    static func large() -> GraphModel {
        var state: UInt64 = 11
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let nodes = (0..<300).map {
            GraphNode(
                id: String(format: "%03d", $0), name: "Node", kind: $0 % 3 == 0 ? .place : .person, count: next(60))
        }
        var pairs = Set<[Int]>()
        while pairs.count < 600 {
            let pair = [next(300), next(300)].sorted()
            if pair[0] != pair[1] { pairs.insert(pair) }
        }
        let edges = pairs.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }.map {
            GraphEdge(first: nodes[$0[0]].id, second: nodes[$0[1]].id, weight: 1 + next(6))
        }
        return GraphModel(nodes: nodes, edges: edges)
    }

    @Test func largeGraphSettlesWithClearanceAndALiveFrameStaysCheap() {
        let graph = Self.large()
        let start = ContinuousClock.now
        let positions = GraphLayout.compute(graph)
        print("Graph layout 300 nodes/600 edges settled in \(start.duration(to: .now))")
        #expect(positions.count == 300)
        var tightest = Double.infinity
        for (index, first) in graph.nodes.enumerated() {
            for second in graph.nodes.dropFirst(index + 1) {
                let gap = positions[first.id]!.distance(to: positions[second.id]!) - first.radius - second.radius
                tightest = min(tightest, gap)
            }
        }
        #expect(tightest >= 8, "tightest gap between two circles: \(tightest)")

        // One live frame = one step plus publishing the positions to the canvas.
        let motion = GraphMotion()
        motion.install(GraphScene(graph), live: true)
        var fastest = Duration.seconds(1)
        for _ in 0..<5 {
            let frames = ContinuousClock.now
            for _ in 0..<20 { motion.advance(steps: 1) }
            fastest = min(fastest, frames.duration(to: .now) / 20)
        }
        print("Graph live frame 300 nodes/600 edges: \(fastest) per frame (unoptimized build)")
        #expect(motion.isRunning && motion.stepCount == 100)
        #expect(fastest < .milliseconds(33))
    }

    @Test func viewportMapsBothWaysAndFindsTheNearestNodeWithinItsTapTarget() {
        let camera = GraphCamera.fitting([GraphPoint(x: -100, y: -50), GraphPoint(x: 300, y: 150)])
        #expect(camera.center == GraphPoint(x: 100, y: 50) && camera.width == 480 && camera.height == 280)
        let viewport = GraphViewport(
            size: CGSize(width: 390, height: 360), camera: camera, zoom: 2, pan: CGSize(width: 30, height: -20))
        let point = GraphPoint(x: 42, y: -17)
        let back = viewport.layout(viewport.screen(point))
        #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
        #expect(viewport.screen(camera.center) == CGPoint(x: 195 + 30, y: 180 - 20))
        #expect(GraphCamera.fitting([]) == GraphCamera())
        #expect(GraphCamera.fitting([.zero], focus: GraphPoint(x: 9, y: 9)).center == GraphPoint(x: 9, y: 9))

        let nodes = ["a", "b"].map { GraphNode(id: $0, name: $0, kind: .place, count: 0) }
        let points = [GraphPoint(x: 100, y: 50), GraphPoint(x: 110, y: 50)]
        let first = viewport.screen(points[0])
        let second = viewport.screen(points[1])
        func hit(_ x: CGFloat, _ y: CGFloat, minimum: Double = 22) -> Int? {
            viewport.nodeIndex(at: CGPoint(x: x, y: y), nodes: nodes, points: points, minimumRadius: minimum)
        }
        #expect(hit(first.x - 1, first.y) == 0 && hit(second.x + 1, second.y) == 1, "nearest node wins")
        #expect(hit(first.x - 21, first.y) == 0, "inside the 44 pt tap target")
        #expect(hit(first.x - 40, first.y) == nil)
        #expect(hit(first.x - 21, first.y, minimum: 1) == nil, "a pointer needs to be on the node itself")
    }

    @Test func dragStartingOnANodeMovesTheNodeAndOnEmptyCanvasPans() throws {
        let nodes = [GraphNode(id: "a", name: "a", kind: .person, count: 0)]
        let points = [GraphPoint(x: 20, y: 10)]
        let viewport = GraphViewport(
            size: CGSize(width: 300, height: 300), camera: GraphCamera(), zoom: 1.5, pan: CGSize(width: 12, height: 0))
        let center = viewport.screen(points[0])
        let start = CGPoint(x: center.x + 6, y: center.y - 4)

        let grab = GraphGrab.begin(at: start, viewport: viewport, nodes: nodes, points: points, minimumRadius: 22)
        guard case .node(let index, _) = grab else {
            Issue.record("a drag that starts on a node must take the node")
            return
        }
        #expect(index == 0)
        let held = try #require(grab.target(for: start, viewport: viewport))
        #expect(held.distance(to: points[0]) < 1e-9, "the node does not jump under the finger")
        let moved = try #require(
            grab.target(for: CGPoint(x: start.x + 30, y: start.y + 15), viewport: viewport))
        #expect(abs(moved.x - (points[0].x + 30 / viewport.scale)) < 1e-9)
        #expect(abs(moved.y - (points[0].y + 15 / viewport.scale)) < 1e-9)

        let empty = GraphGrab.begin(
            at: CGPoint(x: center.x + 120, y: center.y), viewport: viewport, nodes: nodes, points: points,
            minimumRadius: 22)
        #expect(empty == .canvas && empty.target(for: start, viewport: viewport) == nil)
    }

    @Test func screenLoadsSettledOrLiveAndKeepsAHandArrangedLayoutOnRefresh() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let settled = GraphLayout.compute(
            GraphModel.compute(input: context.store.content.graphInput, filter: GraphFilter(), today: today))

        // Reduce Motion / image tests: the finished layout, nothing running.
        let still = GraphScreenModel(store: context.store, focus: "people/Deniz Arıkan.md")
        await still.load(today: today, live: false)
        #expect(still.positions == settled && !still.motion.isRunning && !still.motion.isLive)
        #expect(still.camera.center == settled["people/Deniz Arıkan.md"], "the focused node is centered")
        #expect(still.camera.width > 120)

        // Live: starts unsettled, framed for where it will end up, and ends in the same picture.
        let live = GraphScreenModel(store: context.store)
        await live.load(today: today)
        #expect(live.motion.isRunning && live.positions != settled)
        #expect(live.camera == GraphCamera.fitting(live.motion.nodes.map { settled[$0.id]! }))
        _ = rest(live.motion)
        #expect(live.positions == settled)

        // Selecting from the menu recenters; a tap on the canvas does not.
        live.pan = CGSize(width: 40, height: 0)
        live.select("places/Liman Ofis.md", recenter: false)
        #expect(live.pan.width == 40 && live.camera.center != settled["places/Liman Ofis.md"])
        live.select("places/Liman Ofis.md", recenter: true)
        #expect(live.pan == .zero && live.camera.center == settled["places/Liman Ofis.md"])

        // The user drags a node; an index refresh with the same graph leaves it alone.
        let index = try #require(live.motion.index(of: "people/Deniz Arıkan.md"))
        live.motion.beginDrag(index, at: GraphPoint(x: 900, y: 900))
        live.motion.endDrag()
        _ = rest(live.motion)
        let arranged = live.positions
        #expect(arranged != settled)
        await live.load(today: today)
        #expect(live.positions == arranged && !live.motion.isRunning)

        // The center control frames the layout as it is now.
        live.recenter()
        #expect(live.camera.center == arranged["places/Liman Ofis.md"] && live.pan == .zero)

        // A changed graph rearranges from where the nodes are instead of starting over.
        live.filter.people = false
        await live.load(today: today)
        #expect(live.graph.nodes.count == 4 && live.selected == "places/Liman Ofis.md")
        #expect(live.positions["places/Liman Ofis.md"] == arranged["places/Liman Ofis.md"])
    }
}
