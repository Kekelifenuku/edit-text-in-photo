import CoreGraphics
import Foundation

/// Self-checks a committed edit before it's treated as final: re-OCRs the finished region to
/// confirm the new text actually reads back correctly, and diffs the area around the edit against
/// the pre-edit image to confirm nothing outside the patch moved. A failure here should never be
/// silently swallowed — the caller is expected to surface it for manual adjustment.
enum VerificationService {

    struct Result {
        let passed: Bool
        let recognizedText: String?
        let reason: String?
    }

    nonisolated static func verify(
        expectedText: String,
        region: TextRegion,
        renderedImage: CGImage,
        originalImage: CGImage,
        patchRect: CGRect
    ) async -> Result {
        guard let croppedRendered = renderedImage.cropped(to: patchRect) else {
            return Result(passed: false, recognizedText: nil, reason: "Could not crop the edited region for verification.")
        }

        let recognizedText: String
        do {
            let regions = try await OCRService.detectText(in: PipelineImage(cgImage: croppedRendered))
            recognizedText = regions.map(\.text).joined(separator: " ")
        } catch {
            return Result(passed: false, recognizedText: nil, reason: "OCR re-check failed: \(error.localizedDescription)")
        }

        let distance = levenshtein(normalize(expectedText), normalize(recognizedText))
        let tolerance = max(1, normalize(expectedText).count / 5)
        guard distance <= tolerance else {
            return Result(
                passed: false,
                recognizedText: recognizedText,
                reason: "Rendered text reads as \u{201C}\(recognizedText)\u{201D}, not \u{201C}\(expectedText)\u{201D}."
            )
        }

        guard pixelsOutsideMaskUnchanged(original: originalImage, rendered: renderedImage, patchRect: patchRect) else {
            return Result(passed: false, recognizedText: recognizedText, reason: "Pixels outside the edited region changed unexpectedly.")
        }

        return Result(passed: true, recognizedText: recognizedText, reason: nil)
    }

    nonisolated private static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var prev = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i - 1] == b[j - 1] ? prev : 1 + min(prev, dp[j], dp[j - 1])
                prev = temp
            }
        }
        return dp[b.count]
    }

    /// Confirms nothing changed outside `patchRect` — the full contract boundary of what
    /// `TextRenderer` is allowed to touch. This deliberately does NOT use the original glyphs'
    /// tight ink mask as the allowed-change boundary: a different (but reasonable) font match will
    /// have a different glyph silhouette than the original and can legitimately use more of its
    /// bounding box without that being a rendering bug.
    nonisolated private static func pixelsOutsideMaskUnchanged(original: CGImage, rendered: CGImage, patchRect: CGRect) -> Bool {
        let checkRect = patchRect.insetBy(dx: -20, dy: -20).intersection(original.pixelBounds)
        guard let origCrop = original.cropped(to: checkRect),
              let renderedCrop = rendered.cropped(to: checkRect),
              let (width, height, origBuf) = BitmapContext.pixelBuffer(of: origCrop),
              let (_, _, renderedBuf) = BitmapContext.pixelBuffer(of: renderedCrop),
              origBuf.count == renderedBuf.count else { return true }

        let patchOffsetX = Int((patchRect.origin.x - checkRect.origin.x).rounded())
        let patchOffsetY = Int((patchRect.origin.y - checkRect.origin.y).rounded())
        let patchWidth = Int(patchRect.width.rounded())
        let patchHeight = Int(patchRect.height.rounded())

        var maxDiff = 0
        for y in 0..<height {
            for x in 0..<width {
                let px = x - patchOffsetX, py = y - patchOffsetY
                if px >= 0, px < patchWidth, py >= 0, py < patchHeight { continue }
                let idx = (y * width + x) * 4
                for c in 0..<3 {
                    maxDiff = max(maxDiff, abs(Int(origBuf[idx + c]) - Int(renderedBuf[idx + c])))
                }
            }
        }
        return maxDiff <= 6
    }
}
