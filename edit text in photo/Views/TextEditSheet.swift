import SwiftUI

struct TextEditSheet: View {
    var viewModel: PhotoEditorViewModel
    let region: TextRegion

    @State private var text: String
    @State private var style: TextStyle = .default
    @State private var isPreparing = true
    @State private var isSaving = false
    @State private var previewImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFieldFocused: Bool

    init(viewModel: PhotoEditorViewModel, region: TextRegion) {
        self.viewModel = viewModel
        self.region = region
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
                    }

                    if isPreparing {
                        preparingCard
                    } else {
                        fontCard
                        sizingCard
                        colorCard
                    }
                }
                .padding(Theme.spacingM)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Haptics.mediumTap()
                        Task {
                            isSaving = true
                            let committed = await viewModel.commitEdit(region: region, newText: text, style: style)
                            isSaving = false
                            if committed {
                                Haptics.success()
                                dismiss()
                            } else {
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if let analyzed = await viewModel.prepareEdit(for: region) {
                style = analyzed
            }
            withAnimation(.easeOut(duration: 0.25)) { isPreparing = false }
            updatePreview()
        }
    }

    // MARK: - Sections

    private func previewCard(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            sectionLabel("Preview", icon: "eye.fill")
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
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
        }
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
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(width: 52, height: 44)
                .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)))
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
        }
    }

    private var sizingCard: some View {
        card {
            sectionLabel("Size & Spacing", icon: "arrow.up.and.down.text.horizontal")

            sliderRow(icon: "textformat.size", value: $style.pointSize, range: 6...120, step: 1, displayValue: "\(Int(style.pointSize))")
            sliderRow(icon: "arrow.left.and.right", value: $style.tracking, range: -5...20, step: 0.5, displayValue: String(format: "%.1f", style.tracking))

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
                            .foregroundStyle(isSelected ? .white : .primary)
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

    private func sliderRow(icon: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, step: CGFloat, displayValue: String) -> some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Slider(value: value, in: range, step: step)
                .tint(Theme.accent)
                .onChange(of: value.wrappedValue) { _, _ in updatePreview() }
            Text(displayValue)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var colorCard: some View {
        card {
            sectionLabel("Color", icon: "paintpalette.fill")
            HStack(spacing: Theme.spacingS) {
                ForEach(presetColors, id: \.self) { preset in
                    swatch(preset)
                }
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 34, height: 34)
            }
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
                .textCase(.uppercase)
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
                    blue: c.count > 2 ? c[2] : 0
                )
            },
            set: { newColor in
                let resolved = newColor.resolve(in: EnvironmentValues())
                style.colorComponents = [CGFloat(resolved.red), CGFloat(resolved.green), CGFloat(resolved.blue), 1.0]
                updatePreview()
            }
        )
    }

    private func updatePreview() {
        previewImage = viewModel.preview(region: region, newText: text, style: style)
    }
}
