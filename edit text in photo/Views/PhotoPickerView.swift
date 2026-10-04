import PhotosUI
import SwiftUI

struct PhotoPickerView: View {
    @State private var viewModel = PhotoEditorViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            if viewModel.workingImage != nil {
                EditorCanvasView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                emptyState
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: viewModel.workingImage != nil)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                isLoading = true
                defer {
                    isLoading = false
                    pickerItem = nil
                }
                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                        viewModel.errorMessage = "Couldn't load the selected photo. Try choosing another image."
                        return
                    }
                    guard let uiImage = UIImage(data: data) else {
                        viewModel.errorMessage = "This image couldn't be opened. Try choosing another photo."
                        return
                    }
                    Haptics.mediumTap()
                    await viewModel.load(uiImage: uiImage)
                } catch {
                    viewModel.errorMessage = "Couldn't load the selected photo: \(error.localizedDescription)"
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 48)

            VStack(alignment: .leading, spacing: 0) {
                Text("PHOTO TEXT EDITOR")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.welcomeAccent)

                Text("Keep the photo.\nChange the words.")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .tracking(-0.8)
                    .lineSpacing(-4)
                    .foregroundStyle(Theme.welcomeText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)

                Text("Select text in a photo and rewrite it while preserving the original look.")
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.welcomeTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 310, alignment: .leading)
                    .padding(.top, 14)

                HStack(spacing: 10) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 14, weight: .medium))
                    Text("Find text")
                    Circle().fill(Theme.welcomeStroke).frame(width: 3, height: 3)
                    Text("Match type")
                    Circle().fill(Theme.welcomeStroke).frame(width: 3, height: 3)
                    Text("Review")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.welcomeTextSecondary)
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacingL)

            Spacer(minLength: 44)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 10) {
                    if isLoading {
                        ProgressView().tint(Theme.welcomeBackground)
                    } else {
                        Image(systemName: "photo")
                    }
                    Text(isLoading ? "Reading photo…" : "Choose a photo")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.welcomeBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.welcomeText, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
                .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.horizontal, Theme.spacingL)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingL)
                    .padding(.top, Theme.spacingS)
            } else {
                Text("Choose an image from your library")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.welcomeTextSecondary)
                    .padding(.top, 12)
            }

            Spacer(minLength: 28)
        }
        .background(Theme.welcomeBackground.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack {
            Text("Retouch")
                .font(.system(size: 21, weight: .medium, design: .serif))
                .foregroundStyle(Theme.welcomeText)

            Spacer()

            Button {
                Haptics.lightTap()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.welcomeText)
                    .frame(width: 42, height: 42)
                    .background(Theme.welcomeSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                            .stroke(Theme.welcomeStroke.opacity(0.8), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.top, Theme.spacingS)
    }

}

#Preview {
    PhotoPickerView()
}
