import Photos
import Foundation

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "EyeLine doesn't have permission to save to your Photos library."
        case .saveFailed(let error):
            return "Couldn't save the video: \(error.localizedDescription)"
        }
    }
}

/// Saves finished recordings to the user's Photos library. Requests
/// add-only access — this app never needs to read the existing library.
enum PhotoLibraryService {

    static func requestAuthorizationIfNeeded() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    static func save(videoAt url: URL) async throws {
        guard await requestAuthorizationIfNeeded() else {
            throw PhotoLibraryError.notAuthorized
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .video, fileURL: url, options: options)
            }
        } catch {
            throw PhotoLibraryError.saveFailed(error)
        }
    }
}
