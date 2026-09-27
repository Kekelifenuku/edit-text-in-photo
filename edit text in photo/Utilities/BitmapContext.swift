import CoreGraphics

/// Helpers for creating plain RGBA8 bitmap contexts.
///
/// Two different orientations are needed here, and they are NOT interchangeable — mixing them up
/// silently flips content:
///
/// - Reading pixels out of an existing `CGImage` (`pixelBuffer(of:)`) or resizing one
///   (`CGImage.scaled(by:)`) must use a **native** (unflipped) context. `CGContext.draw(_:in:)`
///   already reproduces a source image right-side-up when the destination is a native context —
///   empirically verified: drawing a source image into a native context and reading the result
///   back matches the source exactly, row for row.
/// - Drawing fresh vector content (rects, CoreText glyphs) where the *positions* you pass in
///   should mean "distance from the top" needs a **top-left-oriented** context
///   (`makeTopLeftOriented`), which flips the CTM so `y=0` really is the top for that content —
///   also empirically verified (a fill at `y: 0..20` lands at the visual top only with this flip).
///   Feeding an *image* through a top-left-oriented context inverts it — the two behave
///   oppositely, because `CGContextDrawImage` already compensates for `CGImage`'s row-0-is-top
///   layout on its own, and stacking our own flip on top of that compensation double-flips it.
nonisolated enum BitmapContext {
    static let colorSpace = CGColorSpaceCreateDeviceRGB()

    static func make(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    /// A context for drawing fresh vector content (rects, CoreText) where positions should be
    /// interpreted as (x, y-from-top, w, h). Do not draw a `CGImage` into this context — see the
    /// type-level note.
    static func makeTopLeftOriented(width: Int, height: Int) -> CGContext? {
        guard let context = make(width: width, height: height) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    /// Renders `image` into a fresh RGBA8 pixel buffer the same size as the image, copied out into
    /// a plain owned array. `pixels[(y * width + x) * 4 ...]` is the RGBA sample at column `x`,
    /// row `y` counted from the top, matching `image`'s own pixel coordinates directly.
    ///
    /// This deliberately returns an owned `[UInt8]` rather than a pointer into the `CGContext`'s
    /// backing store: a pointer would dangle the moment the context is released, and nothing
    /// about reading through it later would signal that to the caller (ARC has no obligation to
    /// keep a context alive just because a raw pointer derived from it is still in scope).
    static func pixelBuffer(of image: CGImage) -> (width: Int, height: Int, pixels: [UInt8])? {
        let width = image.width
        let height = image.height
        guard let context = make(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let count = width * height * 4
        let pixels = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
        return (width, height, pixels)
    }
}
