import CoreGraphics
import Foundation

/// A block of text detected in a photo, with enough geometry to survive rotation and perspective
/// (a plain rect + string would lose that), plus the OCR confidence used to decide whether the
/// region needs a second, upscaled OCR pass.
struct TextRegion: Identifiable, Hashable {
    let id: UUID
    var text: String
    var confidence: Float
    var isHidden: Bool
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var characterBoxes: [CGRect]

    nonisolated init(
        id: UUID = UUID(),
        text: String,
        confidence: Float,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        characterBoxes: [CGRect] = [],
        isHidden: Bool = false
    ) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.isHidden = isHidden
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.characterBoxes = characterBoxes
    }

    nonisolated var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    nonisolated var boundingBox: CGRect { Geometry.boundingBox(of: corners) }

    /// Angle of the top edge, radians, image pixel space (y grows downward).
    nonisolated var rotationAngle: CGFloat {
        atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
    }

    /// Average of the top and bottom edge lengths.
    nonisolated var width: CGFloat {
        (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
    }

    /// Average of the left and right edge lengths.
    nonisolated var lineHeight: CGFloat {
        (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
    }

    nonisolated func hitTest(_ point: CGPoint) -> Bool {
        Geometry.pointInPolygon(point, polygon: corners)
    }
}
