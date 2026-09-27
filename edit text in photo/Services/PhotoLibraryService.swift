import Photos
import UIKit

enum PhotoLibraryService {
    enum SaveError: LocalizedError {
        case notAuthorized
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Photo library access wasn't granted. Enable it in Settings to save edited photos."
            case .saveFailed(let error):
                return error.localizedDescription
            }
        }
    }

    nonisolated static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.notAuthorized
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            throw SaveError.saveFailed(error)
        }
    }
}
