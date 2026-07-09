import Photos
import UIKit

/// Add-only Photos library writes, shared by captured-shot saves and
/// before/after export cards. Never throws to the caller; failures are
/// reported via SaveResult so callers can degrade gracefully (keep the
/// in-app copy, surface a notice) instead of crashing or losing data.
nonisolated struct PhotoLibrarySaver {

    enum SaveResult {
        case saved
        case deniedOrRestricted
        case failed
    }

    static func save(_ image: UIImage) async -> SaveResult {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let resolved: PHAuthorizationStatus
        if status == .notDetermined {
            resolved = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            resolved = status
        }
        guard resolved == .authorized || resolved == .limited else {
            return .deniedOrRestricted
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }
}
