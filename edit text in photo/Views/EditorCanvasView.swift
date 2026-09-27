import SwiftUI

struct EditorCanvasView: View {
    var viewModel: PhotoEditorViewModel
    @State private var editingRegion: TextRegion?
    @State private var showHistory = false

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var showingOriginal = false

    var body: some View {
        ZStack {
            Theme.canvasBackground.ignoresSafeArea()

            GeometryReader { geo in
                if let cgImage = viewModel.workingImage {
                    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                    let displaySize = fitSize(imageSize, in: geo.size.applying(.init(scaleX: 0.92, y: 0.86)))
                    let baseScale = imageSize.width > 0 ? displaySize.width / imageSize.width : 1
                    let baseOffset = CGPoint(
                        x: (geo.size.width - displaySize.width) / 2,
                        y: (geo.size.height - displaySize.height) / 2
                    )

                    ZStack(alignment: .topLeading) {
                        Image(decorative: (showingOriginal ? viewModel.originalImage : cgImage) ?? cgImage, scale: 1)
                            .resizable()
                            .frame(width: displaySize.width, height: displaySize.height)
                            .offset(x: baseOffset.x, y: baseOffset.y)
                            .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)

                        if !showingOriginal {
                            ForEach(viewModel.regions) { region in
                                RegionOverlay(
                                    region: region,
                                    isSelected: viewModel.selectedRegionID == region.id,
                                    scale: baseScale,
                                    offset: baseOffset
                                )
                            }
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
                                guard scale > 1 else { return }
                                panOffset = CGSize(
                                    width: lastPanOffset.width + value.translation.width,
                                    height: lastPanOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastPanOffset = panOffset }
                    )
                    .onTapGesture { location in
                        guard baseScale > 0 else { return }
                        let imagePoint = CGPoint(
                            x: (location.x - baseOffset.x) / baseScale,
                            y: (location.y - baseOffset.y) / baseScale
                        )
                        if let hit = viewModel.regions.first(where: { $0.hitTest(imagePoint) }) {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                viewModel.select(hit)
                            }
                            editingRegion = hit
                        }
                    }
                    .onTapGesture(count: 2) {
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
                        .foregroundStyle(.white)
                        .glassPill(padding: Theme.spacingS)
                        .padding(.top, 72)
                    Spacer()
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            VStack {
                topBar
                Spacer()
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
                ExportControls(viewModel: viewModel)
                    .padding(.bottom, Theme.spacingS)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .sheet(item: $editingRegion) { region in
            TextEditSheet(viewModel: viewModel, region: region)
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
                    .frame(width: 36, height: 36)
            }
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Theme.canvasStroke, lineWidth: 1))

            Spacer()

            HStack(spacing: 2) {
                toolbarIconButton("clock.arrow.circlepath", enabled: !viewModel.undoStack.isEmpty) {
                    Haptics.lightTap()
                    showHistory = true
                }
                Divider().frame(height: 18).overlay(Theme.canvasStroke)
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Theme.canvasStroke, lineWidth: 1))
        }
        .padding(.horizontal, Theme.spacingM)
        .padding(.top, Theme.spacingS)
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
