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
    private var autoMatchStyles: [UUID: TextStyle] = [:]
    private(set) var undoStack: [TextEdit] = []
    private(set) var redoStack: [TextEdit] = []
    private var originalRegions: [TextRegion] = []
    /// Invalidates in-flight OCR and rendering work when the active photo or its pixels change.
    private var imageRevision = 0

    var selectedRegion: TextRegion? {
        regions.first { $0.id == selectedRegionID }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Most recent edit first, for a history list UI.
    var editHistory: [TextEdit] { undoStack.reversed() }

    func load(uiImage: UIImage) async {
        imageRevision += 1
        let revision = imageRevision
        guard let cg = normalizedCGImage(from: uiImage) else {
            errorMessage = "Couldn't read the selected photo."
            stage = workingImage == nil ? .idle : .ready
            return
        }
        originalImage = cg
        workingImage = cg
        regions = []
        originalRegions = []
        backgroundPatches = [:]
        cachedStyles = [:]
        autoMatchStyles = [:]
        undoStack = []
        redoStack = []
        selectedRegionID = nil
        verificationFailure = nil
        errorMessage = nil
        stage = .detectingText

        do {
            let detectedRegions = try await OCRService.detectText(in: PipelineImage(cgImage: cg))
            guard imageRevision == revision else { return }
            regions = detectedRegions
            originalRegions = detectedRegions
        } catch {
            guard imageRevision == revision else { return }
            errorMessage = "Text detection failed: \(error.localizedDescription)"
        }
        if imageRevision == revision {
            stage = .ready
        }
    }

    func select(_ region: TextRegion) {
        selectedRegionID = region.id
    }

    /// Scans the original photo again and adds detections that aren't already represented.
    /// Using the source image avoids mistaking replacement text for a newly discovered region.
    func detectAdditionalText() async throws -> Int {
        guard stage == .ready, let originalImage else { return 0 }
        let revision = imageRevision
        stage = .detectingText
        defer {
            if imageRevision == revision, stage == .detectingText {
                stage = .ready
            }
        }

        let detections = try await OCRService.detectText(in: PipelineImage(cgImage: originalImage))
        guard imageRevision == revision, stage == .detectingText else { return 0 }
        var additions: [TextRegion] = []
        for detection in detections {
            guard !regions.contains(where: { substantiallyOverlaps($0.boundingBox, detection.boundingBox) }),
                  !additions.contains(where: { substantiallyOverlaps($0.boundingBox, detection.boundingBox) }) else {
                continue
            }
            additions.append(detection)
        }

        regions.append(contentsOf: additions)
        originalRegions.append(contentsOf: additions)
        errorMessage = nil
        return additions.count
    }

    /// Adds a user-drawn region so text that OCR missed can still be edited or replaced.
    @discardableResult
    func addManualRegion(in rect: CGRect) -> TextRegion? {
        guard let image = workingImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let selection = rect.standardized.intersection(bounds).integral
        guard selection.width >= 8, selection.height >= 8 else { return nil }

        let region = TextRegion(
            text: "",
            confidence: 1,
            topLeft: selection.origin,
            topRight: CGPoint(x: selection.maxX, y: selection.minY),
            bottomRight: CGPoint(x: selection.maxX, y: selection.maxY),
            bottomLeft: CGPoint(x: selection.minX, y: selection.maxY)
        )
        regions.append(region)
        selectedRegionID = region.id
        return region
    }

    func removeRegionIfEmpty(_ regionID: UUID) {
        guard let index = regions.firstIndex(where: { $0.id == regionID }), regions[index].text.isEmpty else { return }
        regions.remove(at: index)
        if selectedRegionID == regionID { selectedRegionID = nil }
    }

    /// Runs style analysis + background reconstruction for a region (cached after the first call).
    func prepareEdit(for region: TextRegion) async -> TextStyle? {
        guard stage == .ready else { return nil }
        if let cached = cachedStyles[region.id], backgroundPatches[region.id] != nil {
            if autoMatchStyles[region.id] == nil {
                autoMatchStyles[region.id] = cached
            }
            return cached
        }
        guard let working = workingImage else { return nil }

        let revision = imageRevision
        stage = .analyzingStyle
        defer {
            if imageRevision == revision, stage == .analyzingStyle {
                stage = .ready
            }
        }

        let workingBox = PipelineImage(cgImage: working)
        let outcome = await Task.detached(priority: .userInitiated) { () -> (style: TextStyle, patch: BackgroundPatch)? in
            guard let maskResult = MaskGenerator.generate(for: region, in: workingBox.cgImage) else { return nil }
            let style = StyleAnalyzer.analyze(region: region, maskResult: maskResult)
            guard let patch = BackgroundReconstructor.reconstruct(region: region, maskResult: maskResult, in: workingBox.cgImage) else {
                return nil
            }
            return (style, patch)
        }.value

        guard imageRevision == revision,
              stage == .analyzingStyle,
              let outcome else { return nil }
        cachedStyles[region.id] = outcome.style
        if autoMatchStyles[region.id] == nil {
            autoMatchStyles[region.id] = outcome.style
        }
        if backgroundPatches[region.id] == nil {
            backgroundPatches[region.id] = outcome.patch
        }
        return outcome.style
    }

    /// Returns the first detected style for a region so users can restore the photo's original look.
    func autoMatchedStyle(for region: TextRegion) async -> TextStyle? {
        if let style = autoMatchStyles[region.id] { return style }
        return await prepareEdit(for: region)
    }

    /// Renders a live preview of `newText`/`style` without committing it.
    func preview(region: TextRegion, newText: String, style: TextStyle) -> UIImage? {
        guard let composited = renderComposite(region: region, newText: newText, style: style) else { return nil }
        return makePreviewImage(from: composited, maxDimension: 1200)
    }

    /// Renders, verifies, and — on success — commits the edit. Returns whether it was committed.
    func commitEdit(region: TextRegion, newText: String, style: TextStyle) async -> Bool {
        guard stage == .ready,
              let working = workingImage,
              let patch = backgroundPatches[region.id],
              let composited = renderComposite(region: region, newText: newText, style: style) else {
            return false
        }

        let revision = imageRevision
        verificationFailure = nil
        stage = .verifying
        let result = await VerificationService.verify(
            expectedText: newText,
            region: region,
            renderedImage: composited,
            originalImage: working,
            patchRect: patch.patchRect,
            textOpacity: style.colorComponents.count > 3 ? style.colorComponents[3] : 1
        )
        guard imageRevision == revision, stage == .verifying else { return false }
        stage = .ready

        if result.passed {
            guard applyCommit(
                region: region,
                newText: newText,
                style: style,
                composited: composited,
                before: working,
                patchRect: patch.patchRect
            ) else {
                return false
            }
            verificationFailure = nil
            return true
        } else {
            verificationFailure = (region.id, result.reason ?? "Verification failed.")
            return false
        }
    }

    /// Commits an edit despite a failed verification (user explicitly chose to keep it).
    @discardableResult
    func acceptAnyway(region: TextRegion, newText: String, style: TextStyle) -> Bool {
        guard stage == .ready,
              let working = workingImage,
              let patch = backgroundPatches[region.id],
              let composited = renderComposite(region: region, newText: newText, style: style) else { return false }
        guard applyCommit(
            region: region,
            newText: newText,
            style: style,
            composited: composited,
            before: working,
            patchRect: patch.patchRect
        ) else { return false }
        verificationFailure = nil
        return true
    }

    /// Removes the selected text while preserving the reconstructed background as an undoable edit.
    func erase(region: TextRegion) async -> Bool {
        guard stage == .ready, !region.isHidden else { return false }
        let revision = imageRevision
        if backgroundPatches[region.id] == nil {
            guard await prepareEdit(for: region) != nil else { return false }
        }
        guard imageRevision == revision,
              stage == .ready,
              let working = workingImage,
              let patch = backgroundPatches[region.id],
              let composited = compositeFullImage(base: working, patch: patch.patch, patchRect: patch.patchRect) else {
            return false
        }

        guard applyCommit(
            region: region,
            newText: "",
            style: cachedStyles[region.id] ?? .default,
            composited: composited,
            before: working,
            patchRect: patch.patchRect,
            hiddenAfter: true
        ) else { return false }
        selectedRegionID = nil
        verificationFailure = nil
        return true
    }

    func undo() {
        guard stage == .ready,
              let last = undoStack.last,
              let working = workingImage,
              let restored = compositeFullImage(base: working, patch: last.beforePatch, patchRect: last.patchRect) else { return }
        undoStack.removeLast()
        redoStack.append(last)
        workingImage = restored
        imageRevision += 1
        if let idx = regions.firstIndex(where: { $0.id == last.regionID }) {
            regions[idx].text = last.originalText
            regions[idx].isHidden = last.originalHidden
        }
        invalidateWorkingImageCaches()
    }

    func redo() {
        guard stage == .ready,
              let next = redoStack.last,
              let working = workingImage,
              let restored = compositeFullImage(base: working, patch: next.afterPatch, patchRect: next.patchRect) else { return }
        redoStack.removeLast()
        undoStack.append(next)
        workingImage = restored
        imageRevision += 1
        if let idx = regions.firstIndex(where: { $0.id == next.regionID }) {
            regions[idx].text = next.newText
            regions[idx].isHidden = next.newHidden
        }
        invalidateWorkingImageCaches()
    }

    /// Returns to the initial (unedited) state of the current photo.
    func revertToOriginal() {
        guard let original = originalImage else { return }
        imageRevision += 1
        workingImage = original
        regions = originalRegions
        undoStack = []
        redoStack = []
        backgroundPatches = [:]
        cachedStyles = [:]
        autoMatchStyles = [:]
        selectedRegionID = nil
        verificationFailure = nil
        stage = .ready
    }

    /// Clears the loaded photo so the picker reappears.
    func reset() {
        imageRevision += 1
        originalImage = nil
        workingImage = nil
        regions = []
        originalRegions = []
        backgroundPatches = [:]
        cachedStyles = [:]
        autoMatchStyles = [:]
        undoStack = []
        redoStack = []
        selectedRegionID = nil
        verificationFailure = nil
        errorMessage = nil
        stage = .idle
    }

    func exportUIImage() -> UIImage? {
        workingImage.map { UIImage(cgImage: $0, scale: 1, orientation: .up) }
    }

    // MARK: - Private

    @discardableResult
    private func applyCommit(
        region: TextRegion,
        newText: String,
        style: TextStyle,
        composited: CGImage,
        before: CGImage,
        patchRect: CGRect,
        hiddenAfter: Bool = false
    ) -> Bool {
        guard let beforePatch = before.copiedCrop(to: patchRect),
              let afterPatch = composited.copiedCrop(to: patchRect) else { return false }

        let edit = TextEdit(
            id: UUID(),
            regionID: region.id,
            originalText: region.text,
            newText: newText,
            originalHidden: region.isHidden,
            newHidden: hiddenAfter,
            style: style,
            timestamp: Date(),
            patchRect: patchRect,
            beforePatch: beforePatch,
            afterPatch: afterPatch
        )
        undoStack.append(edit)
        redoStack.removeAll()
        workingImage = composited
        imageRevision += 1
        if let idx = regions.firstIndex(where: { $0.id == region.id }) {
            regions[idx].text = newText
            regions[idx].isHidden = hiddenAfter
        }
        // Any cached patch can overlap this change, so reconstruct against the new working image
        // the next time a region is opened. The first-pass auto match remains in its own cache.
        invalidateWorkingImageCaches()
        return true
    }

    private func invalidateWorkingImageCaches() {
        backgroundPatches.removeAll(keepingCapacity: true)
        cachedStyles.removeAll(keepingCapacity: true)
    }

    private func renderComposite(region: TextRegion, newText: String, style: TextStyle) -> CGImage? {
        guard let working = workingImage,
              let patch = backgroundPatches[region.id],
              let rendered = TextRenderer.render(text: newText, style: style, region: region, over: patch) else { return nil }
        return compositeFullImage(base: working, patch: rendered, patchRect: patch.patchRect)
    }

    private func substantiallyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return false }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return false }
        return intersection.width * intersection.height / smallerArea >= 0.65
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

    private func makePreviewImage(from image: CGImage, maxDimension: CGFloat) -> UIImage? {
        let source = UIImage(cgImage: image)
        let largestDimension = max(source.size.width, source.size.height)
        guard largestDimension > maxDimension else { return source }

        let scale = maxDimension / largestDimension
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
