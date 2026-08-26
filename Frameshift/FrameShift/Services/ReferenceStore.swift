import UIKit

/// Persists imported reference images, cached ShotSpecs / analysisFailed,
/// and display-sized person cutouts so cold launch skips Vision when
/// `ShotSpec.analyzerVersion` still matches.
/// nonisolated: the project defaults to MainActor isolation, but this
/// store's file I/O runs on background tasks.
nonisolated struct ReferenceStore {

    struct Manifest: Codable {
        struct Entry: Codable {
            let id: UUID
            let importedAt: Date
            /// `ShotSpec.analyzerVersion` at the time of analysis. Missing or
            /// mismatched → reanalyze once on restore.
            var analyzerVersion: Int?
            var analysisFailed: Bool?
            var spec: ShotSpec?

            private enum CodingKeys: String, CodingKey {
                case id, importedAt, analyzerVersion, analysisFailed, spec
            }

            init(
                id: UUID,
                importedAt: Date,
                analyzerVersion: Int? = nil,
                analysisFailed: Bool? = nil,
                spec: ShotSpec? = nil
            ) {
                self.id = id
                self.importedAt = importedAt
                self.analyzerVersion = analyzerVersion
                self.analysisFailed = analysisFailed
                self.spec = spec
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(UUID.self, forKey: .id)
                importedAt = try c.decode(Date.self, forKey: .importedAt)
                analyzerVersion = try c.decodeIfPresent(Int.self, forKey: .analyzerVersion)
                analysisFailed = try c.decodeIfPresent(Bool.self, forKey: .analysisFailed)
                // A single stale/partial ShotSpec must not fail the whole
                // library decode (that used to wipe references from memory).
                if c.contains(.spec), try c.decodeNil(forKey: .spec) == false {
                    spec = try? c.decode(ShotSpec.self, forKey: .spec)
                } else {
                    spec = nil
                }
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .id)
                try c.encode(importedAt, forKey: .importedAt)
                try c.encodeIfPresent(analyzerVersion, forKey: .analyzerVersion)
                try c.encodeIfPresent(analysisFailed, forKey: .analysisFailed)
                try c.encodeIfPresent(spec, forKey: .spec)
            }
        }
        var activeReferenceID: UUID?
        var references: [Entry]   // index 0 = newest, matches AppState order
    }

    struct RestoredReference {
        let id: UUID
        let importedAt: Date
        /// Display-sized decode for AppState / UI. Full bytes stay on disk.
        let image: UIImage
        let spec: ShotSpec?
        let analysisFailed: Bool
        /// True when cached analysis is missing or version-stale.
        let needsAnalysis: Bool
        /// Cutout PNG exists on disk — load via `loadCutout` when needed.
        let hasCutoutOnDisk: Bool
    }

    private let directory: URL

    private var manifestURL: URL {
        directory.appendingPathComponent("references.json")
    }

    init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        directory = base.appendingPathComponent("References", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // Original imported bytes, format untouched (JPEG/HEIC/PNG), so re-analysis
    // on restore sees the same EXIF the import-time analysis did.
    private func imageURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
    }

    /// Display-sized PNG with alpha for the camera ghost overlay.
    private func cutoutURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).cutout.png")
    }

    @discardableResult
    func saveImageData(_ data: Data, id: UUID) -> Bool {
        (try? data.write(to: imageURL(for: id), options: .atomic)) != nil
    }

    @discardableResult
    func saveCutout(_ image: UIImage, id: UUID) -> Bool {
        guard let data = image.pngData() else { return false }
        return (try? data.write(to: cutoutURL(for: id), options: .atomic)) != nil
    }

    func deleteCutout(id: UUID) {
        try? FileManager.default.removeItem(at: cutoutURL(for: id))
    }

    /// Removes original bytes, cutout, and leaves the caller to rewrite the manifest.
    func deleteImage(id: UUID) {
        try? FileManager.default.removeItem(at: imageURL(for: id))
        deleteCutout(id: id)
    }

    @discardableResult
    func saveManifest(_ manifest: Manifest) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(manifest) else { return false }
        return (try? data.write(to: manifestURL, options: .atomic)) != nil
    }

    /// Reads the manifest, display images, and cached specs. Cutouts are not
    /// decoded here — call `loadCutout` for the active ghost overlay only.
    /// Entries whose image file is missing or unreadable are dropped.
    /// Call off the main thread.
    func loadAll() -> (references: [RestoredReference], activeID: UUID?) {
        guard let data = try? Data(contentsOf: manifestURL) else { return ([], nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return ([], nil) }

        let currentVersion = ShotSpec.analyzerVersion
        let references = manifest.references.compactMap { entry -> RestoredReference? in
            guard let imageData = try? Data(contentsOf: imageURL(for: entry.id)) else { return nil }
            let image = UIImage.downsampled(
                data: imageData,
                maxPixelSize: UIImage.displayMaxPixelSize
            ) ?? UIImage(data: imageData)?.upright()
            guard let image else { return nil }

            // Version mismatch or resilient-decode nil → drop cached spec.
            let versionOK = entry.analyzerVersion == currentVersion
            let failed = versionOK && (entry.analysisFailed == true)
            let spec = versionOK && !failed ? entry.spec : nil
            // Terminal states: usable spec, or recorded analysisFailed.
            let needsAnalysis = !failed && spec == nil

            let hasCutout = FileManager.default.fileExists(atPath: cutoutURL(for: entry.id).path)

            return RestoredReference(
                id: entry.id,
                importedAt: entry.importedAt,
                image: image,
                spec: spec,
                analysisFailed: failed,
                needsAnalysis: needsAnalysis,
                hasCutoutOnDisk: hasCutout && !needsAnalysis && !failed
            )
        }
        return (references, manifest.activeReferenceID)
    }

    /// Display-sized ghost cutout for one reference. Call off the main thread.
    func loadCutout(id: UUID) -> UIImage? {
        guard let cutoutData = try? Data(contentsOf: cutoutURL(for: id)) else { return nil }
        return UIImage.downsampled(
            data: cutoutData,
            maxPixelSize: UIImage.overlayMaxPixelSize
        ) ?? UIImage(data: cutoutData)
    }

    /// Full-resolution upright decode for one-shot Vision / cutout work.
    /// Prefer over keeping full bitmaps in AppState.
    func loadFullImage(id: UUID) -> (image: UIImage, data: Data)? {
        guard
            let imageData = try? Data(contentsOf: imageURL(for: id)),
            let raw = UIImage(data: imageData)
        else { return nil }
        return (raw.upright(), imageData)
    }

    /// Approximate on-disk size for Settings' storage display. Call off the main thread.
    func totalSizeBytes() -> Int64 {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return contents.reduce(into: Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
    }
}
