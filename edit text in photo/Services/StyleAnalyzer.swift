import CoreGraphics

/// Combines geometry-derived size/rotation, `FontMatcher`'s font pick, and directly-sampled ink
/// color into a single `TextStyle` for a region.
enum StyleAnalyzer {

    nonisolated static func analyze(region: TextRegion, maskResult: MaskGenerator.Result) -> TextStyle {
        let capHeightRatio: CGFloat = 0.72
        let estimatedSize = max(8, region.lineHeight * capHeightRatio)

        let match = FontMatcher.bestMatch(for: region.text, glyphMask: maskResult.mask, estimatedSize: estimatedSize)

        let color = maskResult.inkColor
        let colorComponents: [CGFloat] = [
            CGFloat(color.r) / 255.0,
            CGFloat(color.g) / 255.0,
            CGFloat(color.b) / 255.0,
            1.0
        ]

        return TextStyle(
            fontName: match.postScriptName,
            pointSize: match.pointSize,
            tracking: match.tracking,
            lineSpacing: 0,
            alignment: .left,
            colorComponents: colorComponents,
            rotationAngle: region.rotationAngle
        )
    }
}
