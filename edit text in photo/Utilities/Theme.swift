import SwiftUI

/// Shared design tokens so the app reads as one designed surface instead of default-control
/// styling scattered across views.
enum Theme {
    // MARK: Brand color

    /// Deep violet — distinct from the default system blue, reads as a purpose-built creative
    /// tool rather than a stock SwiftUI screen.
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.98)
    static let accentSoft = Color(red: 0.42, green: 0.36, blue: 0.98).opacity(0.14)

    static let success = Color(red: 0.20, green: 0.78, blue: 0.55)
    static let warning = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let danger = Color(red: 0.95, green: 0.32, blue: 0.42)

    // MARK: Editor canvas chrome

    /// The canvas area uses a near-black backdrop (like Lightroom/Darkroom-style editors) so the
    /// photo — not a plain white background — is the visual focus, regardless of system theme.
    static let canvasBackground = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let canvasSurface = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let canvasSurfaceElevated = Color(red: 0.17, green: 0.17, blue: 0.21)
    static let canvasStroke = Color.white.opacity(0.08)
    static let canvasTextPrimary = Color.white.opacity(0.94)
    static let canvasTextSecondary = Color.white.opacity(0.56)

    // MARK: Region confidence tinting

    /// Boxes drawn over detected text are tinted by OCR confidence, so low-confidence detections
    /// visibly stand out before the user taps them.
    static func confidenceColor(_ confidence: Float) -> Color {
        switch confidence {
        case 0.85...: return Color(red: 0.36, green: 0.82, blue: 0.56)
        case 0.6..<0.85: return Color(red: 0.98, green: 0.74, blue: 0.24)
        default: return Color(red: 0.98, green: 0.42, blue: 0.42)
        }
    }

    // MARK: Metrics

    static let cornerRadiusLarge: CGFloat = 28
    static let cornerRadiusMedium: CGFloat = 18
    static let cornerRadiusSmall: CGFloat = 12
    static let spacingXS: CGFloat = 6
    static let spacingS: CGFloat = 10
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24

    // MARK: Shadows

    static let floatingShadowColor = Color.black.opacity(0.28)
}

/// Consistent pill-shaped surface used for floating toolbars/badges over the canvas.
struct GlassPill: ViewModifier {
    var padding: CGFloat = Theme.spacingM
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, padding)
            .padding(.vertical, Theme.spacingS)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.canvasStroke, lineWidth: 1))
            .shadow(color: Theme.floatingShadowColor, radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glassPill(padding: CGFloat = Theme.spacingM) -> some View {
        modifier(GlassPill(padding: padding))
    }
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
