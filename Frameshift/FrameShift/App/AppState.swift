import SwiftUI
import Combine

/// Serializes Vision / person-segmentation so restore, imports, and the
/// sample pack never stampede the Neural Engine against the camera.
private actor VisionWorkQueue {
    func run(_ body: @Sendable () async -> Void) async {
        await body()
    }
}

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

    /// True while import/restore Vision work is in flight. Camera pauses live
    /// subject detection against this so preview isn't starved.
    @Published private(set) var isBackgroundVisionBusy = false

    /// Becomes true after the first `restoreReferences()` finishes (even when
    /// the library is empty). UI that keys off `hasReferences` must wait on
    /// this so cold start doesn't flash the empty-state hint over the mode pill.
    @Published private(set) var hasFinishedRestoringReferences = false

    private let store = ReferenceStore()
    private let analyzer = VisionAnalyzer()
    private let segmenter = PersonSegmenter()
    private let capturedStore = CapturedStore()
    private let filterPresetStore = FilterPresetStore()
    private let visionQueue = VisionWorkQueue()
    private var pendingVisionJobs = 0

    // Photos add-only permission denied notice — shown once per app launch.
    @Published var photoLibraryDeniedNoticeVisible = false
    private var hasShownPhotoLibraryDeniedNotice = false

    /// Restore finished during first-launch onboarding — analyze after the
    /// user reaches the camera so Next taps aren't fighting Neural Engine.
    private var deferredRestoreAnalysis: (active: UUID, rest: [UUID])?

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

    /// Shared import path for PhotosPicker and sample pack.
    /// Shows the photo immediately, persists original bytes, then analyzes off-main.
    func importReference(raw: UIImage, data: Data) {
        let imageData = data
        // Decode/downsample off the main actor — sample pack / multi-import
        // used to upright full-res bitmaps synchronously and freeze UI.
        Task.detached(priority: .utility) { [analyzer, segmenter, store] in
            let full = raw.upright()
            let display = full.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)
            let photoId = await MainActor.run {
                let photo = ReferencePhoto(image: display)
                self.addReference(photo, imageData: imageData)
                return photo.id
            }
            await self.performVisionWork {
                let spec = await analyzer.analyze(image: full, imageData: imageData)
                if let spec {
                    let cutout = await segmenter.cutout(from: full)
                    let displayCutout = cutout?.downsampled(maxPixelSize: UIImage.overlayMaxPixelSize)
                    if let displayCutout {
                        _ = store.saveCutout(displayCutout, id: photoId)
                    } else {
                        store.deleteCutout(id: photoId)
                    }
                    await MainActor.run {
                        self.applyAnalysis(for: photoId, spec: spec, cutout: displayCutout, failed: false)
                    }
                } else {
                    store.deleteCutout(id: photoId)
                    await MainActor.run {
                        self.applyAnalysis(for: photoId, spec: nil, cutout: nil, failed: true)
                    }
                }
            }
        }
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
            ensureCutoutLoaded(for: id)
        }
    }

    /// Loads a persisted ghost cutout on demand (active ref / ghost overlay).
    func ensureCutoutLoaded(for id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        guard references[index].personCutout == nil,
              references[index].spec != nil,
              !references[index].analysisFailed
        else { return }
        Task.detached(priority: .utility) { [store] in
            let cutout = store.loadCutout(id: id)
            guard let cutout else { return }
            await MainActor.run {
                guard let idx = self.references.firstIndex(where: { $0.id == id }),
                      self.references[idx].personCutout == nil
                else { return }
                self.references[idx].personCutout = cutout
            }
        }
    }

    /// Reloads persisted references on launch. Cached specs with a matching
    /// `ShotSpec.analyzerVersion` skip Vision; cutouts load lazily for the
    /// active reference only so cold start doesn't decode dozens of PNGs.
    func restoreReferences() async {
        defer { hasFinishedRestoringReferences = true }
        guard references.isEmpty else { return }
        // Utility: thumb decode must not outrank camera session startup.
        let restored = await Task.detached(priority: .utility) { [store] in
            store.loadAll()
        }.value
        guard !restored.references.isEmpty else { return }

        // Publish display images + specs first — no cutouts — so the mode pill
        // and references grid become usable immediately.
        references = restored.references.map {
            ReferencePhoto(
                id: $0.id,
                image: $0.image,
                importedAt: $0.importedAt,
                spec: $0.spec,
                personCutout: nil,
                analysisFailed: $0.analysisFailed
            )
        }
        if let activeID = restored.activeID,
           let index = references.firstIndex(where: { $0.id == activeID }) {
            activeReferenceIndex = index
        } else {
            activeReferenceIndex = 0
        }

        let activeID = references[activeReferenceIndex].id
        // Ghost overlay only needs the active cutout on camera entry.
        if restored.references.contains(where: { $0.id == activeID && $0.hasCutoutOnDisk }) {
            ensureCutoutLoaded(for: activeID)
        }

        let needingIDs = restored.references.filter(\.needsAnalysis).map(\.id)
        guard !needingIDs.isEmpty else { return }

        let ordered = needingIDs.contains(activeID)
            ? [activeID] + needingIDs.filter { $0 != activeID }
            : needingIDs
        let rest = Array(ordered.dropFirst())
        let first = ordered[0]

        // First-launch onboarding still mounts this restore task — hold Vision
        // until the user finishes so Next isn't fighting Neural Engine.
        let onboardingDone = UserDefaults.standard.bool(
            forKey: "frameshift.hasCompletedOnboarding"
        )
        if onboardingDone {
            scheduleRestoreAnalysis(activeID: first, queuedIDs: rest, yieldForCamera: true)
        } else {
            deferredRestoreAnalysis = (first, rest)
        }
    }

    /// Called when first-launch onboarding completes (or is already done).
    func resumeDeferredAnalysisAfterOnboarding() {
        guard let deferred = deferredRestoreAnalysis else { return }
        deferredRestoreAnalysis = nil
        scheduleRestoreAnalysis(
            activeID: deferred.active,
            queuedIDs: deferred.rest,
            yieldForCamera: true
        )
    }

    private func scheduleRestoreAnalysis(
        activeID: UUID,
        queuedIDs: [UUID],
        yieldForCamera: Bool
    ) {
        let imageStore = store
        let visionAnalyzer = analyzer
        let personSegmenter = segmenter
        // One reference's analysis pass: full-res decode (not retained in
        // AppState), Vision spec, then the ghost cutout — then persist.
        let analyzeOne: @Sendable (UUID) async -> Void = { id in
            guard let full = imageStore.loadFullImage(id: id) else {
                imageStore.deleteCutout(id: id)
                await MainActor.run {
                    self.applyAnalysis(for: id, spec: nil, cutout: nil, failed: true)
                }
                return
            }
            guard let spec = await visionAnalyzer.analyze(image: full.image, imageData: full.data)
            else {
                imageStore.deleteCutout(id: id)
                await MainActor.run {
                    self.applyAnalysis(for: id, spec: nil, cutout: nil, failed: true)
                }
                return
            }
            // Balanced is enough for the ghost overlay and much cheaper at migrate.
            let cutout = await personSegmenter.cutout(from: full.image, quality: .balanced)
            let displayCutout = cutout?.downsampled(maxPixelSize: UIImage.overlayMaxPixelSize)
            if let displayCutout {
                _ = imageStore.saveCutout(displayCutout, id: id)
            } else {
                imageStore.deleteCutout(id: id)
            }
            await MainActor.run {
                self.applyAnalysis(for: id, spec: spec, cutout: displayCutout, failed: false)
            }
        }

        Task(priority: .utility) {
            await performVisionWork {
                // Let AVCaptureSession.startRunning claim the first beat.
                if yieldForCamera {
                    try? await Task.sleep(for: .milliseconds(800))
                }
                await analyzeOne(activeID)
                for id in queuedIDs {
                    await analyzeOne(id)
                }
            }
        }
    }

    /// Runs Vision work one job at a time and publishes busy state for the camera.
    private func performVisionWork(_ body: @escaping @Sendable () async -> Void) async {
        pendingVisionJobs += 1
        isBackgroundVisionBusy = true
        await visionQueue.run(body)
        pendingVisionJobs = max(0, pendingVisionJobs - 1)
        if pendingVisionJobs == 0 {
            isBackgroundVisionBusy = false
        }
    }

    /// Sync on MainActor: the JSON is tiny, and detached writes raced so an
    /// earlier "no spec yet" snapshot could overwrite a completed analysis.
    private func persistManifest() {
        _ = store.saveManifest(ReferenceStore.Manifest(
            activeReferenceID: activeReference?.id,
            references: references.map { photo in
                .init(
                    id: photo.id,
                    importedAt: photo.importedAt,
                    analyzerVersion: (photo.spec != nil || photo.analysisFailed)
                        ? ShotSpec.analyzerVersion : nil,
                    analysisFailed: photo.analysisFailed ? true : nil,
                    spec: photo.spec
                )
            }
        ))
    }

    /// Applies analysis results to memory and rewrites the manifest (spec/failed).
    private func applyAnalysis(
        for id: UUID,
        spec: ShotSpec?,
        cutout: UIImage?,
        failed: Bool
    ) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].spec = spec
        references[index].analysisFailed = failed
        references[index].personCutout = failed ? nil : cutout
        persistManifest()
    }

    func updateSpec(for id: UUID, spec: ShotSpec) {
        applyAnalysis(for: id, spec: spec, cutout: references.first { $0.id == id }?.personCutout, failed: false)
    }

    func updateCutout(for id: UUID, cutout: UIImage) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].personCutout = cutout
        Task.detached(priority: .utility) { [store] in
            _ = store.saveCutout(cutout, id: id)
        }
    }

    func markAnalysisFailed(for id: UUID) {
        applyAnalysis(for: id, spec: nil, cutout: nil, failed: true)
        Task.detached(priority: .utility) { [store] in
            store.deleteCutout(id: id)
        }
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

    /// Single-shot path: downsamples off-main so a full-res capture (or filter
    /// save) never freezes the viewfinder / gallery on insert.
    func addCapturedShot(_ image: UIImage, referenceID: UUID?, burstID: UUID? = nil) {
        let maxSize = UIImage.displayMaxPixelSize
        Task.detached(priority: .userInitiated) {
            let display = image.downsampled(maxPixelSize: maxSize)
            await MainActor.run {
                _ = self.insertCapturedShot(
                    display: display, full: image,
                    referenceID: referenceID, burstID: burstID
                )
            }
        }
    }

    /// Like `addCapturedShot` but returns the new id after the insert lands.
    func addCapturedShotAsync(_ image: UIImage, referenceID: UUID?, burstID: UUID? = nil) async -> UUID {
        let maxSize = UIImage.displayMaxPixelSize
        let display = await Task.detached(priority: .userInitiated) {
            image.downsampled(maxPixelSize: maxSize)
        }.value
        return insertCapturedShot(
            display: display, full: image,
            referenceID: referenceID, burstID: burstID
        )
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
        let manifest = CapturedStore.Manifest(
            shots: capturedShots.map {
                .init(
                    id: $0.id, capturedAt: $0.capturedAt, referenceID: $0.referenceID,
                    isFavorite: $0.isFavorite, burstID: $0.burstID, isBurstBest: $0.isBurstBest
                )
            }
        )
        Task.detached(priority: .utility) { [capturedStore] in
            _ = capturedStore.saveManifest(manifest)
        }
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
        hasFinishedRestoringReferences = true
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
