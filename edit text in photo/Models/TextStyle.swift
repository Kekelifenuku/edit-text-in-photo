import CoreGraphics

enum TextHorizontalAlignment: String, CaseIterable {
    case left, center, right
}

/// The recovered (or manually overridden) visual style for a piece of replacement text.
struct TextStyle: Equatable {
    var fontName: String
    var pointSize: CGFloat
    /// Horizontal glyph scale used to fit longer replacement text without shrinking its height.
    var horizontalScale: CGFloat = 1
    var tracking: CGFloat
    var lineSpacing: CGFloat
    var alignment: TextHorizontalAlignment
    /// sRGB [r, g, b, a] in 0...1, stored as components rather than `CGColor` so the style stays
    /// trivially `Equatable`/`Sendable`.
    var colorComponents: [CGFloat]
    /// Radians, image pixel space, copied from the source region's geometry.
    var rotationAngle: CGFloat
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderlined: Bool = false
    var isStrikethrough: Bool = false
    var outlineWidth: CGFloat = 0
    /// `nil` keeps the automatic color selected for contrast with the text.
    var outlineColorComponents: [CGFloat]? = nil
    var shadowBlur: CGFloat = 0
    var shadowColorComponents: [CGFloat] = [0, 0, 0, 0.55]
    /// Shadow direction as a fraction of the blur radius; defaults to the existing subtle drop.
    var shadowOffsetXRatio: CGFloat = 0
    var shadowOffsetYRatio: CGFloat = 0.3
    var hasBackground: Bool = false
    /// sRGB [r, g, b, a] components for an optional label drawn behind the text.
    var backgroundColorComponents: [CGFloat] = [0, 0, 0, 0.85]
    var backgroundCornerRadius: CGFloat = 0

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
