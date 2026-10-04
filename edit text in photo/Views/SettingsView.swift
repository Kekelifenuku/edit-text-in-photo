import SwiftUI
import UIKit
import StoreKit

struct SettingsView: View {
    @Environment(RevenueCatAccess.self) private var revenueCat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.spacingL) {
                    subscriptionBanner

                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        sectionTitle("Pro features")
                        settingsCard {
                            settingsRow(
                                icon: revenueCat.isPro ? "checkmark.seal.fill" : "lock.fill",
                                tint: revenueCat.isPro ? Theme.success : Theme.accent,
                                title: "Text backgrounds, Share & Save",
                                detail: revenueCat.isPro
                                    ? "All Retouch Pro features are active."
                                    : "Unlock label backgrounds and export edited photos."
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        sectionTitle("Share & Support")
                        settingsCard {
                            if let appStoreURL {
                                ShareLink(
                                    item: appStoreURL,
                                    subject: Text("Try Retouch"),
                                    message: Text("Edit text in photos with Retouch."),
                                    preview: SharePreview("Retouch")
                                ) {
                                    actionRow(
                                        icon: "square.and.arrow.up",
                                        title: "Share Retouch",
                                        detail: "Share the App Store link."
                                    )
                                }
                            }
                            Divider().overlay(Theme.canvasStroke)
                            Button(action: requestAppReview) {
                                actionRow(
                                    icon: "star.bubble",
                                    title: "Rate Retouch",
                                    detail: "Open Apple’s in-app review prompt."
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens Apple's native rating prompt.")
                            Divider().overlay(Theme.canvasStroke)
                            if let bugReportURL {
                                Link(destination: bugReportURL) {
                                    actionRow(
                                        icon: "ladybug",
                                        title: "Report a Bug",
                                        detail: "Email support with app and device details."
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        sectionTitle("About")
                        settingsCard {
                            settingsRow(
                                icon: "text.viewfinder",
                                tint: Theme.accent,
                                title: "Retouch",
                                detail: "Pixel-precise text replacement for your photos."
                            )
                            Divider().overlay(Theme.canvasStroke)
                            settingsRow(
                                icon: "number",
                                tint: Theme.canvasTextSecondary,
                                title: "Version",
                                detail: appVersion
                            )
                        }
                    }
                }
                .padding(.horizontal, Theme.spacingM)
                .padding(.top, Theme.spacingS)
                .padding(.bottom, Theme.spacingL)
            }
            .background(Theme.canvasBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { revenueCat.refreshEntitlement() }
        .sheet(isPresented: Binding(
            get: { revenueCat.showProPaywall },
            set: { revenueCat.showProPaywall = $0 }
        )) {
            RevenueCatProPaywall()
                .environment(revenueCat)
        }
    }

    private var subscriptionBanner: some View {
        Button {
            guard !revenueCat.isPro else { return }
            Haptics.mediumTap()
            revenueCat.requestProAccess()
        } label: {
            VStack(alignment: .leading, spacing: Theme.spacingM) {
                HStack(alignment: .top, spacing: Theme.spacingM) {
                    Image(systemName: revenueCat.isPro ? "checkmark.seal.fill" : "sparkles")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(revenueCat.isPro ? Theme.success : Theme.accent)
                        .frame(width: 38, height: 38)
                        .background((revenueCat.isPro ? Theme.success : Theme.accent).opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(revenueCat.isPro ? "Retouch Pro is active" : "Unlock Retouch Pro")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.canvasTextPrimary)
                        Text(revenueCat.isPro
                             ? "Text backgrounds, Share, and Save are unlocked."
                             : "Add text backgrounds, then export and share your edits.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.canvasTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if revenueCat.isPro {
                    Label("Subscription active", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.success)
                } else {
                    HStack {
                        Text("View Pro options")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(Theme.spacingM)
            .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                    .stroke(Theme.canvasStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(revenueCat.isPro)
        .accessibilityHint(revenueCat.isPro ? "Retouch Pro is active" : "Opens the Pro subscription paywall")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.canvasTextSecondary)
            .padding(.leading, 2)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: Theme.spacingM) {
            content()
        }
        .padding(Theme.spacingM)
        .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Theme.canvasStroke, lineWidth: 1)
        )
    }

    private func settingsRow(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingM) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.canvasTextPrimary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.canvasTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func actionRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Theme.spacingS) {
            settingsRow(icon: icon, tint: Theme.accent, title: title, detail: detail)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.canvasTextSecondary)
        }
        .contentShape(Rectangle())
    }

    private func requestAppReview() {
        ReviewRequestManager.shared.recordExplicitReviewRequest(appVersion: ReviewRequestManager.currentAppVersion)
        requestReview()
    }

    private var appStoreURL: URL? {
        URL(string: "https://apps.apple.com/app/id6757655946")
    }

    private var bugReportURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "fenuku.kekeli8989@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Retouch bug report"),
            URLQueryItem(
                name: "body",
                value: "Please describe what happened:\n\nApp version: \(appVersion)\niOS version: \(UIDevice.current.systemVersion)\nDevice: \(UIDevice.current.model)\n"
            )
        ]
        return components.url
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(RevenueCatAccess.shared)
}
