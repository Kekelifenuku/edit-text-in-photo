import SwiftUI

struct TextEditSheet: View {
    var viewModel: PhotoEditorViewModel
    let region: TextRegion
    let onSuccessfulEdit: () -> Void
    @Environment(RevenueCatAccess.self) private var revenueCat

    @State private var text: String
    @State private var style: TextStyle = .default
    @State private var autoMatchedStyle: TextStyle?
    @State private var isPreparing = true
    @State private var isSaving = false
    @State private var isPickingColor = false
    @State private var previewImage: UIImage?
    @State private var previewZoomScale: CGFloat = 1
    @State private var previewZoomStart: CGFloat = 1
    @State private var previewOffset: CGSize = .zero
    @State private var previewOffsetStart: CGSize = .zero
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFieldFocused: Bool

    init(viewModel: PhotoEditorViewModel, region: TextRegion, onSuccessfulEdit: @escaping () -> Void) {
        self.viewModel = viewModel
        self.region = region
        self.onSuccessfulEdit = onSuccessfulEdit
        _text = State(initialValue: region.text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacingM) {
                    if let previewImage {
                        previewCard(previewImage)
                    } else {
                        previewPlaceholder
                    }

                    if let failure = viewModel.verificationFailure, failure.regionID == region.id {
                        verificationFailureCard(failure.message)
                    }
                    if let saveError {
                        saveErrorCard(saveError)
                    }

                    card {
                        HStack(spacing: Theme.spacingS) {
                            Image(systemName: "textformat.abc")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20)
                            TextField("Text", text: $text, axis: .vertical)
                                .font(.system(size: 17))
                                .focused($textFieldFocused)
                                .onChange(of: text) { _, _ in updatePreview() }
                            if !text.isEmpty {
                                Button {
                                    text = ""
                                    updatePreview()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        HStack(spacing: Theme.spacingXS) {
                            sectionLabel("Letter case", icon: "textformat.abc")
                            Spacer(minLength: 0)
                            caseButton("Aa", accessibilityTitle: "Title case") { $0.localizedCapitalized }
                            caseButton("AA", accessibilityTitle: "Uppercase") { $0.uppercased() }
                            caseButton("aa", accessibilityTitle: "Lowercase") { $0.lowercased() }
                        }
                    }

                    if isPreparing {
                        preparingCard
                    } else {
                        fontCard
                        sizingCard
                        formattingCard
                        colorCard
                        backgroundCard
                        effectsCard
                    }
                }
                .padding(Theme.spacingM)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.removeRegionIfEmpty(region.id)
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.mediumTap()
                        Task {
                            isSaving = true
                            let committed = await viewModel.commitEdit(region: region, newText: text, style: style)
                            isSaving = false
                            if committed {
                                saveError = nil
                                Haptics.success()
                                onSuccessfulEdit()
                                dismiss()
                            } else {
                                if viewModel.verificationFailure?.regionID != region.id {
                                    saveError = "Couldn't save this edit. Please try again."
                                }
                                Haptics.warning()
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Done").fontWeight(.semibold)
                        }
                    }
                    .disabled(isPreparing || isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { revenueCat.showProPaywall },
            set: { revenueCat.showProPaywall = $0 }
        )) {
            RevenueCatProPaywall()
                .environment(revenueCat)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .task {
            if let analyzed = await viewModel.prepareEdit(for: region) {
                style = analyzed
                autoMatchedStyle = await viewModel.autoMatchedStyle(for: region) ?? analyzed
            }
            withAnimation(.easeOut(duration: 0.25)) { isPreparing = false }
            updatePreview()
        }
        .onDisappear {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.removeRegionIfEmpty(region.id)
            }
        }
    }

    // MARK: - Sections

    private func verificationFailureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            Label("Couldn't verify this edit", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.warning()
                guard viewModel.acceptAnyway(region: region, newText: text, style: style) else {
                    saveError = "Couldn't keep this edit. Please try again."
                    return
                }
                Haptics.success()
                onSuccessfulEdit()
                dismiss()
            } label: {
                Text("Use This Edit Anyway")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.canvasBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Theme.warning, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }
            .disabled(isSaving)
        }
        .padding(Theme.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .stroke(Theme.warning.opacity(0.24), lineWidth: 1)
        )
    }

    private func saveErrorCard(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .foregroundStyle(Theme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingM)
        .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
    }

    private func previewCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            sectionLabel("Preview", icon: "eye.fill")
            GeometryReader { geometry in
                let fittedSize = fittedImageSize(image.size, in: geometry.size)
                let zoomGesture = MagnificationGesture()
                    .onChanged { value in
                        previewZoomScale = min(max(previewZoomStart * value, 1), 4)
                    }
                    .onEnded { _ in
                        previewZoomStart = previewZoomScale
                        previewOffset = constrainedPreviewOffset(
                            previewOffset,
                            imageSize: fittedSize,
                            containerSize: geometry.size,
                            scale: previewZoomScale
                        )
                        previewOffsetStart = previewOffset
                    }
                let panGesture = DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard previewZoomScale > 1 else { return }
                        previewOffset = constrainedPreviewOffset(
                            CGSize(
                                width: previewOffsetStart.width + value.translation.width,
                                height: previewOffsetStart.height + value.translation.height
                            ),
                            imageSize: fittedSize,
                            containerSize: geometry.size,
                            scale: previewZoomScale
                        )
                    }
                    .onEnded { _ in
                        previewOffsetStart = previewOffset
                    }

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .scaleEffect(previewZoomScale)
                        .offset(previewOffset)

                    if isPickingColor {
                        VStack {
                            Label("Tap photo to sample", systemImage: "eyedropper")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.black.opacity(0.65), in: Capsule())
                            Spacer()
                        }
                        .padding(Theme.spacingS)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    if previewZoomScale > 1 {
                        Button(action: resetPreviewZoom) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(.black.opacity(0.65), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset preview zoom")
                        .padding(Theme.spacingS)
                    } else if !isPickingColor {
                        Label("Pinch to zoom", systemImage: "hand.pinch")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.65), in: Capsule())
                            .padding(Theme.spacingS)
                            .allowsHitTesting(false)
                    }
                }
                .simultaneousGesture(zoomGesture)
                .simultaneousGesture(panGesture)
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { tap in
                        sampleColor(
                            in: image,
                            at: tap.location,
                            containerSize: geometry.size
                        )
                    }
                )
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium))
        }
        .padding(Theme.spacingM)
        .background(cardBackground)
    }

    private var previewPlaceholder: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            sectionLabel("Preview", icon: "eye.fill")
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 190)
                .overlay(ProgressView())
        }
        .padding(Theme.spacingM)
        .background(cardBackground)
    }

    private var preparingCard: some View {
        HStack(spacing: Theme.spacingS) {
            ProgressView()
            Text("Analyzing font, color & background…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacingL)
        .background(cardBackground)
    }

    private var fontCard: some View {
        card {
            sectionLabel("Font", icon: "textformat")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingS) {
                    ForEach(FontMatcher.candidates, id: \.postScriptName) { candidate in
                        fontChip(candidate)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: Theme.spacingXS) {
                sectionLabel("Quick styles", icon: "sparkles")
                Spacer(minLength: 0)
                quickStyleButton("Original", icon: "wand.and.stars", action: applyAutoMatch)
                    .disabled(autoMatchedStyle == nil || isPreparing || isSaving)
                quickStyleButton("Classic", icon: "textformat") {
                    style.fontName = "Georgia"
                    style.isBold = false
                    style.isItalic = false
                    updatePreview()
                }
                quickStyleButton("Bold", icon: "bold") {
                    style.fontName = "HelveticaNeue"
                    style.isBold = true
                    updatePreview()
                }
            }
        }
    }

    private func caseButton(
        _ title: String,
        accessibilityTitle: String,
        transform: @escaping (String) -> String
    ) -> some View {
        Button {
            Haptics.selection()
            text = transform(text)
            textFieldFocused = false
            updatePreview()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.canvasTextPrimary)
                .frame(minWidth: 38, minHeight: 30)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }

    private func quickStyleButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 7)
                .frame(height: 30)
                .background(Theme.accent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func fontChip(_ candidate: FontCandidate) -> some View {
        let isSelected = style.fontName == candidate.postScriptName
        return Button {
            Haptics.selection()
            style.fontName = candidate.postScriptName
            updatePreview()
        } label: {
            Text("Ag")
                .font(.custom(candidate.postScriptName, size: 20))
                .foregroundStyle(isSelected ? Theme.canvasBackground : Theme.canvasTextPrimary)
                .frame(width: 52, height: 44)
                .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
    }

    private var sizingCard: some View {
        card {
            sectionLabel("Type settings", icon: "textformat.size")

            sliderRow(
                title: "Size",
                icon: "textformat.size",
                value: $style.pointSize,
                range: 6...120,
                step: 1,
                displayValue: "\(Int(style.pointSize))"
            )
            if style.horizontalScale < 0.995 {
                Text("Auto Match kept the font height and narrowed the letters to fit.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            sliderRow(
                title: "Letter spacing",
                icon: "arrow.left.and.right",
                value: $style.tracking,
                range: -5...20,
                step: 0.5,
                displayValue: String(format: "%.1f", style.tracking)
            )
            sliderRow(
                title: "Line spacing",
                icon: "arrow.up.and.down.text.horizontal",
                value: $style.lineSpacing,
                range: 0...20,
                step: 0.5,
                displayValue: String(format: "%.1f", style.lineSpacing)
            )

            HStack(spacing: Theme.spacingXS) {
                ForEach(TextHorizontalAlignment.allCases, id: \.self) { alignment in
                    let isSelected = style.alignment == alignment
                    Button {
                        Haptics.selection()
                        style.alignment = alignment
                        updatePreview()
                    } label: {
                        Image(systemName: iconForAlignment(alignment))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.canvasBackground : Theme.canvasTextPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func sliderRow(
        title: String,
        icon: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        displayValue: String
    ) -> some View {
        VStack(spacing: 2) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)
                .onChange(of: value.wrappedValue) { _, _ in updatePreview() }
        }
    }

    private var colorCard: some View {
        card {
            HStack {
                sectionLabel("Color", icon: "paintpalette.fill")
                Spacer()
                Button {
                    Haptics.selection()
                    withAnimation(.easeOut(duration: 0.15)) { isPickingColor.toggle() }
                } label: {
                    Label(isPickingColor ? "Cancel" : "Sample", systemImage: isPickingColor ? "xmark" : "eyedropper")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPickingColor ? Theme.canvasBackground : Theme.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            isPickingColor ? Theme.accent : Theme.accent.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Tap a point in the preview photo to use its color for the text.")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.spacingS) {
                    ForEach(presetColors, id: \.self) { preset in
                        swatch(preset)
                    }
                    ColorPicker("", selection: colorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 34, height: 34)
                }
            }
            sliderRow(
                title: "Opacity",
                icon: "circle.lefthalf.filled",
                value: opacityBinding,
                range: 0...1,
                step: 0.05,
                displayValue: "\(Int((textOpacity * 100).rounded()))%"
            )
        }
    }

    private var backgroundCard: some View {
        card {
            HStack {
                sectionLabel("Text background", icon: "rectangle.fill")
                Spacer()
                if revenueCat.isPro {
                    Button {
                        Haptics.selection()
                        style.hasBackground.toggle()
                        updatePreview()
                    } label: {
                        Label(style.hasBackground ? "On" : "Off", systemImage: style.hasBackground ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(style.hasBackground ? Theme.success : .secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Haptics.mediumTap()
                        revenueCat.requestProAccess()
                    } label: {
                        Label("Pro", systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the Retouch Pro paywall for text background styles.")
                }
            }

            if revenueCat.isPro, style.hasBackground {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.spacingS) {
                        ForEach(presetColors, id: \.self) { color in
                            backgroundSwatch(color)
                        }
                        ColorPicker("", selection: backgroundColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 34, height: 34)
                    }
                }
                sliderRow(
                    title: "Background opacity",
                    icon: "circle.lefthalf.filled",
                    value: backgroundOpacityBinding,
                    range: 0.1...1,
                    step: 0.05,
                    displayValue: "\(Int((backgroundOpacity * 100).rounded()))%"
                )
                sliderRow(
                    title: "Corner roundness",
                    icon: "rectangle.roundedtop",
                    value: $style.backgroundCornerRadius,
                    range: 0...36,
                    step: 1,
                    displayValue: style.backgroundCornerRadius == 0 ? "Square" : "\(Int(style.backgroundCornerRadius))"
                )
            } else if !revenueCat.isPro {
                Text("Add a color plate behind replacement text, then tune its opacity and corners with Pro.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func backgroundSwatch(_ color: Color) -> some View {
        let resolved = color.resolve(in: EnvironmentValues())
        let isSelected = abs(Double(resolved.red) - backgroundColorComponents[0]) < 0.03
            && abs(Double(resolved.green) - backgroundColorComponents[1]) < 0.03
            && abs(Double(resolved.blue) - backgroundColorComponents[2]) < 0.03
        return Button {
            Haptics.selection()
            style.backgroundColorComponents = [
                CGFloat(resolved.red), CGFloat(resolved.green), CGFloat(resolved.blue), backgroundOpacity
            ]
            updatePreview()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(Circle().stroke(Theme.accent, lineWidth: isSelected ? 2.5 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Background color")
    }

    private var effectsCard: some View {
        card {
            sectionLabel("Effects", icon: "sparkles")
            sliderRow(
                title: "Outline",
                icon: "circle.dashed",
                value: $style.outlineWidth,
                range: 0...4,
                step: 0.5,
                displayValue: style.outlineWidth == 0 ? "Off" : String(format: "%.1f", style.outlineWidth)
            )
            if style.outlineWidth > 0 {
                HStack(spacing: Theme.spacingS) {
                    Text("Outline color")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Auto") {
                        style.outlineColorComponents = nil
                        updatePreview()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose a contrasting outline color automatically.")
                    ColorPicker("Outline color", selection: outlineColorBinding, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 34, height: 34)
                }
            }
            sliderRow(
                title: "Shadow",
                icon: "square.3.layers.3d",
                value: $style.shadowBlur,
                range: 0...16,
                step: 1,
                displayValue: style.shadowBlur == 0 ? "Off" : "\(Int(style.shadowBlur))"
            )
            if style.shadowBlur > 0 {
                HStack(spacing: Theme.spacingS) {
                    Text("Shadow color")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Shadow color", selection: shadowColorBinding, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 34, height: 34)
                }
                sliderRow(
                    title: "Horizontal offset",
                    icon: "arrow.left.and.right",
                    value: $style.shadowOffsetXRatio,
                    range: -1...1,
                    step: 0.1,
                    displayValue: "\(Int((style.shadowOffsetXRatio * 100).rounded()))%"
                )
                sliderRow(
                    title: "Vertical offset",
                    icon: "arrow.up.and.down",
                    value: $style.shadowOffsetYRatio,
                    range: -1...1,
                    step: 0.1,
                    displayValue: "\(Int((style.shadowOffsetYRatio * 100).rounded()))%"
                )
            }
        }
    }

    private var formattingCard: some View {
        card {
            HStack {
                sectionLabel("Style", icon: "textformat.alt")
                Spacer()
                if !region.text.isEmpty {
                    Button(action: applyAutoMatch) {
                        Label("Auto match", systemImage: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(autoMatchedStyle == nil || isPreparing || isSaving)
                    .accessibilityHint("Restores the detected style and narrows longer text to preserve its font height.")
                }
            }
            HStack(spacing: Theme.spacingS) {
                formatButton("B", isSelected: style.isBold) {
                    style.isBold.toggle()
                    updatePreview()
                }
                formatButton("I", isSelected: style.isItalic) {
                    style.isItalic.toggle()
                    updatePreview()
                }
                formatButton("U", isSelected: style.isUnderlined) {
                    style.isUnderlined.toggle()
                    updatePreview()
                }
                formatButton("S", isSelected: style.isStrikethrough) {
                    style.isStrikethrough.toggle()
                    updatePreview()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func formatButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: title == "I" ? .regular : .bold, design: .serif))
                .italic(title == "I")
                .foregroundStyle(isSelected ? Theme.canvasBackground : Theme.canvasTextPrimary)
                .frame(width: 42, height: 38)
                .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
    }

    private func swatch(_ color: Color) -> some View {
        let resolved = color.resolve(in: EnvironmentValues())
        let isSelected = abs(Double(resolved.red) - style.colorComponents[0]) < 0.03
            && abs(Double(resolved.green) - style.colorComponents[1]) < 0.03
            && abs(Double(resolved.blue) - style.colorComponents[2]) < 0.03
        return Button {
            Haptics.selection()
            style.colorComponents = [CGFloat(resolved.red), CGFloat(resolved.green), CGFloat(resolved.blue), 1.0]
            updatePreview()
        } label: {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                .overlay(
                    Circle().stroke(Theme.accent, lineWidth: isSelected ? 2.5 : 0)
                        .padding(-3)
                )
        }
    }

    private var presetColors: [Color] {
        [.black, .white, .red, .orange, .yellow, .green, .blue, .purple]
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            content()
        }
        .padding(Theme.spacingM)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium)
            .fill(Color(.secondarySystemGroupedBackground))
    }

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func iconForAlignment(_ alignment: TextHorizontalAlignment) -> String {
        switch alignment {
        case .left: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = style.colorComponents
                return Color(
                    red: c.count > 0 ? c[0] : 0,
                    green: c.count > 1 ? c[1] : 0,
                    blue: c.count > 2 ? c[2] : 0,
                    opacity: c.count > 3 ? c[3] : 1
                )
            },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                style.colorComponents = [
                    CGFloat(resolved.red),
                    CGFloat(resolved.green),
                    CGFloat(resolved.blue),
                    textOpacity
                ]
                updatePreview()
            }
        )
    }

    private var textOpacity: CGFloat {
        style.colorComponents.count > 3 ? style.colorComponents[3] : 1
    }

    private var defaultOutlineColorComponents: [CGFloat] {
        let components = style.colorComponents
        let luminance = 0.2126 * Double(components.count > 0 ? components[0] : 0)
            + 0.7152 * Double(components.count > 1 ? components[1] : 0)
            + 0.0722 * Double(components.count > 2 ? components[2] : 0)
        let channel: CGFloat = luminance > 0.5 ? 0 : 1
        return [channel, channel, channel, textOpacity]
    }

    private var outlineColorBinding: Binding<Color> {
        Binding(
            get: {
                let components = style.outlineColorComponents ?? defaultOutlineColorComponents
                return Color(
                    red: components.count > 0 ? components[0] : 0,
                    green: components.count > 1 ? components[1] : 0,
                    blue: components.count > 2 ? components[2] : 0,
                    opacity: components.count > 3 ? components[3] : 1
                )
            },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                style.outlineColorComponents = [
                    CGFloat(resolved.red),
                    CGFloat(resolved.green),
                    CGFloat(resolved.blue),
                    CGFloat(resolved.opacity)
                ]
                updatePreview()
            }
        )
    }

    private var shadowColorBinding: Binding<Color> {
        Binding(
            get: {
                let components = style.shadowColorComponents
                return Color(
                    red: components.count > 0 ? components[0] : 0,
                    green: components.count > 1 ? components[1] : 0,
                    blue: components.count > 2 ? components[2] : 0,
                    opacity: components.count > 3 ? components[3] : 0.55
                )
            },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                style.shadowColorComponents = [
                    CGFloat(resolved.red),
                    CGFloat(resolved.green),
                    CGFloat(resolved.blue),
                    CGFloat(resolved.opacity)
                ]
                updatePreview()
            }
        )
    }

    private var opacityBinding: Binding<CGFloat> {
        Binding(
            get: { textOpacity },
            set: { newValue in
                if style.colorComponents.count > 3 {
                    style.colorComponents[3] = newValue
                } else {
                    while style.colorComponents.count < 3 { style.colorComponents.append(0) }
                    style.colorComponents.append(newValue)
                }
                updatePreview()
            }
        )
    }

    private var backgroundColorComponents: [CGFloat] {
        let components = style.backgroundColorComponents
        return [
            components.count > 0 ? components[0] : 0,
            components.count > 1 ? components[1] : 0,
            components.count > 2 ? components[2] : 0,
            components.count > 3 ? components[3] : 0.85
        ]
    }

    private var backgroundOpacity: CGFloat {
        backgroundColorComponents[3]
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                let components = backgroundColorComponents
                return Color(
                    red: components[0],
                    green: components[1],
                    blue: components[2],
                    opacity: components[3]
                )
            },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                style.backgroundColorComponents = [
                    CGFloat(resolved.red),
                    CGFloat(resolved.green),
                    CGFloat(resolved.blue),
                    backgroundOpacity
                ]
                updatePreview()
            }
        )
    }

    private var backgroundOpacityBinding: Binding<CGFloat> {
        Binding(
            get: { backgroundOpacity },
            set: { newValue in
                let components = backgroundColorComponents
                style.backgroundColorComponents = [components[0], components[1], components[2], newValue]
                updatePreview()
            }
        )
    }

    private func fittedImageSize(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func constrainedPreviewOffset(
        _ offset: CGSize,
        imageSize: CGSize,
        containerSize: CGSize,
        scale: CGFloat
    ) -> CGSize {
        let horizontalLimit = max(0, (imageSize.width * scale - containerSize.width) / 2)
        let verticalLimit = max(0, (imageSize.height * scale - containerSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -horizontalLimit), horizontalLimit),
            height: min(max(offset.height, -verticalLimit), verticalLimit)
        )
    }

    private func resetPreviewZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            previewZoomScale = 1
            previewZoomStart = 1
            previewOffset = .zero
            previewOffsetStart = .zero
        }
    }

    private func sampleColor(in image: UIImage, at point: CGPoint, containerSize: CGSize) {
        guard isPickingColor,
              let cgImage = image.cgImage,
              let pixels = BitmapContext.pixelBuffer(of: cgImage) else { return }

        let fittedSize = fittedImageSize(image.size, in: containerSize)
        let imageOrigin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )
        let imagePoint = CGPoint(
            x: (point.x - containerSize.width / 2 - previewOffset.width) / previewZoomScale + containerSize.width / 2,
            y: (point.y - containerSize.height / 2 - previewOffset.height) / previewZoomScale + containerSize.height / 2
        )
        let localX = imagePoint.x - imageOrigin.x
        let localY = imagePoint.y - imageOrigin.y
        guard localX >= 0, localX < fittedSize.width,
              localY >= 0, localY < fittedSize.height else { return }

        let x = min(pixels.width - 1, Int(localX / fittedSize.width * CGFloat(pixels.width)))
        let y = min(pixels.height - 1, Int(localY / fittedSize.height * CGFloat(pixels.height)))
        let offset = (y * pixels.width + x) * 4
        style.colorComponents = [
            CGFloat(pixels.pixels[offset]) / 255,
            CGFloat(pixels.pixels[offset + 1]) / 255,
            CGFloat(pixels.pixels[offset + 2]) / 255,
            textOpacity
        ]
        Haptics.selection()
        withAnimation(.easeOut(duration: 0.15)) { isPickingColor = false }
        updatePreview()
    }

    private func updatePreview() {
        saveError = nil
        if viewModel.verificationFailure?.regionID == region.id {
            viewModel.verificationFailure = nil
        }
        previewImage = viewModel.preview(region: region, newText: text, style: style)
    }

    private func applyAutoMatch() {
        guard let autoMatchedStyle else { return }
        Haptics.selection()
        style = FontMatcher.fittingStyle(autoMatchedStyle, to: text, width: region.width)
        updatePreview()
    }
}
