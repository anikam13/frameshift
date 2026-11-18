import UIKit

/// Full-resolution JPEGs plus a small manifest for the current shooting
/// session only (D-25: photos live in Apple Photos; FrameShift keeps no
/// archive). Used for full-size share, Add to References, save retry, and to
/// bring an open session back if iOS closes the app in the background (D-2).
/// Lives in Caches (the system may purge it — then the session is simply
/// gone), and is cleared when a session ends.
/// nonisolated: file I/O runs on background tasks.
nonisolated struct SessionCaptureCache {

    /// What's needed to rebuild an open session after relaunch.
    struct Manifest: Codable {
        struct Shot: Codable {
            let id: UUID
            let capturedAt: Date
            let referenceID: UUID?
            let burstID: UUID?
            let isBurstBest: Bool
        }
        let lastCaptureAt: Date
        let shots: [Shot]   // newest first, saved-to-Photos shots only
    }

    struct RestoredShot {
        let shot: Manifest.Shot
        let image: UIImage   // display-sized
    }

    private let directory: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("SessionCaptures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var manifestURL: URL { directory.appendingPathComponent("session.json") }

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

    /// Full-resolution decode for share / add-as-reference / retry. Call off the main thread.
    func loadFullImage(id: UUID) -> UIImage? {
        guard
            let imageData = try? Data(contentsOf: imageURL(for: id)),
            let raw = UIImage(data: imageData)
        else { return nil }
        return raw.upright()
    }

    func saveManifest(_ manifest: Manifest?) {
        guard let manifest else {
            try? FileManager.default.removeItem(at: manifestURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    /// Launch: returns the previous session if it's still open (last capture
    /// within `limit`) and clears everything else — stale sessions, orphaned
    /// files, and stores from pre-redesign builds. Call off the main thread.
    func restoreOpenSession(limit: TimeInterval, now: Date = Date()) -> (lastCaptureAt: Date, shots: [RestoredShot])? {
        removeLegacyStores()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? decoder.decode(Manifest.self, from: data),
            now.timeIntervalSince(manifest.lastCaptureAt) <= limit
        else {
            removeAll()
            return nil
        }
        let restored = manifest.shots.compactMap { shot -> RestoredShot? in
            guard let data = try? Data(contentsOf: imageURL(for: shot.id)),
                  let image = UIImage.downsampled(data: data, maxPixelSize: UIImage.displayMaxPixelSize)
            else { return nil }
            return RestoredShot(shot: shot, image: image)
        }
        // Drop files that aren't part of the restored session.
        let keep = Set(restored.map { imageURL(for: $0.shot.id).lastPathComponent } + ["session.json"])
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        guard !restored.isEmpty else {
            removeAll()
            return nil
        }
        return (manifest.lastCaptureAt, restored)
    }

    /// Clears every cached capture and the manifest.
    func removeAll() {
        let fm = FileManager.default
        try? fm.removeItem(at: directory)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stores from earlier builds: the persistent capture archive, removed
    /// filter presets, and the tmp-dir session cache.
    private func removeLegacyStores() {
        let fm = FileManager.default
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for legacy in ["Captures", "FilterPresets"] {
                try? fm.removeItem(at: support.appendingPathComponent(legacy, isDirectory: true))
            }
        }
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("SessionCaptures", isDirectory: true))
    }
}
