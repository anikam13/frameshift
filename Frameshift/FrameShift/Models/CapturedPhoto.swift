import UIKit

/// A photo the user captured in the camera. Stored in the Library tab.
struct CapturedPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let capturedAt: Date
    let referenceID: UUID?      // the reference that was active, if any
    var isFavorite: Bool

    init(image: UIImage, referenceID: UUID? = nil) {
        self.id = UUID()
        self.image = image
        self.capturedAt = Date()
        self.referenceID = referenceID
        self.isFavorite = false
    }

    /// Rebuilds a persisted shot on launch.
    init(id: UUID, image: UIImage, capturedAt: Date, referenceID: UUID?, isFavorite: Bool) {
        self.id = id
        self.image = image
        self.capturedAt = capturedAt
        self.referenceID = referenceID
        self.isFavorite = isFavorite
    }
}
