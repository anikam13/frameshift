import UIKit

/// A photo the user captured in the camera. Stored in the Library tab.
struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let capturedAt: Date
    let referenceID: UUID?      // the reference that was active, if any
    var isFavorite: Bool
    /// Shots captured in one shutter hold share a burstID; nil for singles.
    let burstID: UUID?
    /// User-picked best shot of its burst — the group's cover in the gallery.
    var isBurstBest: Bool

    init(image: UIImage, referenceID: UUID? = nil, burstID: UUID? = nil) {
        self.id = UUID()
        self.image = image
        self.capturedAt = Date()
        self.referenceID = referenceID
        self.isFavorite = false
        self.burstID = burstID
        self.isBurstBest = false
    }

    /// Rebuilds a persisted shot on launch.
    init(
        id: UUID, image: UIImage, capturedAt: Date, referenceID: UUID?,
        isFavorite: Bool, burstID: UUID?, isBurstBest: Bool
    ) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
        self.referenceID = referenceID
        self.isFavorite = isFavorite
        self.burstID = burstID
        self.isBurstBest = isBurstBest
    }
}
