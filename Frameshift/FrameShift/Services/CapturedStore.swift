import UIKit

/// Persists captured shots and their favorite/reference metadata to
/// Application Support so the gallery survives relaunch. Mirrors
/// ReferenceStore's file layout: a JSON manifest plus one JPEG file per shot.
/// Captured images arrive already decoded/cropped by CameraService (HEVC
/// capture bytes are discarded during the preview-crop step), so this
/// re-encodes to JPEG rather than preserving original bytes/EXIF.
/// `loadAll()` returns display-sized bitmaps; use `loadFullImage` for export.
/// nonisolated: the project defaults to MainActor isolation, but this
/// store's file I/O runs on background tasks.
nonisolated struct CapturedStore {

    struct Manifest: Codable {
        struct Entry: Codable {
            let id: UUID
            let capturedAt: Date
            let referenceID: UUID?
            var isFavorite: Bool
            // Optional so manifests written before burst grouping still decode.
            var burstID: UUID?
            var isBurstBest: Bool?
        }
        var shots: [Entry]   // index 0 = newest, matches AppState order
    }

    struct RestoredShot {
        let id: UUID
        let capturedAt: Date
        let referenceID: UUID?
        let isFavorite: Bool
        let burstID: UUID?
        let isBurstBest: Bool
        let image: UIImage
    }

    private let directory: URL

    private var manifestURL: URL {
        directory.appendingPathComponent("captures.json")
    }

    init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        directory = base.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

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
    /// Decodes display-sized thumbnails only — full JPEGs stay on disk.
    func loadAll() -> [RestoredShot] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return [] }

        return manifest.shots.compactMap { entry -> RestoredShot? in
            guard let imageData = try? Data(contentsOf: imageURL(for: entry.id)) else { return nil }
            let image = UIImage.downsampled(
                data: imageData,
                maxPixelSize: UIImage.displayMaxPixelSize
            ) ?? UIImage(data: imageData)?.upright()
            guard let image else { return nil }
            return RestoredShot(
                id: entry.id,
                capturedAt: entry.capturedAt,
                referenceID: entry.referenceID,
                isFavorite: entry.isFavorite,
                burstID: entry.burstID,
                isBurstBest: entry.isBurstBest ?? false,
                image: image
            )
        }
    }

    /// Full-resolution decode for export / share. Call off the main thread.
    func loadFullImage(id: UUID) -> UIImage? {
        guard
            let imageData = try? Data(contentsOf: imageURL(for: id)),
            let raw = UIImage(data: imageData)
        else { return nil }
        return raw.upright()
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
