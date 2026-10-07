import Foundation
import Testing

@testable import ForceLayout

struct ForceSimulationTests {
    /// Reproducible random graph: radii in 10...24, links between random distinct bodies.
    static func sample(bodies: Int, links: Int, seed: UInt64 = 7) -> (radii: [Double], links: [ForceLink]) {
        var state = seed
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let radii = (0..<bodies).map { _ in 10 + Double(next(15)) }
        var result: [ForceLink] = []
        while result.count < links {
            let source = next(bodies)
            let target = next(bodies)
            if source != target { result.append(ForceLink(source: source, target: target, length: 90)) }
        }
        return (radii, result)
    }

    @Test func sameInputAndSeedGiveSameLayoutAndAnotherSeedDiffers() {
        let graph = Self.sample(bodies: 60, links: 90)
        var first = ForceSimulation(radii: graph.radii, links: graph.links, seed: 42)
        var second = ForceSimulation(radii: graph.radii, links: graph.links, seed: 42)
        var other = ForceSimulation(radii: graph.radii, links: graph.links, seed: 43)
        #expect(first.positions == second.positions)
        for _ in 0..<40 {
            first.step()
            second.step()
        }
        #expect(first.positions == second.positions && first.velocities == second.velocities)
        let firstSteps = first.settle()
        let secondSteps = second.settle()
        other.settle()
        #expect(firstSteps == secondSteps)
        #expect(first.positions == second.positions)
        #expect(first.positions != other.positions)
    }

    @Test func layoutSettlesToRestAndThenDoesNoWork() {
        let graph = Self.sample(bodies: 60, links: 90)
        var simulation = ForceSimulation(radii: graph.radii, links: graph.links)
        #expect(!simulation.isAtRest && simulation.alpha == 1)
        let steps = simulation.settle()
        #expect(steps > 10 && steps <= 320)
        #expect(simulation.isAtRest && simulation.kineticEnergy == 0)
        let settled = simulation.positions
        let moving = simulation.step()
        let extra = simulation.settle()
        #expect(!moving && extra == 0)
        #expect(simulation.positions == settled && simulation.stepCount == steps)
    }

    @Test func layoutRestsAsSoonAsNothingMovesAndAWarmStartCoolsSooner() {
        // A small layout finds its place long before the cooling runs out: low speed ends it.
        let graph = Self.sample(bodies: 12, links: 14)
        var small = ForceSimulation(radii: graph.radii, links: graph.links)
        let steps = small.settle()
        #expect(small.isAtRest && steps < 280, "rested after \(steps) steps")
        #expect(small.alpha > small.parameters.restAlpha * 2, "rested at alpha \(small.alpha)")

        // A layout carried over from the screen starts warm, not hot, and moves less.
        var hot = ForceSimulation(radii: graph.radii, links: graph.links, initial: small.positions)
        var warm = ForceSimulation(radii: graph.radii, links: graph.links, initial: small.positions, alpha: 0.3)
        #expect(hot.alpha == 1 && warm.alpha == 0.3 && !warm.isAtRest)
        let hotSteps = hot.settle()
        let warmSteps = warm.settle()
        #expect(warmSteps < hotSteps && warm.isAtRest)
        func drift(_ simulation: ForceSimulation) -> Double {
            zip(simulation.positions, small.positions).map { $0.distance(to: $1) }.max() ?? 0
        }
        #expect(drift(warm) < drift(hot), "warm \(drift(warm)) vs hot \(drift(hot))")
    }

    @Test func settledBodiesAreFiniteCenteredAndDoNotOverlap() {
        for (bodies, links) in [(12, 14), (300, 600), (300, 0)] {
            let graph = Self.sample(bodies: bodies, links: links)
            var simulation = ForceSimulation(radii: graph.radii, links: graph.links)
            simulation.settle()
            let points = simulation.positions
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            let middle = ForcePoint(
                x: points.map(\.x).reduce(0, +) / Double(bodies), y: points.map(\.y).reduce(0, +) / Double(bodies))
            let spread = points.map { $0.distance(to: middle) }.max() ?? 0
            #expect(middle.distance(to: .zero) < spread * 0.1, "gravity keeps the layout around the origin")
            #expect(spread < 60 * Double(bodies).squareRoot() + 200, "gravity bounds the layout: \(spread)")
            var tightest = Double.infinity
            for first in 0..<bodies {
                for second in (first + 1)..<bodies {
                    let gap = points[first].distance(to: points[second]) - graph.radii[first] - graph.radii[second]
                    tightest = min(tightest, gap)
                }
            }
            #expect(tightest >= 3, "circles keep clearance, tightest gap \(tightest)")
        }
    }

    @Test func springsPullLinkedBodiesTogetherAndRepulsionKeepsStrangersApart() {
        // 0-1 linked, 2 unconnected.
        var simulation = ForceSimulation(
            radii: [10, 10, 10], links: [ForceLink(source: 0, target: 1, length: 60)])
        simulation.settle()
        let linked = simulation.positions[0].distance(to: simulation.positions[1])
        let stranger = min(
            simulation.positions[2].distance(to: simulation.positions[0]),
            simulation.positions[2].distance(to: simulation.positions[1]))
        #expect(linked > 40 && linked < 110, "spring settles near its rest length, got \(linked)")
        #expect(stranger > linked, "unlinked body sits farther than the linked pair: \(stranger) vs \(linked)")

        // Without the spring the same pair drifts farther apart.
        var loose = ForceSimulation(radii: [10, 10, 10], links: [])
        loose.settle()
        #expect(loose.positions[0].distance(to: loose.positions[1]) > linked)
    }

    @Test func pinnedBodyFollowsThePointerAndNeighborsFollowOnSprings() {
        // Chain 0-1-2 plus an unconnected body 3.
        let links = [ForceLink(source: 0, target: 1, length: 60), ForceLink(source: 1, target: 2, length: 60)]
        var simulation = ForceSimulation(radii: [12, 12, 12, 12], links: links)
        simulation.settle()
        #expect(simulation.isAtRest)
        let before = simulation.positions
        let target = ForcePoint(x: before[0].x + 400, y: before[0].y)

        simulation.pin(0, at: target)
        #expect(!simulation.isAtRest && simulation.isDragging && simulation.isPinned(0))
        #expect(simulation.positions[0] == target, "the dragged body jumps to the pointer at once")
        for _ in 0..<600 {
            let moving = simulation.step()
            #expect(moving, "never rests while a body is held")
        }
        #expect(simulation.positions[0] == target, "forces do not move a pinned body")
        #expect(simulation.alpha > 0.25, "dragging keeps the layout warm")
        let neighbor = simulation.positions[1].x - before[1].x
        let second = simulation.positions[2].x - before[2].x
        let stranger = simulation.positions[3].x - before[3].x
        #expect(neighbor > 250, "the linked neighbor is dragged along, moved \(neighbor)")
        #expect(second > 150, "the pull travels down the chain, moved \(second)")
        #expect(abs(stranger) < neighbor / 2, "an unconnected body is not dragged along, moved \(stranger)")
        #expect(simulation.positions[0].distance(to: simulation.positions[1]) < 140)

        simulation.unpin(0)
        #expect(!simulation.isDragging && !simulation.isPinned(0) && !simulation.isAtRest)
        let steps = simulation.settle()
        #expect(simulation.isAtRest && steps < 400, "the layout rests again after release")
        #expect(simulation.positions[0] != target, "a released body is free again")
    }

    @Test func pinWakesARestingLayoutAndIgnoresBadInput() {
        var simulation = ForceSimulation(radii: [10, 10], links: [ForceLink(source: 0, target: 1, length: 50)])
        simulation.settle()
        let rested = simulation.positions
        simulation.pin(5, at: .zero)
        simulation.pin(0, at: ForcePoint(x: .nan, y: 0))
        simulation.unpin(0)
        #expect(simulation.isAtRest && simulation.positions == rested)
        simulation.pin(1, at: rested[1])
        #expect(!simulation.isAtRest)
        simulation.pin(1, at: ForcePoint(x: rested[1].x + 5, y: rested[1].y))
        simulation.unpin(1)
        simulation.unpin(1)
        #expect(!simulation.isDragging)
        simulation.settle()
        #expect(simulation.isAtRest)
    }

    @Test func carriedPositionsAreKeptAndNewcomersStartBesideANeighbor() {
        let links = [ForceLink(source: 0, target: 2, length: 60)]
        let carried: [ForcePoint?] = [ForcePoint(x: 500, y: -300), ForcePoint(x: -200, y: 100), nil, nil]
        let simulation = ForceSimulation(radii: [10, 10, 10, 10], links: links, initial: carried)
        #expect(simulation.positions[0] == carried[0] && simulation.positions[1] == carried[1])
        #expect(simulation.positions[2].distance(to: carried[0]!) < 40, "linked newcomer starts beside its neighbor")
        #expect(simulation.positions[3].distance(to: .zero) < 40, "unlinked newcomer starts near the middle")
        #expect(simulation.positions[2] != simulation.positions[3])
    }

    @Test func degenerateInputsAreHandled() {
        var empty = ForceSimulation(radii: [], links: [])
        let emptySteps = empty.settle()
        #expect(empty.isAtRest && emptySteps == 0 && empty.positions.isEmpty)
        empty.reheat()
        #expect(empty.isAtRest)

        var single = ForceSimulation(radii: [10], links: [ForceLink(source: 0, target: 0, length: 10)])
        #expect(single.links.isEmpty)
        single.settle()
        #expect(single.isAtRest && single.positions[0].distance(to: .zero) < 20)

        let dropped = ForceSimulation(
            radii: [10, 10],
            links: [
                ForceLink(source: 0, target: 2, length: 10), ForceLink(source: -1, target: 1, length: 10),
                ForceLink(source: 0, target: 1, length: .nan), ForceLink(source: 1, target: 0, length: 40),
            ])
        #expect(dropped.links == [ForceLink(source: 1, target: 0, length: 40)])

        // Bodies stacked on one point still separate.
        let stacked = Array(repeating: Optional(ForcePoint(x: 3, y: 3)), count: 20)
        var pile = ForceSimulation(radii: Array(repeating: 10, count: 20), links: [], initial: stacked)
        pile.settle()
        #expect(pile.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        for first in 0..<20 {
            for second in (first + 1)..<20 {
                #expect(pile.positions[first].distance(to: pile.positions[second]) >= 20)
            }
        }
    }

    @Test func treeMatchesExactPairwiseSumWhenNothingIsApproximated() {
        let graph = Self.sample(bodies: 80, links: 0)
        var simulation = ForceSimulation(radii: graph.radii, links: [])
        for _ in 0..<5 { simulation.step() }
        let points = simulation.positions
        var exact = Array(repeating: ForcePoint.zero, count: points.count)
        for first in points.indices {
            for second in points.indices where first != second {
                let dx = points[second].x - points[first].x
                let dy = points[second].y - points[first].y
                let factor = 100 / max(dx * dx + dy * dy, 16)
                exact[first].x -= dx * factor
                exact[first].y -= dy * factor
            }
        }
        let tree = QuadTree(positions: points)
        var precise = Array(repeating: ForcePoint.zero, count: points.count)
        tree.addRepulsion(to: &precise, positions: points, strength: 100, theta: 0)
        var approximate = Array(repeating: ForcePoint.zero, count: points.count)
        tree.addRepulsion(to: &approximate, positions: points, strength: 100, theta: 0.9)
        for index in points.indices {
            let size = max(1e-9, exact[index].distance(to: .zero))
            #expect(precise[index].distance(to: exact[index]) < size * 1e-9 + 1e-9)
            #expect(approximate[index].distance(to: exact[index]) < size * 0.25 + 0.05)
        }
    }

    /// Measures one step for 300 bodies and 600 links and prints it. The fastest of several
    /// batches is taken, because other tests run in parallel and add noise.
    ///
    /// This is an unoptimized test build on a shared machine, so the always-on ceiling is loose
    /// (two 60 Hz frames); it catches a step that became many times slower. A release build is
    /// roughly thirty times faster. Set `FORCE_STEP_BUDGET_MS` to enforce a tighter budget on a
    /// quiet machine.
    @Test func stepStaysWithinFrameBudgetForThreeHundredBodies() {
        let graph = Self.sample(bodies: 300, links: 600)
        var simulation = ForceSimulation(radii: graph.radii, links: graph.links)
        var fastest = Double.infinity
        var slowest = 0.0
        for _ in 0..<6 {
            let start = ContinuousClock.now
            for _ in 0..<20 { simulation.step() }
            let elapsed = start.duration(to: .now)
            let batch = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            fastest = min(fastest, batch / 20)
            slowest = max(slowest, batch / 20)
        }
        print("ForceSimulation 300 bodies/600 links: \(fastest) ms per step (slowest batch \(slowest) ms)")
        #expect(!simulation.isAtRest, "the measured steps did real work")
        let budget = ProcessInfo.processInfo.environment["FORCE_STEP_BUDGET_MS"].flatMap(Double.init) ?? 33
        #expect(fastest < budget, "one step took \(fastest) ms, budget \(budget) ms")
    }
}
