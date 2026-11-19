import Photos
import UIKit

/// Photos library writes for captured shots. Saving is add-only; deleting
/// asks for read/write access the first time the user deletes (1.3), and
/// only ever touches assets FrameShift itself created (by stored
/// localIdentifier). Never throws to the caller; failures come back as
/// results so callers can degrade gracefully.
nonisolated struct PhotoLibrarySaver {

    enum SaveResult {
        /// `assetID` is the new asset's localIdentifier (used by Delete).
        case saved(assetID: String?)
        case deniedOrRestricted
        case failed
    }

    enum DeleteResult {
        case deleted
        /// The user declined the system "Allow FrameShift to delete…" alert.
        case cancelled
        case deniedOrRestricted
        case failed
    }

    /// The placeholder's id is assigned inside the change block.
    private final class AssetIDBox: @unchecked Sendable { var id: String? }

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
        let box = AssetIDBox()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
                box.id = request.placeholderForCreatedAsset?.localIdentifier
            }
            return .saved(assetID: box.id)
        } catch {
            return .failed
        }
    }

    /// Deletes FrameShift's own captures from the camera roll. iOS shows its
    /// own confirmation and moves them to Recently Deleted (30 days). With
    /// limited library access, assets this app created stay accessible.
    static func deleteAssets(localIdentifiers ids: [String]) async -> DeleteResult {
        guard !ids.isEmpty else { return .deleted }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else {
            return .deniedOrRestricted
        }
        nonisolated(unsafe) let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        // Already removed in the Photos app — nothing left to delete there.
        guard assets.count > 0 else { return .deleted }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            return .deleted
        } catch let error as NSError
            where error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.userCancelled.rawValue {
            return .cancelled
        } catch {
            return .failed
        }
    }
}
