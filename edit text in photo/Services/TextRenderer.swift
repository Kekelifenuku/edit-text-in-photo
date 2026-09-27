import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import UIKit

/// Deterministically draws replacement text with CoreText, then warps it onto the original quad
/// (rotation and/or true keystone perspective) with `CIPerspectiveTransform`, composited over the
/// region's reconstructed background patch. No generative model draws any pixels here.
enum TextRenderer {

    nonisolated private static let ciContext = CIContext()

    nonisolated static func render(text: String, style: TextStyle, region: TextRegion, over patch: BackgroundPatch) -> CGImage? {
        let width = Int(patch.patchRect.width)
        let height = Int(patch.patchRect.height)
        guard width > 0, height > 0, !text.isEmpty else { return nil }

        let localCorners = [region.topLeft, region.topRight, region.bottomRight, region.bottomLeft].map {
            CGPoint(x: $0.x - patch.patchRect.origin.x, y: $0.y - patch.patchRect.origin.y)
        }

        let textWidth = max(1, Int(region.width.rounded(.up)))
        let textHeight = max(1, Int((region.lineHeight * 1.4).rounded(.up)))
        guard let textBitmap = drawUprightText(text: text, style: style, width: textWidth, height: textHeight) else { return nil }

        let backgroundCI = CIImage(cgImage: patch.patch)
        let textCI = CIImage(cgImage: textBitmap)

        // CIPerspectiveTransform's points are in the *input image's* coordinate space, which Core
        // Image treats as bottom-left-origin — flip our top-left-origin patch-local corners to match.
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: CGFloat(height) - p.y) }

        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = textCI
        filter.topLeft = flip(localCorners[0])
        filter.topRight = flip(localCorners[1])
        filter.bottomRight = flip(localCorners[2])
        filter.bottomLeft = flip(localCorners[3])

        guard let warped = filter.outputImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let composited = warped.cropped(to: bounds).composited(over: backgroundCI)

        return ciContext.createCGImage(composited, from: bounds)
    }

    nonisolated private static func drawUprightText(text: String, style: TextStyle, width: Int, height: Int) -> CGImage? {
        // Top-left-oriented so the resulting CGImage's row 0 is its top row, matching every other
        // image in the pipeline.
        guard let context = BitmapContext.makeTopLeftOriented(width: width, height: height) else { return nil }

        let font = CTFontCreateWithName(style.fontName as CFString, style.pointSize, nil)
        let c = style.colorComponents
        let color = UIColor(
            red: c.count > 0 ? c[0] : 0,
            green: c.count > 1 ? c[1] : 0,
            blue: c.count > 2 ? c[2] : 0,
            alpha: c.count > 3 ? c[3] : 1
        )

        let attrString = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color.cgColor,
            .kern: style.tracking
        ])
        let line = CTLineCreateWithAttributedString(attrString)

        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baselineY = (CGFloat(height) - (ascent + descent)) / 2 + descent

        // CoreText draws glyph outlines assuming a native y-up space; in a top-left-oriented
        // context that would render every glyph mirrored vertically. Counter-flip locally, just
        // for this draw call, so glyphs come out upright while the buffer stays top-left-oriented.
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()

        return context.makeImage()
    }
}
