import SwiftUI

struct VerificationBanner: View {
    let message: String
    let onAdjustManually: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack(spacing: Theme.spacingXS) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text("Couldn't verify this edit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.canvasTextPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.canvasTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.canvasTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAdjustManually) {
                Text("Adjust Manually")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Theme.warning, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
        }
        .padding(Theme.spacingM)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Theme.warning.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Theme.floatingShadowColor, radius: 16, x: 0, y: 8)
        .padding(.bottom, Theme.spacingS)
    }
}
