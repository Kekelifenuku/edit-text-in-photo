import CoreGraphics

enum Geometry {

    /// Even-odd point-in-polygon test. Works for the roughly-convex quads Vision returns for a text line,
    /// including rotated and keystoned ones.
    nonisolated static func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    nonisolated static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension CGPoint {
    nonisolated func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
