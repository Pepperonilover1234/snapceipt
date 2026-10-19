import SwiftUI

/// A force-directed layout: linked nodes pull together like rubber bands, every node pushes
/// the others away, and everything drifts to the centre. It cools down and stops once settled,
/// and warms up again when the graph or a force changes.
@MainActor @Observable
final class GraphSimulation {
    struct Body {
        var position: CGPoint
        var velocity: CGVector = .zero
    }

    private(set) var ids: [String] = []
    private(set) var bodies: [Body] = []
    private(set) var links: [(Int, Int)] = []
    /// How hard each node pushes: busy hubs push more, so they spread out and their labels don't collide.
    private var mass: [Double] = []
    private var slot: [String: Int] = [:]
    /// Changes every step, so views that draw positions redraw.
    private(set) var tick = 0
    private(set) var heat: Double = 1
    var pinned: Int?

    var center = 0.5
    var repel = 10.0
    var linkForce = 1.0
    var linkDistance = 120.0

    var isMoving: Bool { heat > 0.005 }

    func index(of id: String) -> Int? { slot[id] }
    func position(of id: String) -> CGPoint? { slot[id].map { bodies[$0].position } }

    /// Shows a new set of nodes and links. Nodes already on screen keep their place;
    /// new ones start next to a linked neighbour, or on a ring.
    func update(nodes newIDs: [String], edges: [(String, String)], masses: [String: Double] = [:]) {
        let old = Dictionary(uniqueKeysWithValues: zip(ids, bodies))
        var newSlot: [String: Int] = [:]
        for (i, id) in newIDs.enumerated() { newSlot[id] = i }
        var placed: [Body?] = newIDs.map { old[$0] }
        let neighbour = Dictionary(edges.flatMap { [($0.0, $0.1), ($0.1, $0.0)] }, uniquingKeysWith: { a, _ in a })
        for (i, id) in newIDs.enumerated() where placed[i] == nil {
            let angle = Double(abs(id.hashValue % 3600)) / 3600 * 2 * .pi
            if let other = neighbour[id], let near = old[other] {
                placed[i] = Body(position: CGPoint(x: near.position.x + cos(angle) * 30, y: near.position.y + sin(angle) * 30))
            } else {
                let ring = 80 + Double(i % 7) * 25
                placed[i] = Body(position: CGPoint(x: cos(angle) * ring, y: sin(angle) * ring))
            }
        }
        ids = newIDs
        slot = newSlot
        bodies = placed.map { $0! }
        mass = newIDs.map { masses[$0] ?? 1 }
        links = edges.compactMap { a, b in newSlot[a].flatMap { i in newSlot[b].map { (i, $0) } } }
        pinned = nil
        reheat(old.isEmpty ? 1 : 0.6)
    }

    func reheat(_ amount: Double = 0.5) {
        heat = max(heat, amount)
        tick += 1
    }

    func move(_ index: Int, to point: CGPoint) {
        guard bodies.indices.contains(index) else { return }
        bodies[index].position = point
        bodies[index].velocity = .zero
        reheat(0.3)
    }

    /// Runs until settled without drawing, for Reduce Motion.
    func settle() {
        var steps = 0
        while isMoving && steps < 600 { step(); steps += 1 }
    }

    func step() {
        let n = bodies.count
        guard n > 0 else { heat = 0; return }
        var force = [CGVector](repeating: .zero, count: n)
        let strength = repel * 260

        func push(_ i: Int, from point: CGPoint, mass: Double) {
            var dx = bodies[i].position.x - point.x
            var dy = bodies[i].position.y - point.y
            if dx == 0 && dy == 0 { dx = Double(i % 3) - 1; dy = Double(i % 5) - 2 }
            let d2 = max(dx * dx + dy * dy, 36)
            let d = d2.squareRoot()
            let f = strength * mass / d2
            force[i].dx += dx / d * f
            force[i].dy += dy / d * f
        }

        if n <= 300 {
            for i in 0..<n {
                for j in 0..<n where j != i { push(i, from: bodies[j].position, mass: mass[j]) }
            }
        } else {
            // Past a few hundred nodes, nearby nodes push one by one and far-away ones as a cell.
            let size = max(linkDistance * 2, 120)
            var cells: [SIMD2<Int>: [Int]] = [:]
            for i in 0..<n {
                let p = bodies[i].position
                cells[SIMD2(Int((p.x / size).rounded(.down)), Int((p.y / size).rounded(.down))), default: []].append(i)
            }
            let summaries = cells.mapValues { members -> (CGPoint, Double) in
                let x = members.reduce(0) { $0 + bodies[$1].position.x } / Double(members.count)
                let y = members.reduce(0) { $0 + bodies[$1].position.y } / Double(members.count)
                return (CGPoint(x: x, y: y), members.reduce(0) { $0 + mass[$1] })
            }
            for (cell, members) in cells {
                for i in members {
                    for (other, summary) in summaries {
                        if abs(other.x - cell.x) <= 1 && abs(other.y - cell.y) <= 1 {
                            for j in cells[other]! where j != i { push(i, from: bodies[j].position, mass: mass[j]) }
                        } else {
                            push(i, from: summary.0, mass: summary.1)
                        }
                    }
                }
            }
        }

        let spring = linkForce * 0.06
        for (a, b) in links {
            let dx = bodies[b].position.x - bodies[a].position.x
            let dy = bodies[b].position.y - bodies[a].position.y
            let d = max((dx * dx + dy * dy).squareRoot(), 1)
            let pull = (d - linkDistance) * spring
            force[a].dx += dx / d * pull; force[a].dy += dy / d * pull
            force[b].dx -= dx / d * pull; force[b].dy -= dy / d * pull
        }

        let gravity = center * 0.03
        for i in 0..<n where i != pinned {
            force[i].dx -= bodies[i].position.x * gravity
            force[i].dy -= bodies[i].position.y * gravity
            var v = bodies[i].velocity
            v.dx = (v.dx + force[i].dx * heat) * 0.6
            v.dy = (v.dy + force[i].dy * heat) * 0.6
            // A cap keeps a strong repel force from flinging nodes off screen.
            let speed = (v.dx * v.dx + v.dy * v.dy).squareRoot()
            if speed > 40 { v.dx *= 40 / speed; v.dy *= 40 / speed }
            bodies[i].velocity = v
            bodies[i].position.x += v.dx
            bodies[i].position.y += v.dy
        }
        heat *= 0.985
        tick &+= 1
    }

    /// The scale that fits every node on screen.
    func fitScale(in size: CGSize) -> Double {
        guard !bodies.isEmpty else { return 1 }
        let halfW = bodies.map { abs($0.position.x) }.max()! + 70
        let halfH = bodies.map { abs($0.position.y) }.max()! + 50
        return min(size.width / (2 * halfW), size.height / (2 * halfH), 1.6)
    }
}
