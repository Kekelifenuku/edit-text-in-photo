import CoreGraphics

/// Reconstructs the background behind a text region's glyph mask using classic heuristics (no ML
/// model): solid fill, a fitted linear gradient, or a shifted-patch clone for busier backgrounds,
/// with a feathered edge so the seam isn't hard. Every operation stays inside the dilated mask, so
/// pixels outside it are provably untouched (verified later by `VerificationService`).
enum BackgroundReconstructor {

    private struct Sample {
        let x: Int
        let y: Int
        let r: Double
        let g: Double
        let b: Double
    }

    nonisolated static func reconstruct(region: TextRegion, maskResult: MaskGenerator.Result, in image: CGImage) -> BackgroundPatch? {
        let cropRect = maskResult.cropRect
        let maskWidth = Int(maskResult.dilatedMask.size.width)
        let maskHeight = Int(maskResult.dilatedMask.size.height)
        guard maskWidth > 0, maskHeight > 0 else { return nil }

        let padding = max(8, maskResult.mask.size.height)
        let sourceRect = cropRect.insetBy(dx: -padding, dy: -padding).intersection(image.pixelBounds)
        guard let sourceCrop = image.cropped(to: sourceRect),
              let (srcWidth, srcHeight, srcBuffer) = BitmapContext.pixelBuffer(of: sourceCrop) else { return nil }

        let offsetX = Int((cropRect.origin.x - sourceRect.origin.x).rounded())
        let offsetY = Int((cropRect.origin.y - sourceRect.origin.y).rounded())
        let mask = maskResult.dilatedMask.alpha

        let ringSamples = collectRing(mask: mask, maskWidth: maskWidth, maskHeight: maskHeight,
                                       source: srcBuffer, srcWidth: srcWidth, srcHeight: srcHeight,
                                       offsetX: offsetX, offsetY: offsetY)
        guard !ringSamples.isEmpty else { return nil }

        let method = classify(ringSamples)

        var patchBuffer = [UInt8](repeating: 0, count: maskWidth * maskHeight * 4)
        for my in 0..<maskHeight {
            for mx in 0..<maskWidth {
                let sx = mx + offsetX, sy = my + offsetY
                let di = (my * maskWidth + mx) * 4
                if sx >= 0, sx < srcWidth, sy >= 0, sy < srcHeight {
                    let si = (sy * srcWidth + sx) * 4
                    patchBuffer[di] = srcBuffer[si]
                    patchBuffer[di + 1] = srcBuffer[si + 1]
                    patchBuffer[di + 2] = srcBuffer[si + 2]
                }
                patchBuffer[di + 3] = 255
            }
        }

        switch method {
        case .solid:
            let color = averageColor(ringSamples)
            for my in 0..<maskHeight {
                for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 255 {
                    let di = (my * maskWidth + mx) * 4
                    patchBuffer[di] = clampByte(color.0)
                    patchBuffer[di + 1] = clampByte(color.1)
                    patchBuffer[di + 2] = clampByte(color.2)
                }
            }
        case .gradient:
            let planes = fitPlanes(ringSamples)
            for my in 0..<maskHeight {
                for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 255 {
                    let di = (my * maskWidth + mx) * 4
                    let x = Double(mx), y = Double(my)
                    patchBuffer[di] = clampByte(planes.r.0 * x + planes.r.1 * y + planes.r.2)
                    patchBuffer[di + 1] = clampByte(planes.g.0 * x + planes.g.1 * y + planes.g.2)
                    patchBuffer[di + 2] = clampByte(planes.b.0 * x + planes.b.1 * y + planes.b.2)
                }
            }
        case .texture:
            cloneFill(into: &patchBuffer, maskWidth: maskWidth, maskHeight: maskHeight, mask: mask,
                      source: srcBuffer, srcWidth: srcWidth, srcHeight: srcHeight, offsetX: offsetX, offsetY: offsetY)
        }

        feather(&patchBuffer, maskWidth: maskWidth, maskHeight: maskHeight, mask: mask,
                original: srcBuffer, srcWidth: srcWidth, srcHeight: srcHeight, offsetX: offsetX, offsetY: offsetY)

        guard let patchImage = makeRGBAImage(from: patchBuffer, width: maskWidth, height: maskHeight),
              let maskImage = makeGrayImage(from: mask, width: maskWidth, height: maskHeight) else { return nil }

        return BackgroundPatch(regionID: region.id, method: method, patch: patchImage, patchRect: cropRect, mask: maskImage)
    }

    // MARK: - Ring sampling & classification

    nonisolated private static func collectRing(
        mask: [UInt8], maskWidth: Int, maskHeight: Int,
        source: [UInt8], srcWidth: Int, srcHeight: Int,
        offsetX: Int, offsetY: Int
    ) -> [Sample] {
        let ringRadius = 4
        var samples: [Sample] = []
        for my in 0..<maskHeight {
            for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 0 {
                var nearMask = false
                outer: for dy in -ringRadius...ringRadius {
                    for dx in -ringRadius...ringRadius {
                        let nx = mx + dx, ny = my + dy
                        if nx >= 0, nx < maskWidth, ny >= 0, ny < maskHeight, mask[ny * maskWidth + nx] == 255 {
                            nearMask = true
                            break outer
                        }
                    }
                }
                guard nearMask else { continue }
                let sx = mx + offsetX, sy = my + offsetY
                guard sx >= 0, sx < srcWidth, sy >= 0, sy < srcHeight else { continue }
                let idx = (sy * srcWidth + sx) * 4
                samples.append(Sample(x: mx, y: my, r: Double(source[idx]), g: Double(source[idx + 1]), b: Double(source[idx + 2])))
            }
        }
        return samples
    }

    nonisolated private static func classify(_ samples: [Sample]) -> ReconstructionMethod {
        let n = Double(samples.count)
        let meanR = samples.reduce(0.0) { $0 + $1.r } / n
        let meanG = samples.reduce(0.0) { $0 + $1.g } / n
        let meanB = samples.reduce(0.0) { $0 + $1.b } / n
        let variance = samples.reduce(0.0) { acc, s in
            acc + pow(s.r - meanR, 2) + pow(s.g - meanG, 2) + pow(s.b - meanB, 2)
        } / (n * 3)
        let stddev = sqrt(variance)
        if stddev < 6 { return .solid }

        let planes = fitPlanes(samples)
        let mse = samples.reduce(0.0) { acc, s in
            let x = Double(s.x), y = Double(s.y)
            let er = s.r - (planes.r.0 * x + planes.r.1 * y + planes.r.2)
            let eg = s.g - (planes.g.0 * x + planes.g.1 * y + planes.g.2)
            let eb = s.b - (planes.b.0 * x + planes.b.1 * y + planes.b.2)
            return acc + er * er + eg * eg + eb * eb
        } / (n * 3)
        return sqrt(mse) < 8 ? .gradient : .texture
    }

    nonisolated private static func averageColor(_ samples: [Sample]) -> (Double, Double, Double) {
        let n = Double(samples.count)
        return (
            samples.reduce(0.0) { $0 + $1.r } / n,
            samples.reduce(0.0) { $0 + $1.g } / n,
            samples.reduce(0.0) { $0 + $1.b } / n
        )
    }

    // MARK: - Gradient plane fit

    nonisolated private static func fitPlanes(_ samples: [Sample]) -> (r: (Double, Double, Double), g: (Double, Double, Double), b: (Double, Double, Double)) {
        var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, n = 0.0
        var srx = 0.0, sry = 0.0, sr = 0.0
        var sgx = 0.0, sgy = 0.0, sg = 0.0
        var sbx = 0.0, sby = 0.0, sb = 0.0
        for s in samples {
            let x = Double(s.x), y = Double(s.y)
            sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y; n += 1
            srx += x * s.r; sry += y * s.r; sr += s.r
            sgx += x * s.g; sgy += y * s.g; sg += s.g
            sbx += x * s.b; sby += y * s.b; sb += s.b
        }
        let m = [[sxx, sxy, sx], [sxy, syy, sy], [sx, sy, n]]
        func solve(_ sX: Double, _ sY: Double, _ s: Double) -> (Double, Double, Double) {
            guard let solved = solve3x3(m, [sX, sY, s]) else { return (0, 0, n > 0 ? s / n : 0) }
            return (solved[0], solved[1], solved[2])
        }
        return (solve(srx, sry, sr), solve(sgx, sgy, sg), solve(sbx, sby, sb))
    }

    nonisolated private static func solve3x3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        for i in 0..<3 {
            var pivot = i
            for r in (i + 1)..<3 where abs(a[r][i]) > abs(a[pivot][i]) { pivot = r }
            if abs(a[pivot][i]) < 1e-9 { return nil }
            a.swapAt(i, pivot); b.swapAt(i, pivot)
            for r in 0..<3 where r != i {
                let factor = a[r][i] / a[i][i]
                for c in 0..<3 { a[r][c] -= factor * a[i][c] }
                b[r] -= factor * b[i]
            }
        }
        return (0..<3).map { b[$0] / a[$0][$0] }
    }

    // MARK: - Texture clone fallback

    nonisolated private static func cloneFill(
        into buffer: inout [UInt8], maskWidth: Int, maskHeight: Int, mask: [UInt8],
        source: [UInt8], srcWidth: Int, srcHeight: Int, offsetX: Int, offsetY: Int
    ) {
        let shifts: [(Int, Int)] = [
            (0, -(maskHeight + 4)), (0, maskHeight + 4), (-(maskWidth + 4), 0), (maskWidth + 4, 0)
        ]
        var bestShift = shifts[0]
        var bestScore = Double.greatestFiniteMagnitude
        for shift in shifts {
            var score = 0.0, count = 0.0
            for my in 0..<maskHeight {
                for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 0 {
                    let sx = mx + offsetX, sy = my + offsetY
                    let ssx = sx + shift.0, ssy = sy + shift.1
                    guard sx >= 0, sx < srcWidth, sy >= 0, sy < srcHeight,
                          ssx >= 0, ssx < srcWidth, ssy >= 0, ssy < srcHeight else { continue }
                    let i1 = (sy * srcWidth + sx) * 4, i2 = (ssy * srcWidth + ssx) * 4
                    let dr = Double(source[i1]) - Double(source[i2])
                    let dg = Double(source[i1 + 1]) - Double(source[i2 + 1])
                    let db = Double(source[i1 + 2]) - Double(source[i2 + 2])
                    score += dr * dr + dg * dg + db * db
                    count += 1
                }
            }
            if count > 0, score / count < bestScore {
                bestScore = score / count
                bestShift = shift
            }
        }
        for my in 0..<maskHeight {
            for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 255 {
                let sx = mx + offsetX, sy = my + offsetY
                let ssx = sx + bestShift.0, ssy = sy + bestShift.1
                guard ssx >= 0, ssx < srcWidth, ssy >= 0, ssy < srcHeight else { continue }
                let si = (ssy * srcWidth + ssx) * 4
                let di = (my * maskWidth + mx) * 4
                buffer[di] = source[si]
                buffer[di + 1] = source[si + 1]
                buffer[di + 2] = source[si + 2]
            }
        }
    }

    // MARK: - Edge feathering

    nonisolated private static func feather(
        _ buffer: inout [UInt8], maskWidth: Int, maskHeight: Int, mask: [UInt8],
        original: [UInt8], srcWidth: Int, srcHeight: Int, offsetX: Int, offsetY: Int
    ) {
        let featherRadius = 3
        for my in 0..<maskHeight {
            for mx in 0..<maskWidth where mask[my * maskWidth + mx] == 255 {
                var minDist = featherRadius + 1
                for dy in -featherRadius...featherRadius {
                    for dx in -featherRadius...featherRadius {
                        let nx = mx + dx, ny = my + dy
                        guard nx >= 0, nx < maskWidth, ny >= 0, ny < maskHeight, mask[ny * maskWidth + nx] == 0 else { continue }
                        let dist = Int(sqrt(Double(dx * dx + dy * dy)))
                        if dist < minDist { minDist = dist }
                    }
                }
                guard minDist <= featherRadius else { continue }
                let alpha = Double(minDist) / Double(featherRadius)
                let sx = mx + offsetX, sy = my + offsetY
                guard sx >= 0, sx < srcWidth, sy >= 0, sy < srcHeight else { continue }
                let si = (sy * srcWidth + sx) * 4
                let di = (my * maskWidth + mx) * 4
                for c in 0..<3 {
                    let reconstructed = Double(buffer[di + c])
                    let orig = Double(original[si + c])
                    buffer[di + c] = clampByte(reconstructed * alpha + orig * (1 - alpha))
                }
            }
        }
    }

    // MARK: - Image construction

    nonisolated private static func clampByte(_ v: Double) -> UInt8 {
        UInt8(max(0, min(255, v)))
    }

    // CGContext(data: <externally-owned pointer>, ...) does NOT copy the buffer — it uses it
    // directly, so an image later read from it must not outlive that memory. Passing `data: nil`
    // instead makes the context allocate and own a buffer for its full lifetime; we copy our
    // computed pixels into that CG-owned buffer before calling `makeImage()`, so the resulting
    // `CGImage` never references memory owned by a Swift array.
    nonisolated private static func makeRGBAImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let context = BitmapContext.make(width: width, height: height), let data = context.data else { return nil }
        buffer.withUnsafeBytes { src in
            data.copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        return context.makeImage()
    }

    nonisolated private static func makeGrayImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let data = context.data else { return nil }
        buffer.withUnsafeBytes { src in
            data.copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        return context.makeImage()
    }
}
