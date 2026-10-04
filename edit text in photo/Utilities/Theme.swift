import SwiftUI

/// Shared colors and measurements for a quiet, photo-first interface.
enum Theme {
    // MARK: Accent

    /// Muted brass gives the editor one clear point of focus without competing with the photo.
    static let accent = Color(red: 0.78, green: 0.62, blue: 0.35)
    static let accentSoft = accent.opacity(0.16)

    static let success = Color(red: 0.43, green: 0.68, blue: 0.52)
    static let warning = Color(red: 0.86, green: 0.62, blue: 0.34)
    static let danger = Color(red: 0.84, green: 0.43, blue: 0.39)

    // MARK: Editor surfaces

    static let canvasBackground = Color(.systemGroupedBackground)
    static let canvasSurface = Color(.secondarySystemGroupedBackground)
    static let canvasSurfaceElevated = Color(.tertiarySystemGroupedBackground)
    static let canvasStroke = Color(.separator).opacity(0.5)
    static let canvasTextPrimary = Color(.label)
    static let canvasTextSecondary = Color(.secondaryLabel)

    // MARK: Picker surfaces

    static let welcomeBackground = Color(red: 0.95, green: 0.94, blue: 0.91)
    static let welcomeSurface = Color(red: 0.985, green: 0.98, blue: 0.96)
    static let welcomeStroke = Color(red: 0.85, green: 0.83, blue: 0.78)
    static let welcomeText = Color(red: 0.15, green: 0.16, blue: 0.15)
    static let welcomeTextSecondary = Color(red: 0.43, green: 0.43, blue: 0.40)
    static let welcomeAccent = Color(red: 0.50, green: 0.39, blue: 0.23)

    // MARK: Region confidence tinting

    static func confidenceColor(_ confidence: Float) -> Color {
        switch confidence {
        case 0.85...: return Color(red: 0.36, green: 0.76, blue: 0.53)
        case 0.6..<0.85: return Color(red: 0.91, green: 0.69, blue: 0.36)
        default: return Color(red: 0.89, green: 0.45, blue: 0.42)
        }
    }

    // MARK: Metrics

    static let cornerRadiusLarge: CGFloat = 22
    static let cornerRadiusMedium: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 9
    static let spacingXS: CGFloat = 6
    static let spacingS: CGFloat = 10
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24

    static let floatingShadowColor = Color.black.opacity(0.22)
}

/// Centralized haptic feedback so interactions feel deliberate rather than silent/default.
enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumTap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
