import CoreGraphics
import Vision

/// Two-pass Vision text detection: a whole-image pass for coarse geometry, then a crop+upscale
/// re-OCR pass for regions that came back low-confidence or too small to read reliably, keeping
/// whichever pass produced higher confidence for a given region.
enum OCRService {

    struct Config {
        var recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate
        var upscaleFactor: CGFloat = 3.0
        var cropPadding: CGFloat = 0.2
        var rerunConfidenceThreshold: Float = 0.7
        var rerunMinHeightFraction: CGFloat = 0.05
        var minimumTextHeightFraction: Float = 0.01

        nonisolated init(
            recognitionLevel: RecognizeTextRequest.RecognitionLevel = .accurate,
            upscaleFactor: CGFloat = 3.0,
            cropPadding: CGFloat = 0.2,
            rerunConfidenceThreshold: Float = 0.7,
            rerunMinHeightFraction: CGFloat = 0.05,
            minimumTextHeightFraction: Float = 0.01
        ) {
            self.recognitionLevel = recognitionLevel
            self.upscaleFactor = upscaleFactor
            self.cropPadding = cropPadding
            self.rerunConfidenceThreshold = rerunConfidenceThreshold
            self.rerunMinHeightFraction = rerunMinHeightFraction
            self.minimumTextHeightFraction = minimumTextHeightFraction
        }
    }

    enum OCRError: Error {
        case invalidImage
    }

    nonisolated static func detectText(in image: PipelineImage, config: Config = Config()) async throws -> [TextRegion] {
        let cgImage = image.cgImage
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard imageSize.width > 0, imageSize.height > 0 else { throw OCRError.invalidImage }

        let wholeImageRegions = try await recognize(cgImage: cgImage, config: config)

        var refined: [TextRegion] = []
        refined.reserveCapacity(wholeImageRegions.count)
        for region in wholeImageRegions {
            let looksUnreliable = region.confidence < config.rerunConfidenceThreshold
                || region.lineHeight < imageSize.height * config.rerunMinHeightFraction
            if looksUnreliable, let improved = try? await reOCR(region: region, in: cgImage, config: config) {
                refined.append(improved.confidence > region.confidence ? improved : region)
            } else {
                refined.append(region)
            }
        }
        return refined
    }

    nonisolated private static func recognize(cgImage: CGImage, config: Config) async throws -> [TextRegion] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = config.recognitionLevel
        request.minimumTextHeightFraction = config.minimumTextHeightFraction
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: cgImage)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        return observations.compactMap { TextRegion(observation: $0, imageSize: imageSize) }
    }

    nonisolated private static func reOCR(region: TextRegion, in cgImage: CGImage, config: Config) async throws -> TextRegion? {
        let bbox = region.boundingBox
        let paddedWidth = bbox.width * (1 + 2 * config.cropPadding)
        let paddedHeight = bbox.height * (1 + 2 * config.cropPadding)
        let padded = CGRect(
            x: bbox.midX - paddedWidth / 2,
            y: bbox.midY - paddedHeight / 2,
            width: paddedWidth,
            height: paddedHeight
        )
        guard let cropped = cgImage.cropped(to: padded), let upscaled = cropped.scaled(by: config.upscaleFactor) else {
            return nil
        }
        // Re-derive the *actual* crop origin used (cropping clamps to image bounds).
        let actualCropOrigin = padded.integral.intersection(cgImage.pixelBounds).origin

        let cropRegions = try await recognize(cgImage: upscaled, config: config)
        guard let best = cropRegions.max(by: { $0.confidence < $1.confidence }) else { return nil }

        let scale = 1.0 / config.upscaleFactor
        func mapPoint(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * scale + actualCropOrigin.x, y: p.y * scale + actualCropOrigin.y)
        }

        var mapped = best
        mapped.topLeft = mapPoint(best.topLeft)
        mapped.topRight = mapPoint(best.topRight)
        mapped.bottomRight = mapPoint(best.bottomRight)
        mapped.bottomLeft = mapPoint(best.bottomLeft)
        mapped.characterBoxes = best.characterBoxes.map { rect in
            CGRect(origin: mapPoint(rect.origin), size: CGSize(width: rect.width * scale, height: rect.height * scale))
        }
        return mapped
    }
}

extension TextRegion {
    /// Builds a region from a Vision observation, converting Vision's normalized bottom-left-origin
    /// coordinates to top-left-origin pixel coordinates per corner (not just the bounding box), so
    /// rotated/keystoned text keeps its real shape.
    nonisolated init?(observation: RecognizedTextObservation, imageSize: CGSize) {
        guard let candidate = observation.topCandidates(1).first else { return nil }

        func convert(_ p: NormalizedPoint) -> CGPoint {
            p.toImageCoordinates(imageSize, origin: .upperLeft)
        }

        var charBoxes: [CGRect] = []
        let string = candidate.string
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(after: index)
            if let rect = candidate.boundingBox(for: index..<next) {
                let corners = [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft].map(convert)
                charBoxes.append(Geometry.boundingBox(of: corners))
            }
            index = next
        }

        self.init(
            text: candidate.string,
            confidence: candidate.confidence,
            topLeft: convert(observation.topLeft),
            topRight: convert(observation.topRight),
            bottomRight: convert(observation.bottomRight),
            bottomLeft: convert(observation.bottomLeft),
            characterBoxes: charBoxes
        )
    }
}
