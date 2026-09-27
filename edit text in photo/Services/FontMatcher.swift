import CoreGraphics
import CoreText
import UIKit

struct FontCandidate {
    let postScriptName: String
    let displayName: String
}

/// Matches a detected glyph mask against a curated set of iOS fonts by rendering each candidate
/// and comparing rasterized glyph coverage — no LLM guessing involved.
enum FontMatcher {

    struct Match {
        let postScriptName: String
        let pointSize: CGFloat
        let tracking: CGFloat
        let score: Double
    }

    nonisolated static func bestMatch(for text: String, glyphMask: MaskGenerator.Mask, estimatedSize: CGFloat) -> Match {
        guard !text.isEmpty, glyphMask.size.width >= 1, glyphMask.size.height >= 1 else {
            return Match(postScriptName: "HelveticaNeue", pointSize: estimatedSize, tracking: 0, score: 0)
        }

        var best: Match?
        let minSize = max(6, estimatedSize - 4)
        let maxSize = estimatedSize + 4
        var size = minSize
        while size <= maxSize {
            for candidate in candidates {
                guard let rasterized = rasterize(text: text, postScriptName: candidate.postScriptName, size: size, canvasSize: glyphMask.size) else {
                    continue
                }
                let score = similarity(rasterized, glyphMask.alpha)
                if best == nil || score > best!.score {
                    let tracking = solveTracking(text: text, postScriptName: candidate.postScriptName, size: size, targetWidth: glyphMask.size.width)
                    best = Match(postScriptName: candidate.postScriptName, pointSize: size, tracking: tracking, score: score)
                }
            }
            size += 1
        }
        return best ?? Match(postScriptName: "HelveticaNeue", pointSize: estimatedSize, tracking: 0, score: 0)
    }

    nonisolated private static func rasterize(text: String, postScriptName: String, size: CGFloat, canvasSize: CGSize) -> [UInt8]? {
        let width = max(1, Int(canvasSize.width))
        let height = max(1, Int(canvasSize.height))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // Top-left-oriented so this buffer's row order matches MaskGenerator's ink mask, which it
        // gets compared against pixel-for-pixel.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        let attrString = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.white.cgColor
        ])
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        let originX = (CGFloat(width) - bounds.width) / 2 - bounds.origin.x
        let originY = (CGFloat(height) - bounds.height) / 2 - bounds.origin.y

        // CoreText needs a native y-up space to draw non-mirrored glyphs; counter-flip locally,
        // just for this draw call (see TextRenderer.drawUprightText for the same pattern).
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)
        context.restoreGState()

        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        return Array(UnsafeBufferPointer(start: buffer, count: width * height))
    }

    /// Blend of IoU (on thresholded coverage) and normalized cross-correlation (on soft alpha).
    nonisolated private static func similarity(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let threshold: UInt8 = 128
        var intersection = 0, union = 0
        var sumA = 0.0, sumB = 0.0, sumAB = 0.0, sumA2 = 0.0, sumB2 = 0.0
        let n = Double(a.count)

        for i in 0..<a.count {
            let ba = a[i] > threshold
            let bb = b[i] > threshold
            if ba || bb { union += 1 }
            if ba && bb { intersection += 1 }
            let da = Double(a[i]) / 255.0
            let db = Double(b[i]) / 255.0
            sumA += da; sumB += db; sumAB += da * db; sumA2 += da * da; sumB2 += db * db
        }

        let iou = union > 0 ? Double(intersection) / Double(union) : 0
        let meanA = sumA / n, meanB = sumB / n
        let numerator = sumAB - n * meanA * meanB
        let denominator = sqrt(max(0, (sumA2 - n * meanA * meanA) * (sumB2 - n * meanB * meanB)))
        let ncc = denominator > 0 ? numerator / denominator : 0
        return 0.6 * iou + 0.4 * max(0, ncc)
    }

    nonisolated private static func solveTracking(text: String, postScriptName: String, size: CGFloat, targetWidth: CGFloat) -> CGFloat {
        guard text.count > 1 else { return 0 }
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        let attrString = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attrString)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let extra = targetWidth - naturalWidth
        let gaps = CGFloat(text.count - 1)
        guard gaps > 0 else { return 0 }
        return max(-5, min(20, extra / gaps))
    }

    nonisolated static let candidates: [FontCandidate] = buildCandidates()

    nonisolated private static func buildCandidates() -> [FontCandidate] {
        var list: [FontCandidate] = []

        // `UIFont.systemFont(ofSize:weight:).fontName` returns a private, dot-prefixed name
        // (e.g. ".SFUI-Regular") that `CTFontCreateWithName` cannot resolve — it silently falls
        // back to Times New Roman instead (logged as a CoreText warning), which would otherwise
        // poison font-matching scores. The San Francisco family is also reachable by these public,
        // directly-nameable PostScript names, which resolve correctly.
        let sfNames: [(String, String)] = [
            ("SFProText-Regular", "SF Pro Text"), ("SFProText-Medium", "SF Pro Text Medium"),
            ("SFProText-Semibold", "SF Pro Text Semibold"), ("SFProText-Bold", "SF Pro Text Bold"),
            ("SFProDisplay-Regular", "SF Pro Display"), ("SFProDisplay-Medium", "SF Pro Display Medium"),
            ("SFProDisplay-Semibold", "SF Pro Display Semibold"), ("SFProDisplay-Bold", "SF Pro Display Bold"),
            ("SFProDisplay-Black", "SF Pro Display Black"), ("SFProDisplay-Light", "SF Pro Display Light"),
            ("SFProRounded-Regular", "SF Pro Rounded"), ("SFProRounded-Medium", "SF Pro Rounded Medium"),
            ("SFProRounded-Semibold", "SF Pro Rounded Semibold"), ("SFProRounded-Bold", "SF Pro Rounded Bold")
        ]
        for (postScriptName, displayName) in sfNames {
            list.append(FontCandidate(postScriptName: postScriptName, displayName: displayName))
        }

        let staticNames: [(String, String)] = [
            ("HelveticaNeue", "Helvetica Neue"),
            ("HelveticaNeue-Medium", "Helvetica Neue Medium"),
            ("HelveticaNeue-Bold", "Helvetica Neue Bold"),
            ("HelveticaNeue-Italic", "Helvetica Neue Italic"),
            ("ArialMT", "Arial"),
            ("Arial-BoldMT", "Arial Bold"),
            ("Arial-ItalicMT", "Arial Italic"),
            ("TimesNewRomanPSMT", "Times New Roman"),
            ("TimesNewRomanPS-BoldMT", "Times New Roman Bold"),
            ("TimesNewRomanPS-ItalicMT", "Times New Roman Italic"),
            ("Georgia", "Georgia"),
            ("Georgia-Bold", "Georgia Bold"),
            ("Georgia-Italic", "Georgia Italic"),
            ("CourierNewPSMT", "Courier New"),
            ("CourierNewPS-BoldMT", "Courier New Bold"),
            ("Verdana", "Verdana"),
            ("Verdana-Bold", "Verdana Bold"),
            ("Futura-Medium", "Futura Medium"),
            ("Futura-CondensedExtraBold", "Futura Bold"),
            ("AvenirNext-Regular", "Avenir Next"),
            ("AvenirNext-Medium", "Avenir Next Medium"),
            ("AvenirNext-DemiBold", "Avenir Next Demi Bold"),
            ("AvenirNext-Bold", "Avenir Next Bold"),
            ("Baskerville", "Baskerville"),
            ("Menlo-Regular", "Menlo"),
            ("Noteworthy-Bold", "Noteworthy"),
            ("ChalkboardSE-Regular", "Chalkboard SE")
        ]
        for (postScriptName, displayName) in staticNames {
            list.append(FontCandidate(postScriptName: postScriptName, displayName: displayName))
        }

        // Keep only fonts actually installed/resolvable on this system.
        return list.filter { UIFont(name: $0.postScriptName, size: 12) != nil }
    }
}
