import SwiftUI

struct ExportControls: View {
    var viewModel: PhotoEditorViewModel
    var paywallPresentationEnabled = true
    @Environment(RevenueCatAccess.self) private var revenueCat
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var justSaved = false
    @State private var successResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            if let uiImage = viewModel.exportUIImage() {
                if revenueCat.isPro {
                    ShareLink(
                        item: Image(uiImage: uiImage),
                        preview: SharePreview("Edited Photo", image: Image(uiImage: uiImage))
                    ) {
                        shareButtonLabel
                    }
                } else {
                    Button { revenueCat.requestProAccess() } label: {
                        shareButtonLabel
                    }
                }
            }

            Button {
                Haptics.mediumTap()
                if revenueCat.isPro {
                    Task { await save() }
                } else {
                    revenueCat.requestProAccess()
                }
            } label: {
                HStack(spacing: Theme.spacingXS) {
                    if isSaving {
                        ProgressView().tint(Theme.canvasBackground)
                    } else {
                        Image(systemName: justSaved ? "checkmark.circle.fill" : "square.and.arrow.down.fill")
                    }
                    Text(isSaving ? "Saving…" : justSaved ? "Saved" : "Save to Photos")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.canvasBackground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(justSaved ? Theme.success : Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .disabled(isSaving || viewModel.workingImage == nil)
            .accessibilityHint("Saves the full-resolution edited photo to your Photos library.")
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
        .sheet(isPresented: Binding(
            get: { paywallPresentationEnabled && revenueCat.showProPaywall },
            set: { revenueCat.showProPaywall = $0 }
        )) {
            RevenueCatProPaywall()
                .environment(revenueCat)
        }
        .onDisappear {
            successResetTask?.cancel()
        }
    }

    private var shareButtonLabel: some View {
        Label(revenueCat.isPro ? "Share" : "Unlock", systemImage: revenueCat.isPro ? "square.and.arrow.up" : "lock.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.canvasTextPrimary)
            .frame(width: 104, height: 52)
            .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).stroke(Theme.canvasStroke, lineWidth: 1))
    }

    private func save() async {
        guard !isSaving else { return }
        guard let uiImage = viewModel.exportUIImage() else {
            saveMessage = "Couldn't prepare the edited photo for export."
            return
        }
        successResetTask?.cancel()
        justSaved = false
        isSaving = true
        defer { isSaving = false }
        do {
            try await PhotoLibraryService.save(uiImage)
            Haptics.success()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { justSaved = true }
            successResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                guard !Task.isCancelled else { return }
                withAnimation { justSaved = false }
            }
        } catch {
            Haptics.error()
            saveMessage = error.localizedDescription
        }
    }
}
