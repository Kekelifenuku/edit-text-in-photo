import CoreGraphics
import Foundation

/// One committed edit, holding only the changed region needed to undo or redo it.
/// Keeping localized snapshots avoids retaining two full-resolution images per history item.
struct TextEdit: Identifiable {
    let id: UUID
    let regionID: UUID
    let originalText: String
    let newText: String
    let originalHidden: Bool
    let newHidden: Bool
    let style: TextStyle
    let timestamp: Date
    let patchRect: CGRect
    let beforePatch: CGImage
    let afterPatch: CGImage
}
