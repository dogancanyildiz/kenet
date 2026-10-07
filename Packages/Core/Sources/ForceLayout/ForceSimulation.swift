import Foundation

/// A point (or velocity) in layout space.
public struct ForcePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = Self(x: 0, y: 0)
    public func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
}

/// A spring between two bodies, addressed by body index.
public struct ForceLink: Sendable, Equatable {
    public var source: Int
    public var target: Int
    /// Rest length between the two centers.
    public var length: Double
    public init(source: Int, target: Int, length: Double) {
        self.source = source
        self.target = target
        self.length = length
    }
}

/// Tuning constants. Distances are layout points, speeds are points per step.
public struct ForceParameters: Sendable, Equatable {
    /// Strength of the pairwise push; grows with the square of the wanted spacing.
    public var repulsion = 100.0
    /// Pull toward the origin, so unconnected bodies stay in view.
    public var gravity = 0.05
    /// Clearance kept around each body beyond its radius.
    public var collisionPadding = 5.0
    /// Share of an overlap resolved per step.
    public var collisionStrength = 0.7
    /// Share of velocity lost per step.
    public var damping = 0.4
    /// Cooling rate: `alpha` moves this share of the way to its target each step.
    public var cooling = 0.0228
    /// The simulation rests once `alpha` cools below this.
    public var restAlpha = 0.001
    /// The simulation also rests once no body moves faster than this.
    public var restSpeed = 0.01
    /// `alpha` held while a body is pinned (dragged), and the least it is reheated to on release.
    public var dragAlpha = 0.3
    /// Barnes-Hut opening angle: larger is faster and coarser.
    public var theta = 0.9
    /// Speed cap per step; keeps a violent start from throwing bodies far away.
    public var maximumSpeed = 60.0
    /// Spacing of the initial spiral.
    public var initialSpacing = 14.0
    public init() {}
}

/// Live force-directed layout: bodies repel, links pull like springs, gravity keeps the whole
/// centered and collisions keep circles apart. Pure and deterministic: the same bodies, links,
/// seed and sequence of calls always produce the same positions.
///
/// The model follows velocity Verlet with a cooling factor (`alpha`): forces scale with `alpha`,
/// which decays toward zero, so the layout settles and the simulation comes to rest. Pinning a
/// body (dragging) holds `alpha` up; releasing it lets the layout cool again.
public struct ForceSimulation: Sendable {
    public let parameters: ForceParameters
    public let radii: [Double]
    public let links: [ForceLink]
    public private(set) var positions: [ForcePoint]
    public private(set) var velocities: [ForcePoint]
    public private(set) var alpha: Double
    public private(set) var isAtRest: Bool
    /// Steps taken since creation.
    public private(set) var stepCount = 0

    private var pins: [ForcePoint?]
    private var pinnedCount = 0
    private let linkStrength: [Double]
    private let linkBias: [Double]
    private let maximumRadius: Double

    public var count: Int { radii.count }
    public var isDragging: Bool { pinnedCount > 0 }

    /// Sum of squared speeds: zero at rest.
    public var kineticEnergy: Double {
        velocities.reduce(0) { $0 + $1.x * $1.x + $1.y * $1.y } / 2
    }

    /// - Parameters:
    ///   - radii: one entry per body.
    ///   - links: springs; entries with an out-of-range index or equal ends are dropped.
    ///   - seed: perturbs the initial spiral, so different seeds give different layouts.
    ///   - initial: known starting positions (for example carried over from a previous layout);
    ///     `nil` or missing entries start next to a placed neighbor, or on the spiral.
    ///   - alpha: starting temperature in 0...1. A fresh layout starts hot (1); one that is
    ///     mostly in place already can start warmer and rearrange less.
    public init(
        radii: [Double], links: [ForceLink], seed: UInt64 = 42, initial: [ForcePoint?] = [], alpha: Double = 1,
        parameters: ForceParameters = ForceParameters()
    ) {
        let count = radii.count
        self.parameters = parameters
        self.alpha = alpha.isFinite ? min(1, max(parameters.restAlpha, alpha)) : 1
        self.radii = radii.map { $0.isFinite ? max(0, $0) : 0 }
        let valid = links.filter {
            $0.source != $0.target && $0.source >= 0 && $0.target >= 0 && $0.source < count && $0.target < count
                && $0.length.isFinite
        }
        self.links = valid
        var degree = Array(repeating: 0, count: count)
        for link in valid {
            degree[link.source] += 1
            degree[link.target] += 1
        }
        linkStrength = valid.map { 1 / Double(min(degree[$0.source], degree[$0.target])) }
        linkBias = valid.map { Double(degree[$0.source]) / Double(degree[$0.source] + degree[$0.target]) }
        maximumRadius = self.radii.max() ?? 0
        velocities = Array(repeating: .zero, count: count)
        pins = Array(repeating: nil, count: count)
        isAtRest = count == 0
        positions = Self.startingPositions(
            count: count, links: valid, seed: seed, initial: initial, spacing: parameters.initialSpacing)
    }

    // MARK: - Stepping

    /// Advances one fixed step. Returns `true` while the layout is still moving.
    @discardableResult
    public mutating func step() -> Bool {
        guard !isAtRest else { return false }
        let target = pinnedCount > 0 ? parameters.dragAlpha : 0
        alpha += (target - alpha) * parameters.cooling
        applyLinks()
        applyRepulsion()
        applyGravity()
        applyCollisions()
        let fastest = integrate()
        stepCount += 1
        if pinnedCount == 0 && (alpha < parameters.restAlpha || fastest < parameters.restSpeed) {
            rest()
        }
        return !isAtRest
    }

    /// Steps until the layout rests, `maximumSteps` pass or `shouldCancel` says stop.
    /// Returns the number of steps taken.
    @discardableResult
    public mutating func settle(maximumSteps: Int = 600, shouldCancel: () -> Bool = { false }) -> Int {
        var taken = 0
        while taken < maximumSteps && !isAtRest {
            if taken % 8 == 0 && shouldCancel() { break }
            step()
            taken += 1
        }
        return taken
    }

    /// Wakes a resting simulation (or warms a cooling one) to at least `alpha`.
    public mutating func reheat(to alpha: Double = 1) {
        guard count > 0 else { return }
        self.alpha = max(self.alpha, min(1, max(0, alpha)))
        isAtRest = false
    }

    // MARK: - Pinning (dragging)

    /// Holds a body at `point`: it stops reacting to forces and its neighbors follow on springs.
    /// Call again with a new point as the pointer moves.
    public mutating func pin(_ index: Int, at point: ForcePoint) {
        guard positions.indices.contains(index), point.x.isFinite, point.y.isFinite else { return }
        if pins[index] == nil { pinnedCount += 1 }
        pins[index] = point
        positions[index] = point
        velocities[index] = .zero
        reheat(to: parameters.dragAlpha)
    }

    /// Releases a pinned body; the layout cools back to rest.
    public mutating func unpin(_ index: Int) {
        guard positions.indices.contains(index), pins[index] != nil else { return }
        pins[index] = nil
        pinnedCount -= 1
        reheat(to: parameters.dragAlpha)
    }

    public func isPinned(_ index: Int) -> Bool { pins.indices.contains(index) && pins[index] != nil }

    // MARK: - Forces

    private mutating func rest() {
        isAtRest = true
        for index in velocities.indices { velocities[index] = .zero }
    }

    private mutating func applyLinks() {
        for (index, link) in links.enumerated() {
            let source = link.source
            let target = link.target
            var dx = positions[target].x + velocities[target].x - positions[source].x - velocities[source].x
            var dy = positions[target].y + velocities[target].y - positions[source].y - velocities[source].y
            if dx == 0 && dy == 0 {
                dx = 1e-3
                dy = source < target ? 1e-3 : -1e-3
            }
            let distance = (dx * dx + dy * dy).squareRoot()
            let pull = (distance - link.length) / distance * alpha * linkStrength[index]
            dx *= pull
            dy *= pull
            let bias = linkBias[index]
            velocities[target].x -= dx * bias
            velocities[target].y -= dy * bias
            velocities[source].x += dx * (1 - bias)
            velocities[source].y += dy * (1 - bias)
        }
    }

    private mutating func applyRepulsion() {
        guard count > 1 else { return }
        let tree = QuadTree(positions: positions)
        let strength = parameters.repulsion * alpha
        tree.addRepulsion(
            to: &velocities, positions: positions, strength: strength, theta: parameters.theta)
    }

    private mutating func applyGravity() {
        let pull = parameters.gravity * alpha
        for index in positions.indices {
            velocities[index].x -= positions[index].x * pull
            velocities[index].y -= positions[index].y * pull
        }
    }

    /// Uniform grid, cell at least one padded diameter wide: only neighboring cells can overlap.
    private mutating func applyCollisions() {
        let count = count
        guard count > 1, parameters.collisionStrength > 0 else { return }
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var predicted = positions
        for index in 0..<count {
            predicted[index].x += velocities[index].x
            predicted[index].y += velocities[index].y
            minX = min(minX, predicted[index].x)
            minY = min(minY, predicted[index].y)
            maxX = max(maxX, predicted[index].x)
            maxY = max(maxY, predicted[index].y)
        }
        let side = max(1, Int(Double(count).squareRoot().rounded(.up)) * 2)
        let reach = maximumRadius * 2 + parameters.collisionPadding
        let pitch = max(reach, 1e-6, (maxX - minX) / Double(side), (maxY - minY) / Double(side))
        let columns = min(side, Int((maxX - minX) / pitch)) + 1
        let rows = min(side, Int((maxY - minY) / pitch)) + 1
        var cells = Array(repeating: 0, count: count)
        var starts = Array(repeating: 0, count: columns * rows + 1)
        for index in 0..<count {
            let column = min(columns - 1, Int((predicted[index].x - minX) / pitch))
            let row = min(rows - 1, Int((predicted[index].y - minY) / pitch))
            cells[index] = row * columns + column
            starts[cells[index] + 1] += 1
        }
        for cell in 0..<(columns * rows) { starts[cell + 1] += starts[cell] }
        var cursor = starts
        var members = Array(repeating: 0, count: count)
        for index in 0..<count {
            members[cursor[cells[index]]] = index
            cursor[cells[index]] += 1
        }
        // Each unordered pair once: own cell (later members) plus four forward neighbors.
        let forward = [(1, 0), (-1, 1), (0, 1), (1, 1)]
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = row * columns + column
                let range = starts[cell]..<starts[cell + 1]
                for slot in range {
                    let first = members[slot]
                    for other in (slot + 1)..<range.upperBound {
                        collide(first, members[other], predicted: predicted)
                    }
                    for (dx, dy) in forward {
                        let x = column + dx
                        let y = row + dy
                        guard x >= 0, x < columns, y < rows else { continue }
                        let neighbor = y * columns + x
                        for other in starts[neighbor]..<starts[neighbor + 1] {
                            collide(first, members[other], predicted: predicted)
                        }
                    }
                }
            }
        }
    }

    private mutating func collide(_ first: Int, _ second: Int, predicted: [ForcePoint]) {
        let reach = radii[first] + radii[second] + parameters.collisionPadding
        var dx = predicted[first].x - predicted[second].x
        var dy = predicted[first].y - predicted[second].y
        var squared = dx * dx + dy * dy
        guard squared < reach * reach else { return }
        if squared == 0 {
            dx = 1e-3
            dy = first < second ? 1e-3 : -1e-3
            squared = dx * dx + dy * dy
        }
        let distance = squared.squareRoot()
        let push = (reach - distance) / distance * parameters.collisionStrength
        dx *= push
        dy *= push
        // The smaller body yields more; a pinned body does not yield at all.
        let firstArea = radii[first] * radii[first]
        let secondArea = radii[second] * radii[second]
        var share = firstArea + secondArea > 0 ? secondArea / (firstArea + secondArea) : 0.5
        if pins[first] != nil { share = 0 } else if pins[second] != nil { share = 1 }
        velocities[first].x += dx * share
        velocities[first].y += dy * share
        velocities[second].x -= dx * (1 - share)
        velocities[second].y -= dy * (1 - share)
    }

    /// Applies damping and velocities; returns the fastest speed among free bodies.
    private mutating func integrate() -> Double {
        let keep = 1 - parameters.damping
        let limit = parameters.maximumSpeed
        var fastest = 0.0
        for index in positions.indices {
            if pins[index] != nil {
                // `pin` already put the body where it is held; forces must not move it.
                velocities[index] = .zero
                continue
            }
            var vx = velocities[index].x * keep
            var vy = velocities[index].y * keep
            var speed = (vx * vx + vy * vy).squareRoot()
            if !speed.isFinite {
                vx = 0
                vy = 0
                speed = 0
            } else if speed > limit {
                vx *= limit / speed
                vy *= limit / speed
                speed = limit
            }
            velocities[index] = ForcePoint(x: vx, y: vy)
            positions[index].x += vx
            positions[index].y += vy
            fastest = max(fastest, speed)
        }
        return fastest
    }

    // MARK: - Start

    private static func startingPositions(
        count: Int, links: [ForceLink], seed: UInt64, initial: [ForcePoint?], spacing: Double
    ) -> [ForcePoint] {
        var state = seed
        func jitter() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(UInt64.max >> 11) - 0.5
        }
        func spiral(_ slot: Int) -> ForcePoint {
            let angle = Double(slot) * 2.399963229728653
            let radius = spacing * (0.5 + Double(slot)).squareRoot()
            return ForcePoint(x: cos(angle) * radius + jitter(), y: sin(angle) * radius + jitter())
        }
        var placed: [ForcePoint?] = (0..<count).map { index in
            guard index < initial.count, let point = initial[index], point.x.isFinite, point.y.isFinite else {
                return nil
            }
            return point
        }
        guard placed.contains(where: { $0 != nil }) else { return (0..<count).map(spiral) }
        // Newcomers appear beside a neighbor that already has a place, otherwise near the middle.
        var anchors: [Int: ForcePoint] = [:]
        for link in links {
            if placed[link.source] == nil, anchors[link.source] == nil, let point = placed[link.target] {
                anchors[link.source] = point
            }
            if placed[link.target] == nil, anchors[link.target] == nil, let point = placed[link.source] {
                anchors[link.target] = point
            }
        }
        var slot = 0
        for index in 0..<count where placed[index] == nil {
            let offset = spiral(slot)
            let anchor = anchors[index] ?? .zero
            placed[index] = ForcePoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
            slot += 1
        }
        return placed.map { $0 ?? .zero }
    }
}
