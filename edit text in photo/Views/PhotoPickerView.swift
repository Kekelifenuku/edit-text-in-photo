import PhotosUI
import SwiftUI

struct PhotoPickerView: View {
    @State private var viewModel = PhotoEditorViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var heroPulse = false

    var body: some View {
        ZStack {
            if viewModel.workingImage != nil {
                EditorCanvasView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                emptyState
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.workingImage != nil)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                isLoading = true
                defer { isLoading = false }
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    Haptics.mediumTap()
                    await viewModel.load(uiImage: uiImage)
                }
                pickerItem = nil
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.canvasBackground, Color(red: 0.11, green: 0.09, blue: 0.19)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Theme.accent.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: 148, height: 148)
                        .blur(radius: 4)
                        .scaleEffect(heroPulse ? 1.08 : 0.94)

                    Circle()
                        .fill(
                            LinearGradient(colors: [Theme.accent, Color(red: 0.62, green: 0.32, blue: 0.94)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 104, height: 104)
                        .shadow(color: Theme.accent.opacity(0.55), radius: 24, x: 0, y: 12)

                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                        heroPulse = true
                    }
                }

                VStack(spacing: Theme.spacingS) {
                    Text("Retouch")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.canvasTextPrimary)
                    Text("Tap any text in a photo and rewrite it —\nsame font, same place, pixel-precise.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.canvasTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.top, Theme.spacingL)

                featureRow
                    .padding(.top, Theme.spacingL)
                    .padding(.horizontal, Theme.spacingL)

                Spacer(minLength: 32)

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    HStack(spacing: Theme.spacingS) {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "photo.badge.plus.fill")
                        }
                        Text(isLoading ? "Reading photo…" : "Choose a Photo")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(colors: [Theme.accent, Color(red: 0.60, green: 0.30, blue: 0.92)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: Theme.accent.opacity(0.45), radius: 18, x: 0, y: 10)
                }
                .disabled(isLoading)
                .padding(.horizontal, Theme.spacingL)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacingL)
                        .padding(.top, Theme.spacingS)
                }

                Spacer(minLength: 28)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var featureRow: some View {
        HStack(spacing: 0) {
            featureItem(icon: "text.viewfinder", label: "Detects\ntext")
            featureItem(icon: "paintbrush.pointed.fill", label: "Matches\nthe font")
            featureItem(icon: "checkmark.seal.fill", label: "Self-\nverifies")
        }
    }

    private func featureItem(icon: String, label: String) -> some View {
        VStack(spacing: Theme.spacingXS) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.canvasSurface, in: Circle())
                .overlay(Circle().stroke(Theme.canvasStroke, lineWidth: 1))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.canvasTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    PhotoPickerView()
}
