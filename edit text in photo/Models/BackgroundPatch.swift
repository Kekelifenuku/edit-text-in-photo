import CoreGraphics
import Foundation

enum ReconstructionMethod: String {
    case solid, gradient, texture
}

/// A reconstructed (text-removed) background patch for one region, cached so re-rendering a
/// region after a manual style override doesn't redo the background-reconstruction work.
struct BackgroundPatch {
    let regionID: UUID
    let method: ReconstructionMethod
    /// The reconstructed background raster, sized to `patchRect`.
    let patch: CGImage
    /// Top-left-origin pixel rect in the full working image this patch covers.
    let patchRect: CGRect
    /// Single-channel-ish alpha mask (0/255, same size as `patch`) marking which pixels were
    /// reconstructed (i.e. used to be glyph ink). Used both for blending and for verification's
    /// "did anything outside the mask change" check.
    let mask: CGImage
}
