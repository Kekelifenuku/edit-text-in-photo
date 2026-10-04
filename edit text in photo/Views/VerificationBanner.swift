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
                        .background(Theme.canvasSurfaceElevated, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.canvasTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAdjustManually) {
                Text("Adjust Manually")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Theme.canvasSurfaceElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                            .stroke(Theme.warning.opacity(0.24), lineWidth: 1)
                    )
            }
        }
        .padding(Theme.spacingM)
        .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Theme.warning.opacity(0.22), lineWidth: 1)
        )
        .padding(.bottom, Theme.spacingS)
    }
}
