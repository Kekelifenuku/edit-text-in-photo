import CoreGraphics

/// Builds a tight "ink" mask for a detected text region by Otsu-thresholding the crop's luminance
/// and picking whichever side of the threshold is farther from the crop's own border color (a
/// proxy for the surrounding background) as the ink class. No font/glyph knowledge is needed for
/// this step — it just separates "text-colored pixels" from "everything else" inside the region's
/// bounding box.
enum MaskGenerator {

    struct Mask {
        /// Row-major, top-left origin, values are 0 or 255.
        let alpha: [UInt8]
        let size: CGSize
    }

    struct Result {
        let mask: Mask
        let dilatedMask: Mask
        /// Top-left-origin pixel rect (the region's plain bounding box) this mask covers.
        let cropRect: CGRect
        let inkColor: (r: UInt8, g: UInt8, b: UInt8)
    }

    nonisolated static func generate(for region: TextRegion, in image: CGImage) -> Result? {
        let cropRect = region.boundingBox.integral
        guard let crop = image.cropped(to: cropRect),
              let (width, height, buffer) = BitmapContext.pixelBuffer(of: crop) else { return nil }

        let pixelCount = width * height
        guard pixelCount > 0 else { return nil }

        var luminance = [UInt8](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            let r = Double(buffer[i * 4])
            let g = Double(buffer[i * 4 + 1])
            let b = Double(buffer[i * 4 + 2])
            luminance[i] = UInt8(min(255, max(0, 0.299 * r + 0.587 * g + 0.114 * b)))
        }

        var borderSum = 0.0
        var borderCount = 0.0
        for y in 0..<height {
            for x in 0..<width where x < 2 || x >= width - 2 || y < 2 || y >= height - 2 {
                borderSum += Double(luminance[y * width + x])
                borderCount += 1
            }
        }
        let backgroundLuminance = borderCount > 0 ? borderSum / borderCount : 128

        let threshold = otsuThreshold(luminance)

        var sumAbove = 0.0, countAbove = 0.0
        var sumBelow = 0.0, countBelow = 0.0
        for l in luminance {
            if l > threshold {
                sumAbove += Double(l); countAbove += 1
            } else {
                sumBelow += Double(l); countBelow += 1
            }
        }
        let meanAbove = countAbove > 0 ? sumAbove / countAbove : 255
        let meanBelow = countBelow > 0 ? sumBelow / countBelow : 0
        let aboveIsInk = abs(meanAbove - backgroundLuminance) > abs(meanBelow - backgroundLuminance)

        var ink = [UInt8](repeating: 0, count: pixelCount)
        var rSum = 0, gSum = 0, bSum = 0, inkCount = 0
        for i in 0..<pixelCount {
            let isInk = luminance[i] > threshold ? aboveIsInk : !aboveIsInk
            ink[i] = isInk ? 255 : 0
            if isInk {
                rSum += Int(buffer[i * 4]); gSum += Int(buffer[i * 4 + 1]); bSum += Int(buffer[i * 4 + 2])
                inkCount += 1
            }
        }
        let inkColor: (UInt8, UInt8, UInt8) = inkCount > 0
            ? (UInt8(rSum / inkCount), UInt8(gSum / inkCount), UInt8(bSum / inkCount))
            : (0, 0, 0)

        let tight = Mask(alpha: ink, size: CGSize(width: width, height: height))
        let dilated = Mask(alpha: dilate(ink, width: width, height: height, radius: 2), size: tight.size)

        return Result(mask: tight, dilatedMask: dilated, cropRect: cropRect, inkColor: inkColor)
    }

    nonisolated private static func otsuThreshold(_ values: [UInt8]) -> UInt8 {
        var histogram = [Int](repeating: 0, count: 256)
        for v in values { histogram[Int(v)] += 1 }
        let total = values.count
        var sum = 0.0
        for t in 0..<256 { sum += Double(t) * Double(histogram[t]) }

        var sumB = 0.0, weightBackground = 0.0, maxVariance = 0.0, threshold = 128
        for t in 0..<256 {
            weightBackground += Double(histogram[t])
            guard weightBackground > 0 else { continue }
            let weightForeground = Double(total) - weightBackground
            guard weightForeground > 0 else { break }
            sumB += Double(t) * Double(histogram[t])
            let meanBackground = sumB / weightBackground
            let meanForeground = (sum - sumB) / weightForeground
            let variance = weightBackground * weightForeground * (meanBackground - meanForeground) * (meanBackground - meanForeground)
            if variance > maxVariance {
                maxVariance = variance
                threshold = t
            }
        }
        return UInt8(threshold)
    }

    nonisolated private static func dilate(_ mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = mask
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] == 0 {
                var found = false
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < width, ny >= 0, ny < height, mask[ny * width + nx] == 255 {
                            found = true
                            break
                        }
                    }
                    if found { break }
                }
                if found { result[y * width + x] = 255 }
            }
        }
        return result
    }
}
