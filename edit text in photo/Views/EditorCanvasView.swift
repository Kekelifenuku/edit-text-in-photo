import SwiftUI
import StoreKit

struct EditorCanvasView: View {
    var viewModel: PhotoEditorViewModel
    @Environment(RevenueCatAccess.self) private var revenueCat
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var editingRegion: TextRegion?
    @State private var showHistory = false
    @State private var shouldCheckReviewAfterEditDismissal = false

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var showingOriginal = false
    @State private var activeTool: EditorTool = .select
    @State private var drawStart: CGPoint?
    @State private var drawRect: CGRect?
    @State private var isErasing = false
    @State private var detectionNotice: String?

    var body: some View {
        ZStack {
            Theme.canvasBackground.ignoresSafeArea()

            GeometryReader { geo in
                if let cgImage = viewModel.workingImage {
                    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                    let displaySize = fitSize(imageSize, in: geo.size.applying(.init(scaleX: 0.92, y: 0.86)))
                    let baseScale = imageSize.width > 0 ? displaySize.width / imageSize.width : 1
                    let imageVerticalBias = min(48, geo.size.height * 0.055)
                    let baseOffset = CGPoint(
                        x: (geo.size.width - displaySize.width) / 2,
                        y: (geo.size.height - displaySize.height) / 2 - imageVerticalBias
                    )

                    ZStack(alignment: .topLeading) {
                        Image(decorative: (showingOriginal ? viewModel.originalImage : cgImage) ?? cgImage, scale: 1)
                            .resizable()
                            .frame(width: displaySize.width, height: displaySize.height)
                            .offset(x: baseOffset.x, y: baseOffset.y)
                            .shadow(color: .black.opacity(0.32), radius: 16, x: 0, y: 8)

                        if !showingOriginal {
                            ForEach(viewModel.regions.filter { !$0.isHidden }) { region in
                                RegionOverlay(
                                    region: region,
                                    isSelected: viewModel.selectedRegionID == region.id,
                                    scale: baseScale,
                                    offset: baseOffset
                                )
                            }
                        }

                        if let drawRect, activeTool == .draw {
                            Rectangle()
                                .fill(Theme.accent.opacity(0.14))
                                .overlay(Rectangle().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
                                .frame(width: drawRect.width, height: drawRect.height)
                                .position(x: drawRect.midX, y: drawRect.midY)
                                .allowsHitTesting(false)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 60) {
                    } onPressingChanged: { pressing in
                        guard viewModel.canUndo else { return }
                        if pressing { Haptics.lightTap() }
                        withAnimation(.easeInOut(duration: 0.15)) { showingOriginal = pressing }
                    }
                    .scaleEffect(scale, anchor: .center)
                    .offset(panOffset)
                    .contentShape(Rectangle())
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 5)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { panOffset = .zero; lastPanOffset = .zero } }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if activeTool == .draw {
                                    drawStart = drawStart ?? value.startLocation
                                    guard let drawStart else { return }
                                    drawRect = CGRect(
                                        x: min(drawStart.x, value.location.x),
                                        y: min(drawStart.y, value.location.y),
                                        width: abs(value.location.x - drawStart.x),
                                        height: abs(value.location.y - drawStart.y)
                                    )
                                    return
                                }
                                guard scale > 1 else { return }
                                panOffset = CGSize(
                                    width: lastPanOffset.width + value.translation.width,
                                    height: lastPanOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                if activeTool == .draw {
                                    defer {
                                        drawStart = nil
                                        drawRect = nil
                                    }
                                    guard let drawStart, baseScale > 0 else { return }
                                    let selection = CGRect(
                                        x: min(drawStart.x, value.location.x),
                                        y: min(drawStart.y, value.location.y),
                                        width: abs(value.location.x - drawStart.x),
                                        height: abs(value.location.y - drawStart.y)
                                    )
                                    let imageRect = CGRect(
                                        x: (selection.minX - baseOffset.x) / baseScale,
                                        y: (selection.minY - baseOffset.y) / baseScale,
                                        width: selection.width / baseScale,
                                        height: selection.height / baseScale
                                    )
                                    if let region = viewModel.addManualRegion(in: imageRect) {
                                        Haptics.selection()
                                        activeTool = .select
                                        editingRegion = region
                                    }
                                    return
                                }
                                lastPanOffset = panOffset
                            }
                    )
                    .onTapGesture { location in
                        guard activeTool != .draw else { return }
                        guard baseScale > 0 else { return }
                        let imagePoint = CGPoint(
                            x: (location.x - baseOffset.x) / baseScale,
                            y: (location.y - baseOffset.y) / baseScale
                        )
                        if let hit = viewModel.regions.first(where: { !$0.isHidden && $0.hitTest(imagePoint) }) {
                            Haptics.selection()
                            if activeTool == .erase {
                                isErasing = true
                                Task {
                                    _ = await viewModel.erase(region: hit)
                                    isErasing = false
                                }
                                return
                            }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                viewModel.select(hit)
                            }
                        }
                    }
                    .onTapGesture(count: 2) {
                        guard activeTool == .select else { return }
                        if let region = viewModel.selectedRegion {
                            editingRegion = region
                            return
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scale = 1; lastScale = 1; panOffset = .zero; lastPanOffset = .zero
                        }
                    }
                }
            }
            .padding(.top, 64)
            .padding(.bottom, 84)

            if showingOriginal {
                VStack {
                    Text("BEFORE")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.canvasTextPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                                .stroke(Theme.canvasStroke, lineWidth: 1)
                        )
                        .padding(.top, 72)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
                if viewModel.stage == .detectingText {
                    detectionStatus("Finding text…", isLoading: true)
                        .padding(.horizontal, Theme.spacingM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let detectionNotice {
                    detectionStatus(detectionNotice, isLoading: false, isError: detectionNotice == "Text detection failed")
                        .padding(.horizontal, Theme.spacingM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let errorMessage = viewModel.errorMessage {
                    detectionStatus(errorMessage, isLoading: false, isError: true)
                        .padding(.horizontal, Theme.spacingM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let failure = viewModel.verificationFailure {
                    VerificationBanner(
                        message: failure.message,
                        onAdjustManually: {
                            if let region = viewModel.regions.first(where: { $0.id == failure.regionID }) {
                                editingRegion = region
                            }
                        },
                        onDismiss: { withAnimation { viewModel.verificationFailure = nil } }
                    )
                    .padding(.horizontal, Theme.spacingM)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let region = viewModel.selectedRegion, !region.isHidden {
                    selectedActions(for: region)
                        .padding(.horizontal, Theme.spacingM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                toolRail
                ExportControls(viewModel: viewModel, paywallPresentationEnabled: editingRegion == nil)
                    .padding(.bottom, Theme.spacingS)
            }
        }
        .statusBarHidden(false)
        .sheet(item: $editingRegion, onDismiss: handleTextEditDismissal) { region in
            TextEditSheet(viewModel: viewModel, region: region) {
                ReviewRequestManager.shared.recordSuccessfulAction()
                shouldCheckReviewAfterEditDismissal = true
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(viewModel: viewModel)
        }
    }

    private var topBar: some View {
        HStack(spacing: Theme.spacingS) {
            Button {
                Haptics.lightTap()
                withAnimation { viewModel.reset() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.canvasTextPrimary)
                    .frame(width: 40, height: 40)
            }
            .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).stroke(Theme.canvasStroke, lineWidth: 1))

            Spacer()

            HStack(spacing: 2) {
                toolbarIconButton("clock.arrow.circlepath", enabled: !viewModel.undoStack.isEmpty) {
                    Haptics.lightTap()
                    showHistory = true
                }
                Divider().frame(height: 18).overlay(Theme.canvasStroke)
                toolbarIconButton(
                    viewModel.stage == .detectingText ? "hourglass" : "text.viewfinder",
                    enabled: viewModel.stage == .ready,
                    action: scanForText
                )
                .accessibilityLabel(viewModel.stage == .detectingText ? "Finding text" : "Find text")
                .accessibilityHint("Scan this photo again for text that wasn't detected.")
                toolbarIconButton("arrow.uturn.backward", enabled: viewModel.canUndo) {
                    Haptics.lightTap()
                    withAnimation { viewModel.undo() }
                }
                toolbarIconButton("arrow.uturn.forward", enabled: viewModel.canRedo) {
                    Haptics.lightTap()
                    withAnimation { viewModel.redo() }
                }
            }
            .padding(.horizontal, Theme.spacingXS)
            .padding(.vertical, 2)
            .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.canvasStroke, lineWidth: 1))
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.top, Theme.spacingS)
    }

    private var toolRail: some View {
        VStack(spacing: Theme.spacingXS) {
            HStack(spacing: Theme.spacingXS) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        Haptics.lightTap()
                        withAnimation(.easeOut(duration: 0.18)) {
                            activeTool = tool
                            if tool == .draw {
                                scale = 1
                                lastScale = 1
                                panOffset = .zero
                                lastPanOffset = .zero
                            }
                        }
                    } label: {
                        Label(tool.title, systemImage: tool.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(activeTool == tool ? Theme.canvasBackground : Theme.canvasTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                activeTool == tool ? Theme.accent : .clear,
                                in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall)
                            )
                    }
                }
            }
            .padding(Theme.spacingXS)
            .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium).stroke(Theme.canvasStroke, lineWidth: 1))

            HStack(spacing: Theme.spacingXS) {
                Image(systemName: isErasing ? "hourglass" : activeTool.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(isErasing ? "Removing text…" : activeTool.hint)
                    .font(.caption)
                    .foregroundStyle(Theme.canvasTextSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.spacingM)
    }

    private func selectedActions(for region: TextRegion) -> some View {
        HStack(spacing: Theme.spacingS) {
            Button {
                Haptics.lightTap()
                editingRegion = region
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.canvasBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }

            Button {
                Haptics.warning()
                isErasing = true
                Task {
                    _ = await viewModel.erase(region: region)
                    isErasing = false
                }
            } label: {
                Label("Erase", systemImage: "eraser.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.canvasTextPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.canvasSurfaceElevated, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).stroke(Theme.canvasStroke, lineWidth: 1))
            }
            .disabled(isErasing)
        }
    }

    private func toolbarIconButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Theme.canvasTextPrimary : Theme.canvasTextSecondary.opacity(0.4))
                .frame(width: 36, height: 32)
        }
        .disabled(!enabled)
    }

    private func detectionStatus(_ message: String, isLoading: Bool, isError: Bool = false) -> some View {
        HStack(spacing: Theme.spacingS) {
            if isLoading {
                ProgressView().tint(Theme.accent)
            } else if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            } else {
                Image(systemName: message == "No new text found" ? "text.magnifyingglass" : "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.canvasTextPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingS)
        .background(Theme.canvasSurface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).stroke(Theme.canvasStroke, lineWidth: 1))
    }

    private func scanForText() {
        guard viewModel.stage == .ready else { return }
        withAnimation { detectionNotice = nil }
        Task {
            let message: String
            do {
                let addedCount = try await viewModel.detectAdditionalText()
                if addedCount == 0 {
                    message = "No new text found"
                } else {
                    message = "Found \(addedCount) new text area\(addedCount == 1 ? "" : "s")"
                }
            } catch {
                message = "Text detection failed"
            }
            withAnimation { detectionNotice = message }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if detectionNotice == message {
                withAnimation { detectionNotice = nil }
            }
        }
    }

    private func handleTextEditDismissal() {
        guard shouldCheckReviewAfterEditDismissal else { return }
        shouldCheckReviewAfterEditDismissal = false

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }

            let presentation = ReviewRequestManager.PresentationContext(
                appIsActive: scenePhase == .active,
                onboardingIsPresented: false,
                paywallIsPresented: revenueCat.showProPaywall,
                purchaseFlowIsPresented: revenueCat.showProPaywall,
                errorIsPresented: viewModel.errorMessage != nil || viewModel.verificationFailure != nil,
                anotherModalIsPresented: showHistory || editingRegion != nil || viewModel.workingImage == nil || viewModel.stage != .ready
            )
            guard ReviewRequestManager.shared.claimReviewRequestIfEligible(
                appVersion: ReviewRequestManager.currentAppVersion,
                presentation: presentation
            ) else {
                return
            }

            requestReview()
        }
    }

    private func fitSize(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

}

/// A detected text region drawn as animated corner brackets (photo-editor style) rather than a
/// plain stroked rectangle, tinted by OCR confidence.
private struct RegionOverlay: View {
    let region: TextRegion
    let isSelected: Bool
    let scale: CGFloat
    let offset: CGPoint

    var body: some View {
        let points = region.corners.map { CGPoint(x: $0.x * scale + offset.x, y: $0.y * scale + offset.y) }
        let color = isSelected ? Theme.accent : Theme.confidenceColor(region.confidence)

        ZStack {
            quadPath(points).stroke(color.opacity(isSelected ? 0.9 : 0.55), lineWidth: isSelected ? 2 : 1.2)
            if isSelected {
                quadPath(points).fill(color.opacity(0.1))
            }
            ForEach(0..<4, id: \.self) { i in
                CornerBracket()
                    .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .position(points[i])
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected ? 1 : 0.6)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private func quadPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
