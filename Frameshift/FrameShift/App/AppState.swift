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

    // This session's captures, newest first (plus any whose Photos save is
    // still pending or failed). Not an archive: dropped when the session ends
    // and never persisted across launches (D-25).
    @Published var capturedShots: [CapturedPhoto] = []

    // Camera is the default mode; the REFERENCE · CAMERA pill switches this.
    @Published var selectedTab: Tab = .references

    /// The camera viewfinder's frame in window coordinates — where Recreate's
    /// morph lands (D-29). Not published: only read when Recreate is tapped.
    var viewfinderFrame: CGRect = .zero
    /// True while the Recreate morph is flying onto the viewfinder. The camera
    /// holds the overlay back until it lands so the person isn't shown twice.
    @Published var morphReferenceID: UUID?
    var isRecreateMorphInFlight: Bool { morphReferenceID != nil }
    /// Mirrors `CameraViewModel.isFeedSettled` for the Recreate scan, which
    /// can be hosted outside the camera (the preview cover).
    @Published var isCameraFeedSettled = false

    /// Is this reference's overlay final? True once its cutout is in memory,
    /// or when no cutout is coming (analysis failed). An unanalyzed import
    /// stays false — the scan's timeout covers it.
    func isOverlayReady(for id: UUID) -> Bool {
        guard let ref = references.first(where: { $0.id == id }) else { return true }
        return ref.personCutout != nil || ref.analysisFailed || cutoutLookupDone.contains(id)
    }

    /// References whose on-disk cutout lookup finished — found or not (no
    /// person segmented). Lets the reveal stop waiting for a cutout that
    /// doesn't exist.
    @Published private(set) var cutoutLookupDone: Set<UUID> = []

    /// Quick-row Recreate: the camera hosts the morph above the gallery.
    @Published var recreateMorph: RecreateMorphRequest?

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
    private let captureCache = SessionCaptureCache()
    private let visionQueue = VisionWorkQueue()
    private var pendingVisionJobs = 0

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
        let hadActive = activeReference != nil
        references.insert(photo, at: 0)
        // Importing doesn't change what the camera is shooting against —
        // only Recreate / the picker does. Keep the active reference's index.
        activeReferenceIndex = hadActive ? activeReferenceIndex + 1 : 0
        let id = photo.id
        Task.detached(priority: .utility) { [store] in
            if !store.saveImageData(imageData, id: id) {
                await MainActor.run { self.showTransientNotice("Couldn't save this reference") }
            }
        }
        persistManifest()
    }

    /// Shared import path for PhotosPicker and sample pack.
    /// Shows the photo immediately, analyzes from the original (EXIF roll),
    /// and persists a compressed JPEG instead of the source HEIC/PNG.
    func importReference(
        raw: UIImage,
        data: Data,
        bundledAssetName: String? = nil,
        onAdded: (@MainActor (UUID) -> Void)? = nil
    ) {
        let originalData = data
        let assetName = bundledAssetName
        // Decode/downsample off the main actor — sample pack / multi-import
        // used to upright full-res bitmaps synchronously and freeze UI.
        Task.detached(priority: .utility) { [analyzer, segmenter, store] in
            let full = raw.upright()
            let stored = full.compressedReferenceJPEG() ?? originalData
            let display = full.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)
            let photoId = await MainActor.run {
                let photo = ReferencePhoto(image: display, bundledAssetName: assetName)
                self.addReference(photo, imageData: stored)
                onAdded?(photo.id)
                return photo.id
            }
            await self.performVisionWork {
                let spec = await analyzer.analyze(image: full, imageData: originalData)
                if let spec {
                    let subject = CGRect(
                        x: spec.subjectLeft,
                        y: spec.subjectTop,
                        width: spec.subjectWidth,
                        height: spec.subjectHeight
                    )
                    let cutout = await segmenter.cutout(from: full, subjectNormalized: subject)
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
        let activeID = activeReference?.id
        references.removeAll { $0.id == id }
        if let activeID, activeID != id,
           let index = references.firstIndex(where: { $0.id == activeID }) {
            activeReferenceIndex = index
        } else {
            activeReferenceIndex = max(0, min(activeReferenceIndex, references.count - 1))
        }
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

    /// Makes a reference active from a shooting surface (camera picker,
    /// quick-access row, Recreate) and records the use for "recent" ranking.
    func useReference(id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].useCount += 1
        references[index].lastUsedAt = Date()
        setActiveReference(id: id)   // persists the manifest
    }

    func setReferenceFavorite(id: UUID, isFavorite: Bool) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].isFavorite = isFavorite
        persistManifest()
    }

    /// One merged row: favorites first (most recently used first), then
    /// used-but-not-favorite references by recency. No duplicates.
    var quickAccessReferences: [ReferencePhoto] {
        let byRecency: (ReferencePhoto, ReferencePhoto) -> Bool = {
            ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
        }
        let favorites = references.filter(\.isFavorite).sorted(by: byRecency)
        let recents = references
            .filter { !$0.isFavorite && $0.lastUsedAt != nil }
            .sorted(by: byRecency)
        return favorites + recents
    }

    var curatedReferences: [ReferencePhoto] { references.filter(\.isCurated) }
    /// Newest import first (`references` is already newest-first).
    var importedReferences: [ReferencePhoto] { references.filter { !$0.isCurated } }

    // MARK: Capture session

    /// Captures confirmed saved to Apple Photos in the current shooting
    /// session, newest first. Drives the camera thumbnail's count badge.
    /// A session ends after `sessionInactivityLimit` without a capture;
    /// switching references never resets it.
    @Published private(set) var sessionShotIDs: [UUID] = []
    private var lastSessionCaptureAt: Date?
    /// Provisional — the UX spec leaves the exact threshold open.
    static let sessionInactivityLimit: TimeInterval = 30 * 60

    var sessionSavedCount: Int { sessionShotIDs.count }

    /// Ends a stale session before a new capture lands in it.
    /// Shots confirmed saved to Photos in the current session, newest first.
    var sessionShots: [CapturedPhoto] {
        if let last = lastSessionCaptureAt,
           Date().timeIntervalSince(last) > Self.sessionInactivityLimit {
            return []
        }
        let ids = Set(sessionShotIDs)
        return capturedShots.filter { ids.contains($0.id) }
    }

    /// Ends a stale session when the camera or session gallery appears, so an
    /// old session's count never greets a new shoot.
    func endSessionIfStale() {
        rollSessionIfStale()
    }

    /// Session Select → Add to References (D-11). Imports each shot's
    /// full-resolution JPEG through the normal reference pipeline.
    /// Returns how many were added.
    @discardableResult
    func addCapturedShotsAsReferences(ids: [UUID]) async -> Int {
        var added = 0
        for id in ids {
            guard let shot = capturedShots.first(where: { $0.id == id }) else { continue }
            let full = await loadFullShot(id: id) ?? shot.image
            guard let pair = await Task.detached(priority: .utility, operation: {
                guard let data = full.jpegData(compressionQuality: 0.92),
                      let raw = UIImage(data: data) else { return nil as (Data, UIImage)? }
                return (data, raw)
            }).value else { continue }
            importReference(raw: pair.1, data: pair.0)
            added += 1
        }
        return added
    }

    /// Ends a stale session: its shots leave memory and the temporary cache.
    /// Shots not yet confirmed saved (pending / failed) are kept.
    private func rollSessionIfStale(now: Date = Date()) {
        guard let last = lastSessionCaptureAt,
              now.timeIntervalSince(last) > Self.sessionInactivityLimit
        else { return }
        let ended = Set(sessionShotIDs)
        capturedShots.removeAll { ended.contains($0.id) }
        sessionShotIDs.removeAll()
        lastSessionCaptureAt = nil
        deleteCachedCaptures(Array(ended))
        persistSessionManifest()
    }

    /// Writes the open session's manifest so it survives iOS closing the app
    /// in the background (D-2). Only shots confirmed saved to Photos.
    private func persistSessionManifest() {
        let manifest: SessionCaptureCache.Manifest?
        if let last = lastSessionCaptureAt, !sessionShotIDs.isEmpty {
            let ids = Set(sessionShotIDs)
            manifest = .init(
                lastCaptureAt: last,
                shots: capturedShots.filter { ids.contains($0.id) }.map {
                    .init(id: $0.id, capturedAt: $0.capturedAt, referenceID: $0.referenceID,
                          burstID: $0.burstID, isBurstBest: $0.isBurstBest,
                          photosAssetID: $0.photosAssetID)
                }
            )
        } else {
            manifest = nil
        }
        Task.detached(priority: .utility) { [captureCache] in
            captureCache.saveManifest(manifest)
        }
    }

    private func deleteCachedCaptures(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        Task.detached(priority: .utility) { [captureCache] in
            for id in ids { captureCache.deleteImage(id: id) }
        }
    }

    /// Keeps the session count in step after a removal.
    private func syncSessionIDs() {
        let existing = Set(capturedShots.map(\.id))
        sessionShotIDs.removeAll { !existing.contains($0) }
        persistSessionManifest()
    }

    private func noteSessionSaved(id: UUID, photosAssetID: String?) {
        if let index = capturedShots.firstIndex(where: { $0.id == id }) {
            capturedShots[index].photosAssetID = photosAssetID
        }
        rollSessionIfStale()
        lastSessionCaptureAt = Date()
        sessionShotIDs.insert(id, at: 0)
        persistSessionManifest()
    }

    /// Loads a persisted ghost cutout on demand (active ref / ghost overlay).
    func ensureCutoutLoaded(for id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        guard references[index].personCutout == nil,
              references[index].spec != nil,
              !references[index].analysisFailed
        else { return }
        // User-initiated: it gates the Recreate reveal.
        Task.detached(priority: .userInitiated) { [store] in
            let cutout = store.loadCutout(id: id)
            guard let cutout else {
                await MainActor.run { _ = self.cutoutLookupDone.insert(id) }
                return
            }
            await MainActor.run {
                self.cutoutLookupDone.insert(id)
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

        if restored.references.isEmpty {
            // First launch: the curated Explore set ships in the bundle.
            // Seed it, then analyze in the background (gallery comes first).
            await seedBundledSamplesIntoLibrary()
            guard !references.isEmpty else { return }
            let ids = references.map(\.id)
            scheduleRestoreAnalysis(activeID: ids[0], queuedIDs: Array(ids.dropFirst()), yieldForCamera: false)
            return
        }

        // Publish display images + specs first — no cutouts — so the mode pill
        // and references grid become usable immediately.
        references = restored.references.map {
            ReferencePhoto(
                id: $0.id,
                image: $0.image,
                importedAt: $0.importedAt,
                spec: $0.spec,
                personCutout: nil,
                analysisFailed: $0.analysisFailed,
                bundledAssetName: $0.bundledAssetName,
                isFavorite: $0.isFavorite,
                useCount: $0.useCount,
                lastUsedAt: $0.lastUsedAt
            )
        }
        if let activeID = restored.activeID,
           let index = references.firstIndex(where: { $0.id == activeID }) {
            activeReferenceIndex = index
        } else {
            activeReferenceIndex = 0
        }

        let activeID = references[activeReferenceIndex].id
        // Launch routing (D-2, revised): always open on the gallery. The
        // camera stays mounted underneath and starts its session now, so it's
        // warm by the time the user taps Recreate / Resume Camera.
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

        scheduleRestoreAnalysis(activeID: first, queuedIDs: rest, yieldForCamera: true)
    }

    /// Writes the bundled sample pack into an empty first-launch library.
    /// Vision stays deferred so onboarding's coach demo isn't starved.
    private func seedBundledSamplesIntoLibrary() async {
        guard references.isEmpty else { return }
        let names = SampleReferencePack.assetNames
        let prepared = await Task.detached(priority: .utility) {
            names.compactMap { name -> (String, UIImage, Data)? in
                guard let image = UIImage(named: name) else { return nil }
                let full = image.upright()
                guard let data = full.compressedReferenceJPEG() else { return nil }
                let display = full.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)
                return (name, display, data)
            }
        }.value
        for (name, display, data) in prepared {
            addReference(ReferencePhoto(image: display, bundledAssetName: name), imageData: data)
        }
    }

    func activateBundledSample(named: String) {
        guard let index = references.firstIndex(where: { $0.bundledAssetName == named }) else { return }
        activeReferenceIndex = index
        persistManifest()
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
            let subject = CGRect(
                x: spec.subjectLeft,
                y: spec.subjectTop,
                width: spec.subjectWidth,
                height: spec.subjectHeight
            )
            let cutout = await personSegmenter.cutout(
                from: full.image,
                quality: .balanced,
                subjectNormalized: subject
            )
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
                    spec: photo.spec,
                    bundledAssetName: photo.bundledAssetName,
                    isFavorite: photo.isFavorite ? true : nil,
                    useCount: photo.useCount > 0 ? photo.useCount : nil,
                    lastUsedAt: photo.lastUsedAt
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

    /// Bundled samples not yet in the library. Empty-state and the in-grid
    /// "Add sample references" row both key off this.
    var missingBundledSampleNames: [String] {
        let have = Set(references.compactMap(\.bundledAssetName))
        return SampleReferencePack.assetNames.filter { !have.contains($0) }
    }

    /// Imports remaining bundled stills through the normal pipeline.
    /// `preferring` is inserted last so it becomes the active reference.
    func importBundledSamples(preferring selected: String? = nil) {
        let have = Set(references.compactMap(\.bundledAssetName))
        var names = SampleReferencePack.assetNames.filter { !have.contains($0) }
        if let selected {
            names.removeAll { $0 == selected }
            if !have.contains(selected) {
                names.append(selected)
            }
        }
        guard !names.isEmpty else { return }
        Task {
            var importedAny = false
            for name in names {
                guard let pair = await Task.detached(priority: .utility, operation: {
                    guard
                        let image = UIImage(named: name),
                        let data = image.compressedReferenceJPEG(),
                        let raw = UIImage(data: data)
                    else { return nil as (Data, UIImage)? }
                    return (data, raw)
                }).value else {
                    #if DEBUG
                    print("SampleReferencePack: missing asset \(name)")
                    #endif
                    continue
                }
                importedAny = true
                importReference(raw: pair.1, data: pair.0, bundledAssetName: name)
            }
            if !importedAny {
                showTransientNotice("Couldn't load sample photos")
            }
        }
    }

    /// References Vision couldn't find a person in — can't drive camera
    /// coaching, shown separately so they don't spin in "Analyzing…" forever.
    var noSubjectReferences: [ReferencePhoto] {
        references.filter { $0.analysisFailed }
    }

    /// Storage → Clear Imported References. Curated Explore photos stay.
    func clearImportedReferences() {
        for photo in importedReferences {
            removeReference(id: photo.id)
        }
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

    /// Single-shot path: downsamples off-main so a full-res capture never freezes the viewfinder / gallery on insert.
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
        rollSessionIfStale()
        let shot = CapturedPhoto(image: display, referenceID: referenceID, burstID: burstID)
        capturedShots.insert(shot, at: 0)

        // Temporary full-size copy for share / Add to References / retry;
        // a failure here only costs full resolution, so it stays silent.
        Task.detached(priority: .utility) { [captureCache] in
            guard let data = image.jpegData(compressionQuality: 0.92) else { return }
            captureCache.saveImageData(data, id: shot.id)
        }

        Task.detached(priority: .utility) {
            let result = await PhotoLibrarySaver.save(image)
            await MainActor.run {
                switch result {
                // Only a confirmed Photos save counts toward the session —
                // a failed save must not read as saved.
                case .saved(let assetID): self.noteSessionSaved(id: shot.id, photosAssetID: assetID)
                case .deniedOrRestricted: self.notePhotoLibraryDenied()
                case .failed:             self.failedSaveShotID = shot.id
                }
            }
        }
        return shot.id
    }

    /// A capture whose Photos save failed; the camera asks Try Again /
    /// Discard Photo (Paper "Photo save failed").
    @Published var failedSaveShotID: UUID?

    func retryFailedSave() {
        guard let id = failedSaveShotID else { return }
        failedSaveShotID = nil
        Task {
            guard let image = await loadFullShot(id: id) ?? capturedShots.first(where: { $0.id == id })?.image
            else { return }
            switch await PhotoLibrarySaver.save(image) {
            case .saved(let assetID): noteSessionSaved(id: id, photosAssetID: assetID)
            case .deniedOrRestricted: notePhotoLibraryDenied()
            case .failed:             failedSaveShotID = id
            }
        }
    }

    func discardFailedSave() {
        guard let id = failedSaveShotID else { return }
        failedSaveShotID = nil
        removeCapturedShot(id: id)
    }

    /// Re-runs Vision for a reference ("Couldn't prepare reference" → Try Again).
    func retryAnalysis(id: UUID) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].analysisFailed = false
        references[index].spec = nil
        scheduleRestoreAnalysis(activeID: id, queuedIDs: [], yieldForCamera: false)
    }

    enum CaptureDeleteOutcome: Equatable {
        case deleted(Int)
        /// The user tapped Don't Allow on the system delete confirmation.
        case cancelled
        case photosDenied
        case failed
    }

    /// Deletes shots from the camera roll (the system asks to confirm; they
    /// go to Recently Deleted) and then from the session. Shots whose save
    /// never landed have no asset and are only removed from the session.
    func deleteCapturedShots(ids: [UUID]) async -> CaptureDeleteOutcome {
        let wanted = Set(ids)
        let shots = capturedShots.filter { wanted.contains($0.id) }
        guard !shots.isEmpty else { return .deleted(0) }
        switch await PhotoLibrarySaver.deleteAssets(localIdentifiers: shots.compactMap(\.photosAssetID)) {
        case .deleted:
            capturedShots.removeAll { wanted.contains($0.id) }
            syncSessionIDs()
            deleteCachedCaptures(shots.map(\.id))
            return .deleted(shots.count)
        case .cancelled:          return .cancelled
        case .deniedOrRestricted: return .photosDenied
        case .failed:             return .failed
        }
    }

    func removeCapturedShot(id: UUID) {
        capturedShots.removeAll { $0.id == id }
        syncSessionIDs()
        deleteCachedCaptures([id])
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
        persistSessionManifest()
    }

    /// Resolves a captured shot's reference, tolerating deletion of the reference since.
    func reference(for id: UUID?) -> ReferencePhoto? {
        guard let id else { return nil }
        return references.first { $0.id == id }
    }

    /// Full-resolution capture from the session cache (memory holds
    /// display-sized bitmaps). Nil once the session's cache is gone.
    func loadFullShot(id: UUID) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { [captureCache] in
            captureCache.loadFullImage(id: id)
        }.value
    }

    /// Launch: brings back a session that was still open when iOS closed
    /// the app (last capture within `sessionInactivityLimit`); otherwise
    /// clears the cache. Also removes stores from pre-redesign builds.
    func restoreSessionFromPreviousLaunch() async {
        let limit = Self.sessionInactivityLimit
        let restored = await Task.detached(priority: .utility) { [captureCache] in
            captureCache.restoreOpenSession(limit: limit)
        }.value
        guard let restored, capturedShots.isEmpty else { return }
        capturedShots = restored.shots.map {
            CapturedPhoto(
                id: $0.shot.id, image: $0.image, capturedAt: $0.shot.capturedAt,
                referenceID: $0.shot.referenceID, burstID: $0.shot.burstID,
                isBurstBest: $0.shot.isBurstBest,
                photosAssetID: $0.shot.photosAssetID
            )
        }
        sessionShotIDs = capturedShots.map(\.id)
        lastSessionCaptureAt = restored.lastCaptureAt
    }

    #if DEBUG
    /// Preview hook (`-preview-seed-session`): fakes a capture session from
    /// the reference photos — three singles and a 6-shot burst — so the
    /// session gallery can be checked in the Simulator (no camera there).
    func seedSessionForPreview() {
        guard !references.isEmpty else { return }
        var shots: [CapturedPhoto] = []
        let burstID = UUID()
        for index in 0..<6 {
            let ref = references[index % references.count]
            shots.append(CapturedPhoto(image: ref.image, referenceID: ref.id, burstID: burstID))
        }
        for ref in references.prefix(3) {
            shots.append(CapturedPhoto(image: ref.image, referenceID: ref.id))
        }
        capturedShots.insert(contentsOf: shots, at: 0)
        sessionShotIDs = shots.map(\.id)
        lastSessionCaptureAt = Date()
    }

    /// UI-test hook (`-uitest-seed-references` launch argument): the curated
    /// set plus one import, in memory only — no disk writes, no Vision, and
    /// no sample auto-import (nothing is missing).
    func seedReferencesForUITests() {
        var seeded: [ReferencePhoto] = SampleReferencePack.assetNames.compactMap { name in
            guard let image = UIImage(named: name) else { return nil }
            var photo = ReferencePhoto(image: image, bundledAssetName: name)
            photo.analysisFailed = true
            return photo
        }
        let size = CGSize(width: 300, height: 400)
        let imported = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        var mine = ReferencePhoto(image: imported)
        mine.analysisFailed = true
        seeded.insert(mine, at: 0)
        references = seeded
        selectedTab = .references
        hasFinishedRestoringReferences = true
    }
    #endif

    /// Surfaces the "photos aren't saving to your camera roll" notice, once
    /// per app launch.
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
