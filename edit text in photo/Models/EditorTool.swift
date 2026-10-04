import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case draw
    case erase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .draw: return "Draw"
        case .erase: return "Erase"
        }
    }

    var icon: String {
        switch self {
        case .select: return "hand.tap.fill"
        case .draw: return "pencil.and.outline"
        case .erase: return "eraser.fill"
        }
    }

    var hint: String {
        switch self {
        case .select: return "Tap a text block to edit it"
        case .draw: return "Draw around text OCR missed"
        case .erase: return "Tap a text block to remove it"
        }
    }
}
