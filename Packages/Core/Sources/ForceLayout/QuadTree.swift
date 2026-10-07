import Foundation

/// Barnes-Hut tree over point masses: a far group of bodies acts as one body at its center of
/// mass, so the pairwise push costs O(n log n) instead of O(n²). Built fresh each step, in body
/// order, so results are reproducible.
struct QuadTree {
    private struct Cell {
        /// Index of the first of four children, or -1 for a leaf.
        var firstChild: Int32 = -1
        /// Leaf only: head of the chain of bodies stored here, or -1.
        var head: Int32 = -1
        var mass = 0.0
        var centerX = 0.0
        var centerY = 0.0
    }

    private var cells = [Cell()]
    /// Per body: next body in the same leaf, or -1.
    private var next: [Int32]
    private let originX: Double
    private let originY: Double
    private let extent: Double

    private static let maximumDepth = 32
    /// Closer pairs push as if they were this far apart; collisions take over from there.
    private static let minimumDistanceSquared = 16.0

    init(positions: [ForcePoint]) {
        var minX = 0.0
        var minY = 0.0
        var maxX = 0.0
        var maxY = 0.0
        if let first = positions.first {
            (minX, minY, maxX, maxY) = (first.x, first.y, first.x, first.y)
        }
        for point in positions {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        extent = max(maxX - minX, maxY - minY, 1e-6)
        originX = (minX + maxX) / 2
        originY = (minY + maxY) / 2
        next = Array(repeating: -1, count: positions.count)
        cells.reserveCapacity(positions.count * 3)
        for index in positions.indices { insert(Int32(index), positions: positions) }
        summarize(positions: positions)
    }

    private mutating func insert(_ body: Int32, positions: [ForcePoint]) {
        let point = positions[Int(body)]
        var node = 0
        var middleX = originX
        var middleY = originY
        var quarter = extent / 4
        var depth = 0
        while true {
            if cells[node].firstChild >= 0 {
                let right = point.x >= middleX
                let lower = point.y >= middleY
                node = Int(cells[node].firstChild) + (right ? 1 : 0) + (lower ? 2 : 0)
                middleX += right ? quarter : -quarter
                middleY += lower ? quarter : -quarter
                quarter /= 2
                depth += 1
                continue
            }
            let resident = cells[node].head
            if resident < 0 {
                cells[node].head = body
                return
            }
            let other = positions[Int(resident)]
            if depth >= Self.maximumDepth || (other.x == point.x && other.y == point.y) {
                next[Int(body)] = resident
                cells[node].head = body
                return
            }
            // Split: the resident chain moves into its quadrant, then the loop descends.
            let base = cells.count
            cells.append(contentsOf: [Cell(), Cell(), Cell(), Cell()])
            cells[base + (other.x >= middleX ? 1 : 0) + (other.y >= middleY ? 2 : 0)].head = resident
            cells[node].head = -1
            cells[node].firstChild = Int32(base)
        }
    }

    /// Children always sit after their parent, so one backward pass sums masses bottom-up.
    private mutating func summarize(positions: [ForcePoint]) {
        for node in stride(from: cells.count - 1, through: 0, by: -1) {
            var total = 0.0
            var sumX = 0.0
            var sumY = 0.0
            if cells[node].firstChild >= 0 {
                let base = Int(cells[node].firstChild)
                for child in base..<(base + 4) {
                    total += cells[child].mass
                    sumX += cells[child].centerX * cells[child].mass
                    sumY += cells[child].centerY * cells[child].mass
                }
            } else {
                var body = cells[node].head
                while body >= 0 {
                    total += 1
                    sumX += positions[Int(body)].x
                    sumY += positions[Int(body)].y
                    body = next[Int(body)]
                }
            }
            cells[node].mass = total
            if total > 0 {
                cells[node].centerX = sumX / total
                cells[node].centerY = sumY / total
            }
        }
    }

    /// Adds the push every other body exerts to each body's velocity.
    ///
    /// Runs on raw buffers with a fixed stack: this is the hot loop of every frame, and checked
    /// array access makes unoptimized builds an order of magnitude slower.
    func addRepulsion(
        to velocities: inout [ForcePoint], positions: [ForcePoint], strength: Double, theta: Double
    ) {
        // A pop pushes at most four entries, one level deeper each time.
        let capacity = (Self.maximumDepth + 2) * 4
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: capacity) { stack in
            withUnsafeTemporaryAllocation(of: Double.self, capacity: capacity) { sizes in
                velocities.withUnsafeMutableBufferPointer { velocities in
                    positions.withUnsafeBufferPointer { positions in
                        cells.withUnsafeBufferPointer { cells in
                            next.withUnsafeBufferPointer { next in
                                for index in 0..<positions.count {
                                    let push = Self.push(
                                        on: index, positions: positions, cells: cells, next: next, stack: stack,
                                        sizes: sizes, extent: extent, strength: strength, thetaSquared: theta * theta)
                                    velocities[index].x += push.x
                                    velocities[index].y += push.y
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func push(
        on index: Int, positions: UnsafeBufferPointer<ForcePoint>, cells: UnsafeBufferPointer<Cell>,
        next: UnsafeBufferPointer<Int32>, stack: UnsafeMutableBufferPointer<Int32>,
        sizes: UnsafeMutableBufferPointer<Double>, extent: Double, strength: Double, thetaSquared: Double
    ) -> ForcePoint {
        let pointX = positions[index].x
        let pointY = positions[index].y
        let softening = minimumDistanceSquared
        var pushX = 0.0
        var pushY = 0.0
        var top = 1
        stack[0] = 0
        sizes[0] = extent
        while top > 0 {
            top -= 1
            let cell = cells[Int(stack[top])]
            let size = sizes[top]
            if cell.mass == 0 { continue }
            if cell.firstChild >= 0 {
                let dx = cell.centerX - pointX
                let dy = cell.centerY - pointY
                let squared = dx * dx + dy * dy
                if size * size < thetaSquared * squared {
                    // Far enough: the whole cell acts as one mass.
                    let factor = strength * cell.mass / max(squared, softening)
                    pushX -= dx * factor
                    pushY -= dy * factor
                    continue
                }
                for child in 0..<4 {
                    stack[top + child] = cell.firstChild + Int32(child)
                    sizes[top + child] = size / 2
                }
                top += 4
                continue
            }
            var body = cell.head
            while body >= 0 {
                let other = Int(body)
                body = next[other]
                if other == index { continue }
                var dx = positions[other].x - pointX
                var dy = positions[other].y - pointY
                if dx == 0 && dy == 0 {
                    // Coincident bodies get a fixed, opposite nudge so they separate.
                    dx = index < other ? -1e-3 : 1e-3
                    dy = dx
                }
                let factor = strength / max(dx * dx + dy * dy, softening)
                pushX -= dx * factor
                pushY -= dy * factor
            }
        }
        return ForcePoint(x: pushX, y: pushY)
    }
}
