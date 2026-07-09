import UIKit

/// Persists imported reference images and their ordering to Application
/// Support so references survive relaunch. ShotSpecs are never serialized —
/// they are recomputed by VisionAnalyzer on load (see ShotSpec.swift).
/// nonisolated: the project defaults to MainActor isolation, but this
/// store's file I/O runs on background tasks.
nonisolated struct ReferenceStore {

    struct Manifest: Codable {
        struct Entry: Codable {
            let id: UUID
            let importedAt: Date
        }
        var activeReferenceID: UUID?
        var references: [Entry]   // index 0 = newest, matches AppState order
    }

    struct RestoredReference {
        let id: UUID
        let importedAt: Date
        /// Display-sized decode for AppState / UI. Full bytes stay on disk.
        let image: UIImage
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

    @discardableResult
    func saveImageData(_ data: Data, id: UUID) -> Bool {
        (try? data.write(to: imageURL(for: id), options: .atomic)) != nil
    }

    func deleteImage(id: UUID) {
        try? FileManager.default.removeItem(at: imageURL(for: id))
    }

    @discardableResult
    func saveManifest(_ manifest: Manifest) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(manifest) else { return false }
        return (try? data.write(to: manifestURL, options: .atomic)) != nil
    }

    /// Reads the manifest and image files. Entries whose image file is
    /// missing or unreadable are dropped. Call off the main thread.
    /// Images are ImageIO-downsampled for display; full bytes stay on disk
    /// and are loaded via `loadFullImage` for Vision re-analysis.
    func loadAll() -> (references: [RestoredReference], activeID: UUID?) {
        guard let data = try? Data(contentsOf: manifestURL) else { return ([], nil) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return ([], nil) }

        let references = manifest.references.compactMap { entry -> RestoredReference? in
            guard let imageData = try? Data(contentsOf: imageURL(for: entry.id)) else { return nil }
            let image = UIImage.downsampled(
                data: imageData,
                maxPixelSize: UIImage.displayMaxPixelSize
            ) ?? UIImage(data: imageData)?.upright()
            guard let image else { return nil }
            return RestoredReference(
                id: entry.id,
                importedAt: entry.importedAt,
                image: image
            )
        }
        return (references, manifest.activeReferenceID)
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
