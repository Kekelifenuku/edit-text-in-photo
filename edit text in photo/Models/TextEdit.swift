import CoreGraphics
import Foundation

/// One committed edit, holding enough to undo it: a snapshot of the full working image from
/// immediately before the edit was applied.
struct TextEdit: Identifiable {
    let id: UUID
    let regionID: UUID
    let originalText: String
    let newText: String
    let style: TextStyle
    let timestamp: Date
    let beforeImage: CGImage
    let afterImage: CGImage
}
