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
        // Render at the detected region's actual height. Extra vertical padding here is warped
        // back into the same quad below, which compresses the letters and makes them look short.
        let textHeight = max(1, Int(region.lineHeight.rounded(.up)))
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

        var font = CTFontCreateWithName(style.fontName as CFString, style.pointSize, nil)
        var traits: CTFontSymbolicTraits = []
        if style.isBold { traits.insert(.traitBold) }
        if style.isItalic { traits.insert(.traitItalic) }
        if !traits.isEmpty, let styledFont = CTFontCreateCopyWithSymbolicTraits(font, style.pointSize, nil, traits, traits) {
            font = styledFont
        }
        let c = style.colorComponents
        let color = UIColor(
            red: c.count > 0 ? c[0] : 0,
            green: c.count > 1 ? c[1] : 0,
            blue: c.count > 2 ? c[2] : 0,
            alpha: c.count > 3 ? c[3] : 1
        )

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color.cgColor,
            .kern: style.tracking,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle(
                alignment: style.alignment,
                lineSpacing: style.lineSpacing
            )
        ]
        if style.outlineWidth > 0 {
            let outlineColor: UIColor
            if let components = style.outlineColorComponents {
                outlineColor = UIColor(
                    red: components.count > 0 ? components[0] : 0,
                    green: components.count > 1 ? components[1] : 0,
                    blue: components.count > 2 ? components[2] : 0,
                    alpha: components.count > 3 ? components[3] : 1
                )
            } else {
                let luminance = 0.2126 * Double(c.count > 0 ? c[0] : 0)
                    + 0.7152 * Double(c.count > 1 ? c[1] : 0)
                    + 0.0722 * Double(c.count > 2 ? c[2] : 0)
                outlineColor = (luminance > 0.5 ? UIColor.black : UIColor.white)
                    .withAlphaComponent(c.count > 3 ? c[3] : 1)
            }
            // CoreText expresses stroke width as a percentage of font size; negative values keep
            // the glyph filled while drawing its outline.
            let strokePercent = min(40, style.outlineWidth / max(style.pointSize, 1) * 100)
            attributes[.strokeWidth] = -strokePercent
            attributes[.strokeColor] = outlineColor.cgColor
        }
        if style.isUnderlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if style.isStrikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attrString)
        // Lay out against the uncompressed width, then scale only the glyphs horizontally. This
        // keeps replacement text at the matched point size instead of making taller letters
        // smaller just because the new wording is longer.
        let horizontalScale = max(0.01, min(1, style.horizontalScale))
        let layoutWidth = CGFloat(width) / horizontalScale
        let unconstrainedSize = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: layoutWidth, height: .greatestFiniteMagnitude),
            nil
        )
        let frameHeight = min(CGFloat(height), max(1, ceil(unconstrainedSize.height)))
        let verticalInset = max(0, (CGFloat(height) - frameHeight) / 2)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: verticalInset, width: layoutWidth, height: frameHeight))
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        if style.hasBackground {
            let background = style.backgroundColorComponents
            let fillColor = UIColor(
                red: background.count > 0 ? background[0] : 0,
                green: background.count > 1 ? background[1] : 0,
                blue: background.count > 2 ? background[2] : 0,
                alpha: background.count > 3 ? background[3] : 0.85
            )
            let backgroundRect = CGRect(x: 0, y: 0, width: width, height: height)
            let cornerRadius = min(style.backgroundCornerRadius, min(backgroundRect.width, backgroundRect.height) / 2)
            context.setFillColor(fillColor.cgColor)
            context.addPath(CGPath(
                roundedRect: backgroundRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            ))
            context.fillPath()
        }

        // CoreText draws glyph outlines assuming a native y-up space; in a top-left-oriented
        // context that would render every glyph mirrored vertically. Counter-flip locally, just
        // for this draw call, so glyphs come out upright while the buffer stays top-left-oriented.
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: horizontalScale, y: 1)
        if style.shadowBlur > 0 {
            let shadow = style.shadowColorComponents
            context.setShadow(
                offset: CGSize(
                    width: style.shadowBlur * style.shadowOffsetXRatio,
                    height: style.shadowBlur * style.shadowOffsetYRatio
                ),
                blur: style.shadowBlur,
                color: UIColor(
                    red: shadow.count > 0 ? shadow[0] : 0,
                    green: shadow.count > 1 ? shadow[1] : 0,
                    blue: shadow.count > 2 ? shadow[2] : 0,
                    alpha: shadow.count > 3 ? shadow[3] : 0.55
                ).cgColor
            )
        }
        CTFrameDraw(frame, context)
        context.restoreGState()

        return context.makeImage()
    }

    nonisolated private static func paragraphStyle(
        alignment: TextHorizontalAlignment,
        lineSpacing: CGFloat
    ) -> CTParagraphStyle {
        var textAlignment: CTTextAlignment
        switch alignment {
        case .left: textAlignment = .left
        case .center: textAlignment = .center
        case .right: textAlignment = .right
        }
        var spacing = lineSpacing
        var lineBreakMode = CTLineBreakMode.byWordWrapping

        return withUnsafePointer(to: &textAlignment) { alignmentPointer in
            withUnsafePointer(to: &spacing) { spacingPointer in
                withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                    let settings = [
                        CTParagraphStyleSetting(
                            spec: .alignment,
                            valueSize: MemoryLayout<CTTextAlignment>.size,
                            value: UnsafeRawPointer(alignmentPointer)
                        ),
                        CTParagraphStyleSetting(
                            spec: .lineSpacingAdjustment,
                            valueSize: MemoryLayout<CGFloat>.size,
                            value: UnsafeRawPointer(spacingPointer)
                        ),
                        CTParagraphStyleSetting(
                            spec: .lineBreakMode,
                            valueSize: MemoryLayout<CTLineBreakMode>.size,
                            value: UnsafeRawPointer(lineBreakPointer)
                        )
                    ]
                    return settings.withUnsafeBufferPointer { buffer in
                        CTParagraphStyleCreate(buffer.baseAddress, buffer.count)
                    }
                }
            }
        }
    }
}
