import UIKit

struct ReferencePhoto: Identifiable {
    let id: UUID
    let image: UIImage
    var spec: ShotSpec?
    /// Person-only cutout (transparent background) for the ghost overlay.
    /// Computed alongside spec; in memory only, never serialized.
    var personCutout: UIImage?
    /// True when analysis completed but found no person/face — a terminal
    /// state distinct from "still analyzing" (spec == nil). Not persisted;
    /// recomputed each launch like spec.
    var analysisFailed: Bool = false
    let importedAt: Date

    init(image: UIImage) {
        self.id = UUID()
        self.image = image
        self.spec = nil
        self.personCutout = nil
        self.importedAt = Date()
    }

    /// Rebuilds a persisted reference on launch; spec is recomputed separately.
    init(id: UUID, image: UIImage, importedAt: Date) {
        self.id = id
        self.image = image
        self.spec = nil
        self.personCutout = nil
        self.importedAt = importedAt
    }
}
