import Photos
import UIKit

enum PhotoLibraryService {
    enum SaveError: LocalizedError {
        case notAuthorized
        case restricted
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Photo access is off for this app. Allow Retouch to add photos in Settings."
            case .restricted:
                return "Saving photos is restricted on this device."
            case .saveFailed(let error):
                return error.localizedDescription
            }
        }
    }

    nonisolated static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        switch status {
        case .authorized, .limited:
            break
        case .restricted:
            throw SaveError.restricted
        case .denied, .notDetermined:
            throw SaveError.notAuthorized
        @unknown default:
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
