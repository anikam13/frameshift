import UIKit

struct ReferencePhoto: Identifiable {
    let id: UUID
    let image: UIImage
    var spec: ShotSpec?
    /// Person-only cutout (transparent background) for the ghost overlay.
    /// Display-sized in RAM; PNG on disk beside the original import bytes.
    var personCutout: UIImage?
    /// True when analysis completed but found no person/face — a terminal
    /// state distinct from "still analyzing" (spec == nil). Persisted with
    /// `analyzerVersion` so cold start does not re-run Vision.
    var analysisFailed: Bool = false
    let importedAt: Date

    init(image: UIImage) {
        self.id = UUID()
        self.image = image
        self.spec = nil
        self.personCutout = nil
        self.importedAt = Date()
    }

    /// Rebuilds a persisted reference on launch (image + cached analysis).
    init(
        id: UUID,
        image: UIImage,
        importedAt: Date,
        spec: ShotSpec? = nil,
        personCutout: UIImage? = nil,
        analysisFailed: Bool = false
    ) {
        self.id = id
        self.image = image
        self.spec = spec
        self.personCutout = personCutout
        self.analysisFailed = analysisFailed
        self.importedAt = importedAt
    }
}
