//
//  ShapeRecognizer.swift
//  ScriptureScribe
//
//  Turns a hand-drawn stroke into a clean shape for Auto Shapes (pen tool):
//  straight lines, circles, ovals, triangles, squares, rectangles, other
//  straight-sided shapes (diamonds, pentagons, stars), and open zig-zags.
//
//  How it works:
//    1. A nearly straight stroke becomes a line (made exactly flat or upright
//       when it's within a few degrees).
//    2. The stroke is resampled into evenly spaced points, and corners are found
//       wherever the direction turns sharply over a short distance.
//    3. A closed stroke with no corners becomes a circle or oval if it fits one.
//       A closed stroke with 3+ corners and straight sides becomes a straight-sided
//       shape; four right angles become a perfect rectangle or square.
//    4. An open stroke with corners and straight sides becomes straight segments
//       (an L, a check mark, a zig-zag).
//  Anything else returns nil, and the stroke stays hand-drawn.
//

import CoreGraphics
import Foundation

enum RecognizedShape {
    case line(CGPoint, CGPoint)
    /// Open path of straight segments through these points.
    case polyline([CGPoint])
    /// Closed straight-sided shape through these corners.
    case polygon([CGPoint])
    /// A circle when radiusX == radiusY. `rotation` is in radians.
    case ellipse(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, rotation: CGFloat)
}

enum ShapeRecognizer {

    // MARK: - Tuning

    private static let sampleCount          = 64
    private static let cornerWindow         = 3                        // samples each side when measuring a turn
    private static let cornerAngle          = 55.0 * CGFloat.pi / 180  // a sharper turn is a corner
    private static let minShapeSize: CGFloat      = 20                 // bounding-box diagonal, in points
    private static let lineStraightness: CGFloat  = 0.9                // end-to-end distance / drawn length
    private static let closedGap: CGFloat         = 0.22               // end gap / size to count as closed
    private static let maxSideBend: CGFloat       = 0.2                // a side's bulge / its length
    // Open strokes are held to a stricter standard so a pause in the middle of
    // handwriting (wavy, curvy strokes) doesn't get turned into a zig-zag.
    private static let maxOpenSideBend: CGFloat   = 0.1
    private static let maxOpenCorners             = 4
    private static let handShake: CGFloat         = 4                  // points of wobble always allowed on a side
    private static let maxEllipseError: CGFloat   = 0.13               // average distance off the oval, relative
    private static let circleRoundness: CGFloat   = 0.85               // short / long radius to call it a circle
    private static let axisSnap             = 6.0 * CGFloat.pi / 180   // snap angles this close to flat/upright
    private static let rightAngleTolerance  = 22.0 * CGFloat.pi / 180
    private static let squareTolerance: CGFloat   = 0.12               // side difference to call it a square

    // MARK: - Recognition

    static func recognize(_ input: [CGPoint]) -> RecognizedShape? {
        let points = removingDuplicates(input)
        guard points.count >= 5 else { return nil }
        let size = diagonal(of: points)
        let length = pathLength(points)
        guard size >= minShapeSize, length > 0 else { return nil }

        let first = points[0], last = points[points.count - 1]

        // 1. Nearly straight: a line.
        if distance(first, last) / length >= lineStraightness {
            return line(from: first, to: last)
        }

        // 2. Closed if the stroke comes back near its start. The tail past that
        //    point (an overshoot) is trimmed off.
        if let end = closingIndex(points, size: size) {
            let loop = Array(points[0...end]) + [first]
            var samples = resample(loop, count: sampleCount + 1)
            samples.removeLast()   // same as the first sample; the loop wraps around
            let corners = cornerIndices(samples, closed: true)

            if corners.count >= 3, corners.count <= 12,
               sidesAreStraight(samples, corners: corners, closed: true) {
                let vertices = corners.map { samples[$0] }
                return .polygon(vertices.count == 4 ? regularizedQuad(vertices) : vertices)
            }
            return ellipse(fitting: samples)
        }

        // 3. Open with corners and straight segments: a polyline.
        let samples = resample(points, count: sampleCount)
        let corners = cornerIndices(samples, closed: false)
        guard (1...maxOpenCorners).contains(corners.count) else { return nil }
        let breaks = [0] + corners + [samples.count - 1]
        guard sidesAreStraight(samples, corners: breaks, closed: false, maxBend: maxOpenSideBend) else { return nil }
        return .polyline(breaks.map { samples[$0] })
    }

    // MARK: - Outline for drawing

    /// Points to draw the shape with. Corners are repeated so they stay sharp, and
    /// extra points along each side keep it perfectly straight.
    static func outline(of shape: RecognizedShape) -> [CGPoint] {
        switch shape {
        case .line(let a, let b):
            return straightPath([a, b])
        case .polyline(let vertices):
            return straightPath(vertices)
        case .polygon(let vertices):
            return straightPath(vertices + [vertices[0]])
        case .ellipse(let center, let rx, let ry, let rotation):
            let count = 72
            var pts = (0..<count).map { i -> CGPoint in
                let t = CGFloat(i) / CGFloat(count) * 2 * .pi
                return rotated(CGPoint(x: rx * cos(t), y: ry * sin(t)), by: rotation) + center
            }
            pts.append(contentsOf: pts.prefix(3))   // carry on past the start so it closes smoothly
            return pts
        }
    }

    // MARK: - Shapes

    private static func line(from a: CGPoint, to b: CGPoint) -> RecognizedShape {
        let angle = atan2(b.y - a.y, b.x - a.x)
        if abs(sin(angle)) < sin(axisSnap) {          // nearly flat
            let y = (a.y + b.y) / 2
            return .line(CGPoint(x: a.x, y: y), CGPoint(x: b.x, y: y))
        }
        if abs(cos(angle)) < sin(axisSnap) {          // nearly upright
            let x = (a.x + b.x) / 2
            return .line(CGPoint(x: x, y: a.y), CGPoint(x: x, y: b.y))
        }
        return .line(a, b)
    }

    /// Fits a circle or oval to a closed loop of evenly spaced points.
    private static func ellipse(fitting samples: [CGPoint]) -> RecognizedShape? {
        let mean = average(samples)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in samples {
            let dx = p.x - mean.x, dy = p.y - mean.y
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        var rotation = 0.5 * atan2(2 * sxy, sxx - syy)   // direction of the long axis

        // Size from the extents along the axes.
        let local = samples.map { rotated($0 - mean, by: -rotation) }
        let xs = local.map(\.x), ys = local.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        var rx = (maxX - minX) / 2, ry = (maxY - minY) / 2
        guard rx > 4, ry > 4 else { return nil }
        let center = mean + rotated(CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), by: rotation)

        // How closely the drawing follows the oval.
        let error = samples.reduce(CGFloat(0)) { sum, p in
            let q = rotated(p - center, by: -rotation)
            return sum + abs(sqrt((q.x / rx) * (q.x / rx) + (q.y / ry) * (q.y / ry)) - 1)
        } / CGFloat(samples.count)
        guard error <= maxEllipseError else { return nil }

        if min(rx, ry) / max(rx, ry) >= circleRoundness {
            let r = (rx + ry) / 2
            return .ellipse(center: center, radiusX: r, radiusY: r, rotation: 0)
        }
        // Make nearly flat or upright ovals exactly flat or upright.
        if abs(sin(rotation)) < sin(axisSnap) {
            rotation = 0
        } else if abs(cos(rotation)) < sin(axisSnap) {
            rotation = 0
            swap(&rx, &ry)
        }
        return .ellipse(center: center, radiusX: rx, radiusY: ry, rotation: rotation)
    }

    /// Four corners with right angles become a perfect rectangle (or square), squared
    /// to the page when it's nearly level. Other four-sided shapes stay as drawn.
    private static func regularizedQuad(_ c: [CGPoint]) -> [CGPoint] {
        for i in 0..<4 {
            let angle = angleBetween(c[(i + 3) % 4] - c[i], c[(i + 1) % 4] - c[i])
            if abs(angle - .pi / 2) > rightAngleTolerance { return c }
        }

        // Orientation: the sides' average direction, folded into a quarter turn.
        var sx: CGFloat = 0, sy: CGFloat = 0
        for i in 0..<4 {
            let d = c[(i + 1) % 4] - c[i]
            let a = atan2(d.y, d.x), len = hypot(d.x, d.y)
            sx += cos(4 * a) * len; sy += sin(4 * a) * len
        }
        var theta = atan2(sy, sx) / 4
        if abs(theta) < axisSnap { theta = 0 }

        let center = average(c)
        let local = c.map { rotated($0 - center, by: -theta) }
        let xs = local.map(\.x).sorted(), ys = local.map(\.y).sorted()
        let left = (xs[0] + xs[1]) / 2, right  = (xs[2] + xs[3]) / 2
        let top  = (ys[0] + ys[1]) / 2, bottom = (ys[2] + ys[3]) / 2
        var halfW = (right - left) / 2, halfH = (bottom - top) / 2
        let mid = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        if abs(halfW - halfH) / max(halfW, halfH) < squareTolerance {
            let side = (halfW + halfH) / 2
            halfW = side; halfH = side
        }
        return [CGPoint(x: -halfW, y: -halfH), CGPoint(x: halfW, y: -halfH),
                CGPoint(x: halfW, y: halfH),   CGPoint(x: -halfW, y: halfH)]
            .map { rotated($0 + mid, by: theta) + center }
    }

    // MARK: - Corners and sides

    /// Indices of sharp turns, at least a corner-window apart.
    private static func cornerIndices(_ s: [CGPoint], closed: Bool) -> [Int] {
        let n = s.count, k = cornerWindow
        var turn = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let before: CGPoint, after: CGPoint
            if closed {
                before = s[(i - k + n) % n]; after = s[(i + k) % n]
            } else {
                guard i - k >= 0, i + k < n else { continue }
                before = s[i - k]; after = s[i + k]
            }
            turn[i] = angleBetween(s[i] - before, after - s[i])
        }
        var picked: [Int] = []
        for i in (0..<n).filter({ turn[$0] >= cornerAngle }).sorted(by: { turn[$0] > turn[$1] }) {
            let tooClose = picked.contains { j in
                let d = abs(i - j)
                return (closed ? min(d, n - d) : d) <= k
            }
            if !tooClose { picked.append(i) }
        }
        return picked.sorted()
    }

    /// True when the points between each pair of breaks stay close to a straight line.
    /// A little hand shake is always allowed, so short sides aren't judged too harshly.
    private static func sidesAreStraight(_ s: [CGPoint], corners: [Int], closed: Bool,
                                         maxBend: CGFloat = maxSideBend) -> Bool {
        let pairs = closed ? corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
                           : zip(corners, corners.dropFirst()).map { ($0, $1) }
        for (from, to) in pairs {
            let a = s[from], b = s[to]
            let side = distance(a, b)
            guard side > 0 else { return false }
            var i = (from + 1) % s.count
            while i != to {
                if distanceFromLine(s[i], a, b) > max(maxBend * side, handShake) { return false }
                i = (i + 1) % s.count
            }
        }
        return true
    }

    /// Where a closed stroke gets back to its start: the point in the last part of the
    /// stroke closest to the start, if it's close enough.
    private static func closingIndex(_ p: [CGPoint], size: CGFloat) -> Int? {
        let from = max(Int(Double(p.count) * 0.6), 2)
        guard from < p.count else { return nil }
        var best = from, bestDistance = CGFloat.infinity
        for i in from..<p.count {
            let d = distance(p[i], p[0])
            if d < bestDistance { best = i; bestDistance = d }
        }
        return bestDistance <= size * closedGap ? best : nil
    }

    // MARK: - Geometry helpers

    /// Corners repeated so they stay sharp, with points along each side to keep it straight.
    private static func straightPath(_ vertices: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for (i, v) in vertices.enumerated() {
            out += [v, v, v]
            guard i + 1 < vertices.count else { break }
            let w = vertices[i + 1]
            for t in [0.25, 0.5, 0.75] as [CGFloat] {
                out.append(CGPoint(x: v.x + (w.x - v.x) * t, y: v.y + (w.y - v.y) * t))
            }
        }
        return out
    }

    /// Evenly spaced points along the path.
    private static func resample(_ input: [CGPoint], count: Int) -> [CGPoint] {
        var pts = input
        let interval = pathLength(pts) / CGFloat(count - 1)
        guard interval > 0 else { return Array(repeating: input[0], count: count) }
        var result = [pts[0]]
        var carried: CGFloat = 0
        var i = 1
        while i < pts.count {
            let d = distance(pts[i - 1], pts[i])
            if carried + d >= interval, d > 0 {
                let t = (interval - carried) / d
                let q = CGPoint(x: pts[i - 1].x + t * (pts[i].x - pts[i - 1].x),
                                y: pts[i - 1].y + t * (pts[i].y - pts[i - 1].y))
                result.append(q)
                pts.insert(q, at: i)   // measure on from the new point
                carried = 0
            } else {
                carried += d
            }
            i += 1
        }
        while result.count < count { result.append(pts[pts.count - 1]) }
        return Array(result.prefix(count))
    }

    private static func removingDuplicates(_ p: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for q in p where out.last.map({ distance($0, q) >= 0.5 }) ?? true { out.append(q) }
        return out
    }

    private static func pathLength(_ p: [CGPoint]) -> CGFloat {
        zip(p, p.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func diagonal(of p: [CGPoint]) -> CGFloat {
        let xs = p.map(\.x), ys = p.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return hypot(maxX - minX, maxY - minY)
    }

    private static func average(_ p: [CGPoint]) -> CGPoint {
        let n = CGFloat(p.count)
        return CGPoint(x: p.reduce(0) { $0 + $1.x } / n, y: p.reduce(0) { $0 + $1.y } / n)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func distanceFromLine(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let len = distance(a, b)
        guard len > 0 else { return distance(p, a) }
        return abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / len
    }

    /// Angle between two directions, 0 (same way) to π (opposite).
    private static func angleBetween(_ u: CGPoint, _ v: CGPoint) -> CGFloat {
        let lu = hypot(u.x, u.y), lv = hypot(v.x, v.y)
        guard lu > 0, lv > 0 else { return 0 }
        return acos(max(-1, min(1, (u.x * v.x + u.y * v.y) / (lu * lv))))
    }

    private static func rotated(_ p: CGPoint, by angle: CGFloat) -> CGPoint {
        CGPoint(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
