import UIKit

/// Persists user-created filter presets (look-source photos picked in the
/// filter sheet) to Application Support so they survive relaunch. Images are
/// stored already-downsampled — only their color statistics matter.
/// nonisolated: the project defaults to MainActor isolation, but this
/// store's file I/O runs on background tasks.
nonisolated struct FilterPresetStore {

    struct Manifest: Codable {
        struct Entry: Codable {
            let id: UUID
            let name: String
            let createdAt: Date
        }
        var presets: [Entry]   // creation order, matches AppState order
    }

    private let directory: URL

    private var manifestURL: URL {
        directory.appendingPathComponent("presets.json")
    }

    /// `directory` is injectable for tests; the app uses the default.
    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]
            self.directory = base.appendingPathComponent("FilterPresets", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory, withIntermediateDirectories: true
        )
    }

    private func imageURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
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
    func loadAll() -> [CustomFilterPreset] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: data) else { return [] }

        return manifest.presets.compactMap { entry in
            guard
                let imageData = try? Data(contentsOf: imageURL(for: entry.id)),
                let image = UIImage.downsampled(
                    data: imageData, maxPixelSize: UIImage.overlayMaxPixelSize
                ) ?? UIImage(data: imageData)
            else { return nil }
            return CustomFilterPreset(
                id: entry.id,
                name: entry.name,
                image: image,
                createdAt: entry.createdAt
            )
        }
    }
}
