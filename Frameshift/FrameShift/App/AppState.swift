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

    // User-created filter presets (look-source photos), creation order.
    @Published var filterPresets: [CustomFilterPreset] = []

    // Camera is the default mode; the REFERENCE · CAMERA pill switches this.
    @Published var selectedTab: Tab = .camera

    private let store = ReferenceStore()
    private let analyzer = VisionAnalyzer()
    private let segmenter = PersonSegmenter()
    private let capturedStore = CapturedStore()
    private let filterPresetStore = FilterPresetStore()

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

        // One reference's analysis pass: full-res decode (not retained in
        // AppState), Vision spec, then the ghost cutout.
        let analyzeOne: @Sendable (UUID) async -> Void = { [store, analyzer, segmenter] id in
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

        // Launch-speed rule: never fan out one Vision pass per reference at
        // launch — a parallel stampede of pose/face/segmentation models
        // starves the camera session and first render. The active reference
        // (the one live coaching needs) analyzes right away; the rest run
        // one at a time at utility, yielding to camera and UI work.
        let activeID = references[activeReferenceIndex].id
        let queuedIDs = restored.references.map(\.id).filter { $0 != activeID }
        Task.detached(priority: .userInitiated) {
            await analyzeOne(activeID)
            Task.detached(priority: .utility) {
                for id in queuedIDs { await analyzeOne(id) }
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
    func addCapturedShot(_ image: UIImage, referenceID: UUID?, burstID: UUID? = nil) -> UUID {
        // Keep a display-sized bitmap in memory; write the capture-quality
        // JPEG to disk (and Photos) from the full image on a background task.
        let display = image.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)
        return insertCapturedShot(display: display, full: image, referenceID: referenceID, burstID: burstID)
    }

    /// Burst-path variant: the caller downsamples off the main actor first —
    /// shots land up to 10/s during a burst, and downsampling each one here
    /// would freeze the viewfinder for the whole hold.
    @discardableResult
    func insertCapturedShot(display: UIImage, full image: UIImage, referenceID: UUID?, burstID: UUID?) -> UUID {
        let shot = CapturedPhoto(image: display, referenceID: referenceID, burstID: burstID)
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

    // MARK: Bursts

    /// Marks one shot as its burst's best — the group's cover in the gallery.
    func setBurstBest(id: UUID) {
        guard
            let shot = capturedShots.first(where: { $0.id == id }),
            let burstID = shot.burstID
        else { return }
        for index in capturedShots.indices where capturedShots[index].burstID == burstID {
            capturedShots[index].isBurstBest = (capturedShots[index].id == id)
        }
        persistCapturedManifest()
    }

    /// Deletes every shot captured in one burst.
    func removeBurst(burstID: UUID) {
        let ids = capturedShots.filter { $0.burstID == burstID }.map(\.id)
        guard !ids.isEmpty else { return }
        capturedShots.removeAll { $0.burstID == burstID }
        persistCapturedManifest()
        Task.detached(priority: .utility) { [capturedStore] in
            for id in ids { capturedStore.deleteImage(id: id) }
        }
    }

    /// Burst picker's "Keep Only This" — deletes the rest of the burst. The
    /// survivor keeps its burstID but a one-shot group renders as a normal
    /// photo in the gallery.
    func keepOnlyBurstShot(id: UUID) {
        guard
            let keep = capturedShots.first(where: { $0.id == id }),
            let burstID = keep.burstID
        else { return }
        let removeIDs = capturedShots
            .filter { $0.burstID == burstID && $0.id != id }
            .map(\.id)
        guard !removeIDs.isEmpty else { return }
        capturedShots.removeAll { removeIDs.contains($0.id) }
        persistCapturedManifest()
        Task.detached(priority: .utility) { [capturedStore] in
            for id in removeIDs { capturedStore.deleteImage(id: id) }
        }
    }

    /// Resolves a captured shot's reference, tolerating deletion of the reference since.
    func reference(for id: UUID?) -> ReferencePhoto? {
        guard let id else { return nil }
        return references.first { $0.id == id }
    }

    /// Full-resolution captured shot for filter rendering. Display bitmaps in
    /// memory are downsampled; this reloads from disk.
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

    /// Reloads persisted captured shots on launch. Utility priority: this
    /// decodes a thumbnail per shot (bursts make that dozens), and only the
    /// bottom-left gallery thumb shows it — it must not race camera startup.
    func restoreCapturedShots() async {
        guard capturedShots.isEmpty else { return }
        let restored = await Task.detached(priority: .utility) { [capturedStore] in
            capturedStore.loadAll()
        }.value
        capturedShots = restored
            .sorted { $0.capturedAt > $1.capturedAt }
            .map {
                CapturedPhoto(
                    id: $0.id, image: $0.image, capturedAt: $0.capturedAt,
                    referenceID: $0.referenceID, isFavorite: $0.isFavorite,
                    burstID: $0.burstID, isBurstBest: $0.isBurstBest
                )
            }
    }

    private func persistCapturedManifest() {
        capturedStore.saveManifest(CapturedStore.Manifest(
            shots: capturedShots.map {
                .init(
                    id: $0.id, capturedAt: $0.capturedAt, referenceID: $0.referenceID,
                    isFavorite: $0.isFavorite, burstID: $0.burstID, isBurstBest: $0.isBurstBest
                )
            }
        ))
    }

    #if DEBUG
    /// UI-test hook (`-uitest-seed-references` launch argument): in-memory
    /// references only, no disk writes, no Vision analysis.
    func seedReferencesForUITests(count: Int = 4) {
        let colors: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange]
        references = (0..<count).map { index in
            let size = CGSize(width: 300, height: 400)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                colors[index % colors.count].setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            var photo = ReferencePhoto(image: image)
            photo.analysisFailed = true   // stable "No subject" section, no spinner
            return photo
        }
        selectedTab = .references
    }
    #endif

    // MARK: Custom filter presets

    /// Creates a preset from a look-source photo picked in the filter sheet.
    /// The image arrives already downsampled — only its color stats matter.
    @discardableResult
    func addFilterPreset(from image: UIImage) -> CustomFilterPreset {
        // Numbering survives deletes: one past the highest existing number,
        // so a fresh preset never takes a deleted one's name.
        let nextNumber = (filterPresets.compactMap { preset in
            preset.name.hasPrefix("Preset ") ? Int(preset.name.dropFirst(7)) : nil
        }.max() ?? 0) + 1
        let preset = CustomFilterPreset(
            id: UUID(), name: "Preset \(nextNumber)", image: image, createdAt: Date()
        )
        filterPresets.append(preset)

        let id = preset.id
        Task.detached(priority: .utility) { [filterPresetStore] in
            guard
                let data = image.jpegData(compressionQuality: 0.85),
                filterPresetStore.saveImageData(data, id: id)
            else {
                await MainActor.run { self.showTransientNotice("Couldn't save this preset") }
                return
            }
        }
        persistFilterPresetManifest()
        return preset
    }

    func removeFilterPreset(id: UUID) {
        filterPresets.removeAll { $0.id == id }
        Task.detached(priority: .utility) { [filterPresetStore] in
            filterPresetStore.deleteImage(id: id)
        }
        persistFilterPresetManifest()
    }

    /// Reloads persisted filter presets on launch. Utility: nothing on the
    /// camera screen needs these — first use is the gallery's filter sheet.
    func restoreFilterPresets() async {
        guard filterPresets.isEmpty else { return }
        filterPresets = await Task.detached(priority: .utility) { [filterPresetStore] in
            filterPresetStore.loadAll()
        }.value
    }

    private func persistFilterPresetManifest() {
        filterPresetStore.saveManifest(FilterPresetStore.Manifest(
            presets: filterPresets.map {
                .init(id: $0.id, name: $0.name, createdAt: $0.createdAt)
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
