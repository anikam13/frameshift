import UIKit

/// A photo captured in the current session. Display-sized in memory; the
/// full JPEG is in Apple Photos plus a `SessionCaptureCache` copy while the session is open.
struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let capturedAt: Date
    let referenceID: UUID?      // the reference that was active, if any
    /// Shots captured in one shutter hold share a burstID; nil for singles.
    let burstID: UUID?
    /// User-picked best shot of its burst — the group's cover in the session grid.
    var isBurstBest: Bool
    /// Photos `localIdentifier` once the add-only save lands — what Delete
    /// removes from the camera roll. nil while the save is pending/failed.
    var photosAssetID: String?

    init(image: UIImage, referenceID: UUID? = nil, burstID: UUID? = nil) {
        self.id = UUID()
        self.image = image
        self.capturedAt = Date()
        self.referenceID = referenceID
        self.burstID = burstID
        self.isBurstBest = false
    }

    /// Rebuilds a shot from the session cache after relaunch.
    init(id: UUID, image: UIImage, capturedAt: Date, referenceID: UUID?, burstID: UUID?, isBurstBest: Bool, photosAssetID: String? = nil) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
        self.referenceID = referenceID
        self.burstID = burstID
        self.isBurstBest = isBurstBest
        self.photosAssetID = photosAssetID
    }
}
