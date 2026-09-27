import CoreGraphics

enum TextHorizontalAlignment: String, CaseIterable {
    case left, center, right
}

/// The recovered (or manually overridden) visual style for a piece of replacement text.
struct TextStyle: Equatable {
    var fontName: String
    var pointSize: CGFloat
    var tracking: CGFloat
    var lineSpacing: CGFloat
    var alignment: TextHorizontalAlignment
    /// sRGB [r, g, b, a] in 0...1, stored as components rather than `CGColor` so the style stays
    /// trivially `Equatable`/`Sendable`.
    var colorComponents: [CGFloat]
    /// Radians, image pixel space, copied from the source region's geometry.
    var rotationAngle: CGFloat

    static let `default` = TextStyle(
        fontName: "HelveticaNeue",
        pointSize: 24,
        tracking: 0,
        lineSpacing: 0,
        alignment: .left,
        colorComponents: [0, 0, 0, 1],
        rotationAngle: 0
    )
}
