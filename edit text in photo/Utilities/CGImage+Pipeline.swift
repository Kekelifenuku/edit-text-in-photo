import CoreGraphics

extension CGImage {
    nonisolated var pixelBounds: CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    /// Crops to `rect` (top-left-origin pixel coordinates), clamped to the image bounds.
    nonisolated func cropped(to rect: CGRect) -> CGImage? {
        let clamped = rect.integral.intersection(pixelBounds)
        guard !clamped.isEmpty, clamped.width >= 1, clamped.height >= 1 else { return nil }
        return cropping(to: clamped)
    }

    /// Resizes by `factor`, keeping the result oriented the same way as the source.
    nonisolated func scaled(by factor: CGFloat, interpolationQuality: CGInterpolationQuality = .high) -> CGImage? {
        guard factor > 0 else { return nil }
        let newWidth = max(1, Int((CGFloat(width) * factor).rounded()))
        let newHeight = max(1, Int((CGFloat(height) * factor).rounded()))
        guard let context = BitmapContext.make(width: newWidth, height: newHeight) else { return nil }
        context.interpolationQuality = interpolationQuality
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
