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
    /// Asset catalog name when this came from `SampleReferencePack`, so
    /// onboarding / "Add samples" can skip photos already in the library.
    var bundledAssetName: String?
    let importedAt: Date
    /// User-starred; leads the quick-access row and camera picker.
    var isFavorite: Bool = false
    /// Times this reference was made active in the camera. Ranks "recent".
    var useCount: Int = 0
    var lastUsedAt: Date?

    init(image: UIImage, bundledAssetName: String? = nil) {
        self.id = UUID()
        self.image = image
        self.spec = nil
        self.personCutout = nil
        self.bundledAssetName = bundledAssetName
        self.importedAt = Date()
    }

    /// Rebuilds a persisted reference on launch (image + cached analysis).
    init(
        id: UUID,
        image: UIImage,
        importedAt: Date,
        spec: ShotSpec? = nil,
        personCutout: UIImage? = nil,
        analysisFailed: Bool = false,
        bundledAssetName: String? = nil,
        isFavorite: Bool = false,
        useCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.image = image
        self.spec = spec
        self.personCutout = personCutout
        self.analysisFailed = analysisFailed
        self.bundledAssetName = bundledAssetName
        self.importedAt = importedAt
        self.isFavorite = isFavorite
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
    }

    /// Curated (bundled) photos belong to Explore; everything else to Yours.
    var isCurated: Bool { bundledAssetName != nil }
}
