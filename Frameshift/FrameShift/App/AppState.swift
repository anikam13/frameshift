import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {

    enum Tab: Hashable { case references, camera }

    // Reference photos (inspiration to recreate)
    @Published var references: [ReferencePhoto] = []
    @Published var activeReferenceIndex: Int = 0

    // Captured shots (shown in the gallery preview)
    @Published var capturedShots: [CapturedPhoto] = []

    // Camera is the default mode; the REFERENCE · CAMERA pill switches this.
    @Published var selectedTab: Tab = .camera

    private let store = ReferenceStore()
    private let analyzer = VisionAnalyzer()
    private let segmenter = PersonSegmenter()
    private let capturedStore = CapturedStore()

    // Photos add-only permission denied notice — shown once per app launch.
    @Published var photoLibraryDeniedNoticeVisible = false
    private var hasShownPhotoLibraryDeniedNotice = false

    // General-purpose ephemeral notice (Photos save failed, local save
    // failed, etc.) — shown every time since each is a distinct failure,
    // not a standing state like the Photos-denied notice above.
    @Published var transientNotice: String?
    private var transientNoticeDismissTask: Task<Void, Never>?

    // MARK: References

    var activeReference: ReferencePhoto? {
        guard references.indices.contains(activeReferenceIndex) else { return nil }
        return references[activeReferenceIndex]
    }

    var hasReferences: Bool { !references.isEmpty }

    func addReference(_ photo: ReferencePhoto, imageData: Data) {
        references.insert(photo, at: 0)
        activeReferenceIndex = 0   // newest becomes active
        let id = photo.id
        Task.detached(priority: .utility) { [store] in
            if !store.saveImageData(imageData, id: id) {
                await MainActor.run { self.showTransientNotice("Couldn't save this reference") }
            }
        }
        persistManifest()
    }

    func removeReference(id: UUID) {
        references.removeAll { $0.id == id }
        activeReferenceIndex = max(0, min(activeReferenceIndex, references.count - 1))
        Task.detached(priority: .utility) { [store] in
            store.deleteImage(id: id)
        }
        persistManifest()
    }

    func setActiveReference(id: UUID) {
        if let index = references.firstIndex(where: { $0.id == id }) {
            activeReferenceIndex = index
            persistManifest()
        }
    }

    /// Reloads persisted references on launch and recomputes their specs.
    /// Display images are downsampled; Vision/cutout use a one-shot full decode.
    func restoreReferences() async {
        guard references.isEmpty else { return }
        let restored = await Task.detached(priority: .userInitiated) { [store] in
            store.loadAll()
        }.value
        guard !restored.references.isEmpty else { return }

        references = restored.references.map {
            ReferencePhoto(id: $0.id, image: $0.image, importedAt: $0.importedAt)
        }
        if let activeID = restored.activeID,
           let index = references.firstIndex(where: { $0.id == activeID }) {
            activeReferenceIndex = index
        } else {
            activeReferenceIndex = 0
        }

        for entry in restored.references {
            let id = entry.id
            Task.detached(priority: .userInitiated) { [store, analyzer, segmenter] in
                // Full-res decode only for this analysis pass — not retained in AppState.
                guard let full = store.loadFullImage(id: id) else {
                    await MainActor.run { self.markAnalysisFailed(for: id) }
                    return
                }
                guard let spec = await analyzer.analyze(image: full.image, imageData: full.data)
                else {
                    await MainActor.run { self.markAnalysisFailed(for: id) }
                    return
                }
                await MainActor.run { self.updateSpec(for: id, spec: spec) }
                if let cutout = await segmenter.cutout(from: full.image) {
                    let displayCutout = cutout.downsampled(maxPixelSize: UIImage.overlayMaxPixelSize)
                    await MainActor.run { self.updateCutout(for: id, cutout: displayCutout) }
                }
            }
        }
    }

    private func persistManifest() {
        store.saveManifest(ReferenceStore.Manifest(
            activeReferenceID: activeReference?.id,
            references: references.map { .init(id: $0.id, importedAt: $0.importedAt) }
        ))
    }

    func updateSpec(for id: UUID, spec: ShotSpec) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].spec = spec
    }

    func updateCutout(for id: UUID, cutout: UIImage) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].personCutout = cutout
    }

    func markAnalysisFailed(for id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].analysisFailed = true
    }

    /// References grouped by detected style (tilt, camera angle, pose, lens,
    /// then framing size). Photos still being analyzed are returned
    /// separately via `unanalyzedReferences`.
    var styleGroups: [(category: ShotSpec.StyleCategory, photos: [ReferencePhoto])] {
        ShotSpec.StyleCategory.allCases.compactMap { category in
            let photos = references.filter { $0.spec?.styleCategory == category }
            return photos.isEmpty ? nil : (category, photos)
        }
    }

    var unanalyzedReferences: [ReferencePhoto] {
        references.filter { $0.spec == nil && !$0.analysisFailed }
    }

    /// References Vision couldn't find a person in — can't drive camera
    /// coaching, shown separately so they don't spin in "Analyzing…" forever.
    var noSubjectReferences: [ReferencePhoto] {
        references.filter { $0.analysisFailed }
    }

    /// Settings' "Clear All References" — leaves captured shots untouched.
    func clearAllReferences() {
        let ids = references.map(\.id)
        references.removeAll()
        activeReferenceIndex = 0
        Task.detached(priority: .utility) { [store] in
            for id in ids { store.deleteImage(id: id) }
        }
        persistManifest()
    }

    // MARK: Captured shots

    @discardableResult
    func addCapturedShot(_ image: UIImage, referenceID: UUID?) -> UUID {
        // Keep a display-sized bitmap in memory; write the capture-quality
        // JPEG to disk (and Photos) from the full image on a background task.
        let display = image.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)
        let shot = CapturedPhoto(image: display, referenceID: referenceID)
        capturedShots.insert(shot, at: 0)
        persistCapturedManifest()

        Task.detached(priority: .utility) { [capturedStore] in
            guard let data = image.jpegData(compressionQuality: 0.92) else { return }
            if !capturedStore.saveImageData(data, id: shot.id) {
                await MainActor.run { self.showTransientNotice("Couldn't save this photo") }
            }
        }

        Task.detached(priority: .utility) {
            let result = await PhotoLibrarySaver.save(image)
            await MainActor.run {
                switch result {
                case .saved:              break
                case .deniedOrRestricted: self.notePhotoLibraryDenied()
                case .failed:             self.showTransientNotice("Couldn't save to your camera roll")
                }
            }
        }
        return shot.id
    }

    func removeCapturedShot(id: UUID) {
        capturedShots.removeAll { $0.id == id }
        persistCapturedManifest()
        Task.detached(priority: .utility) { [capturedStore] in
            capturedStore.deleteImage(id: id)
        }
    }

    func setFavorite(id: UUID, isFavorite: Bool) {
        guard let index = capturedShots.firstIndex(where: { $0.id == id }) else { return }
        capturedShots[index].isFavorite = isFavorite
        persistCapturedManifest()
    }

    /// Resolves a captured shot's reference, tolerating deletion of the reference since.
    func reference(for id: UUID?) -> ReferencePhoto? {
        guard let id else { return nil }
        return references.first { $0.id == id }
    }

    /// Full-resolution images for export. Display bitmaps in memory are
    /// downsampled; this reloads from disk for the share card.
    func loadExportImages(shotID: UUID, referenceID: UUID) async -> (reference: UIImage, shot: UIImage)? {
        await Task.detached(priority: .userInitiated) { [store, capturedStore] in
            guard
                let reference = store.loadFullImage(id: referenceID)?.image,
                let shot = capturedStore.loadFullImage(id: shotID)
            else { return nil }
            return (reference, shot)
        }.value
    }

    /// Full-resolution captured shot for filter rendering — same reload-from-
    /// disk rationale as `loadExportImages`.
    func loadFullShot(id: UUID) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { [capturedStore] in
            capturedStore.loadFullImage(id: id)
        }.value
    }

    /// Settings' "Clear All Captured Shots" — only removes FrameShift's local
    /// copies; anything already saved to the system Photos library stays there,
    /// matching how single-shot delete already behaves.
    func clearAllCapturedShots() {
        let ids = capturedShots.map(\.id)
        capturedShots.removeAll()
        Task.detached(priority: .utility) { [capturedStore] in
            for id in ids { capturedStore.deleteImage(id: id) }
        }
        persistCapturedManifest()
    }

    /// Reloads persisted captured shots on launch.
    func restoreCapturedShots() async {
        guard capturedShots.isEmpty else { return }
        let restored = await Task.detached(priority: .userInitiated) { [capturedStore] in
            capturedStore.loadAll()
        }.value
        capturedShots = restored
            .sorted { $0.capturedAt > $1.capturedAt }
            .map {
                CapturedPhoto(
                    id: $0.id, image: $0.image, capturedAt: $0.capturedAt,
                    referenceID: $0.referenceID, isFavorite: $0.isFavorite
                )
            }
    }

    private func persistCapturedManifest() {
        capturedStore.saveManifest(CapturedStore.Manifest(
            shots: capturedShots.map {
                .init(id: $0.id, capturedAt: $0.capturedAt, referenceID: $0.referenceID, isFavorite: $0.isFavorite)
            }
        ))
    }

    /// Surfaces the "photos aren't saving to your camera roll" notice, once
    /// per app launch. Called for both raw captures and export-card saves so
    /// either path can trigger it without double-showing.
    func notePhotoLibraryDenied() {
        guard !hasShownPhotoLibraryDeniedNotice else { return }
        hasShownPhotoLibraryDeniedNotice = true
        photoLibraryDeniedNoticeVisible = true
    }

    func dismissPhotoLibraryDeniedNotice() {
        photoLibraryDeniedNoticeVisible = false
    }

    /// Ephemeral notice, like CameraViewModel's capture-failure notice —
    /// auto-dismisses, no "Settings" action since there's nothing there to fix.
    func showTransientNotice(_ message: String) {
        transientNoticeDismissTask?.cancel()
        transientNotice = message
        transientNoticeDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            transientNotice = nil
        }
    }
}
