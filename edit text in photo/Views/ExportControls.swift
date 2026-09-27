import SwiftUI

struct ExportControls: View {
    var viewModel: PhotoEditorViewModel
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var justSaved = false

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            if let uiImage = viewModel.exportUIImage() {
                ShareLink(
                    item: Image(uiImage: uiImage),
                    preview: SharePreview("Edited Photo", image: Image(uiImage: uiImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.canvasTextPrimary)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Theme.canvasStroke, lineWidth: 1))
                }
            }

            Button {
                Haptics.mediumTap()
                Task { await save() }
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: justSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                    }
                    Text(justSaved ? "Saved" : "Save to Photos")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(colors: justSaved ? [Theme.success, Theme.success] : [Theme.accent, Color(red: 0.60, green: 0.30, blue: 0.92)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
                .shadow(color: Theme.accent.opacity(0.4), radius: 14, x: 0, y: 8)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, Theme.spacingM)
        .alert(
            "",
            isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } }),
            presenting: saveMessage
        ) { _ in
            Button("OK", role: .cancel) { saveMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func save() async {
        guard let uiImage = viewModel.exportUIImage() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibraryService.save(uiImage)
            Haptics.success()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { justSaved = true }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { justSaved = false }
        } catch {
            Haptics.error()
            saveMessage = error.localizedDescription
        }
    }
}
