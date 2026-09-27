import CoreGraphics
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class PhotoEditorViewModel {

    enum Stage: Equatable {
        case idle
        case detectingText
        case ready
        case analyzingStyle
        case verifying
    }

    private(set) var originalImage: CGImage?
    private(set) var workingImage: CGImage?
    private(set) var regions: [TextRegion] = []
    private(set) var stage: Stage = .idle
    var errorMessage: String?

    var selectedRegionID: UUID?
    var verificationFailure: (regionID: UUID, message: String)?

    private var backgroundPatches: [UUID: BackgroundPatch] = [:]
    private var cachedStyles: [UUID: TextStyle] = [:]
    private(set) var undoStack: [TextEdit] = []
    private(set) var redoStack: [TextEdit] = []
    private var originalRegions: [TextRegion] = []

    var selectedRegion: TextRegion? {
        regions.first { $0.id == selectedRegionID }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Most recent edit first, for a history list UI.
    var editHistory: [TextEdit] { undoStack.reversed() }

    func load(uiImage: UIImage) async {
        guard let cg = normalizedCGImage(from: uiImage) else {
            errorMessage = "Couldn't read the selected photo."
            return
        }
        originalImage = cg
        workingImage = cg
        regions = []
        backgroundPatches = [:]
        cachedStyles = [:]
        undoStack = []
        redoStack = []
        selectedRegionID = nil
        verificationFailure = nil
        errorMessage = nil
        stage = .detectingText

        do {
            regions = try await OCRService.detectText(in: PipelineImage(cgImage: cg))
            originalRegions = regions
        } catch {
            errorMessage = "Text detection failed: \(error.localizedDescription)"
        }
        stage = .ready
    }

    func select(_ region: TextRegion) {
        selectedRegionID = region.id
    }

    /// Runs style analysis + background reconstruction for a region (cached after the first call).
    func prepareEdit(for region: TextRegion) async -> TextStyle? {
        if let cached = cachedStyles[region.id] { return cached }
        guard let working = workingImage else { return nil }

        stage = .analyzingStyle
        defer { stage = .ready }

        let workingBox = PipelineImage(cgImage: working)
        let outcome = await Task.detached(priority: .userInitiated) { () -> (style: TextStyle, patch: BackgroundPatch)? in
            guard let maskResult = MaskGenerator.generate(for: region, in: workingBox.cgImage) else { return nil }
            let style = StyleAnalyzer.analyze(region: region, maskResult: maskResult)
            guard let patch = BackgroundReconstructor.reconstruct(region: region, maskResult: maskResult, in: workingBox.cgImage) else {
                return nil
            }
            return (style, patch)
        }.value

        guard let outcome else { return nil }
        cachedStyles[region.id] = outcome.style
        if backgroundPatches[region.id] == nil {
            backgroundPatches[region.id] = outcome.patch
        }
        return outcome.style
    }

    /// Renders a live preview of `newText`/`style` without committing it.
    func preview(region: TextRegion, newText: String, style: TextStyle) -> UIImage? {
        guard let composited = renderComposite(region: region, newText: newText, style: style) else { return nil }
        return UIImage(cgImage: composited)
    }

    /// Renders, verifies, and — on success — commits the edit. Returns whether it was committed.
    func commitEdit(region: TextRegion, newText: String, style: TextStyle) async -> Bool {
        guard let working = workingImage,
              let patch = backgroundPatches[region.id],
              let composited = renderComposite(region: region, newText: newText, style: style) else {
            return false
        }

        stage = .verifying
        let result = await VerificationService.verify(
            expectedText: newText,
            region: region,
            renderedImage: composited,
            originalImage: working,
            patchRect: patch.patchRect
        )
        stage = .ready

        if result.passed {
            applyCommit(region: region, newText: newText, style: style, composited: composited, before: working)
            verificationFailure = nil
            return true
        } else {
            verificationFailure = (region.id, result.reason ?? "Verification failed.")
            return false
        }
    }

    /// Commits an edit despite a failed verification (user explicitly chose to keep it).
    func acceptAnyway(region: TextRegion, newText: String, style: TextStyle) {
        guard let working = workingImage,
              let composited = renderComposite(region: region, newText: newText, style: style) else { return }
        applyCommit(region: region, newText: newText, style: style, composited: composited, before: working)
        verificationFailure = nil
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(last)
        workingImage = last.beforeImage
        if let idx = regions.firstIndex(where: { $0.id == last.regionID }) {
            regions[idx].text = last.originalText
        }
        // The cached background patch was built against an older working image; drop it so the
        // next edit to this region reconstructs against the restored image.
        backgroundPatches[last.regionID] = nil
        cachedStyles[last.regionID] = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(next)
        workingImage = next.afterImage
        if let idx = regions.firstIndex(where: { $0.id == next.regionID }) {
            regions[idx].text = next.newText
        }
        backgroundPatches[next.regionID] = nil
        cachedStyles[next.regionID] = nil
    }

    /// Returns to the initial (unedited) state of the current photo.
    func revertToOriginal() {
        guard let original = originalImage else { return }
        workingImage = original
        regions = originalRegions
        undoStack = []
        redoStack = []
        backgroundPatches = [:]
        cachedStyles = [:]
        selectedRegionID = nil
        verificationFailure = nil
    }

    /// Clears the loaded photo so the picker reappears.
    func reset() {
        originalImage = nil
        workingImage = nil
        regions = []
        originalRegions = []
        backgroundPatches = [:]
        cachedStyles = [:]
        undoStack = []
        redoStack = []
        selectedRegionID = nil
        verificationFailure = nil
        errorMessage = nil
        stage = .idle
    }

    func exportUIImage() -> UIImage? {
        workingImage.map { UIImage(cgImage: $0) }
    }

    // MARK: - Private

    private func applyCommit(region: TextRegion, newText: String, style: TextStyle, composited: CGImage, before: CGImage) {
        let edit = TextEdit(id: UUID(), regionID: region.id, originalText: region.text, newText: newText, style: style, timestamp: Date(), beforeImage: before, afterImage: composited)
        undoStack.append(edit)
        redoStack.removeAll()
        workingImage = composited
        if let idx = regions.firstIndex(where: { $0.id == region.id }) {
            regions[idx].text = newText
        }
    }

    private func renderComposite(region: TextRegion, newText: String, style: TextStyle) -> CGImage? {
        guard let working = workingImage,
              let patch = backgroundPatches[region.id],
              let rendered = TextRenderer.render(text: newText, style: style, region: region, over: patch) else { return nil }
        return compositeFullImage(base: working, patch: rendered, patchRect: patch.patchRect)
    }

    private func compositeFullImage(base: CGImage, patch: CGImage, patchRect: CGRect) -> CGImage? {
        // Native (unflipped) context: a full-canvas image draw reproduces the source right-side up
        // regardless of y-direction (it covers every row either way), but placing an image at a
        // sub-rect uses the context's native bottom-up y — empirically confirmed: a sub-rect drawn
        // at "y" lands measured up from the bottom, not down from the top. `patchRect` is in
        // top-left-origin pixel coordinates (like the rest of the pipeline), so convert it.
        guard let context = BitmapContext.make(width: base.width, height: base.height) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        let nativeRect = CGRect(
            x: patchRect.origin.x,
            y: CGFloat(base.height) - patchRect.origin.y - patchRect.height,
            width: patchRect.width,
            height: patchRect.height
        )
        context.draw(patch, in: nativeRect)
        return context.makeImage()
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let upright = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        return upright.cgImage
    }
}
