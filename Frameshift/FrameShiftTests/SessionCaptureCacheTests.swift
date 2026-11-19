import UIKit
import Testing
@testable import FrameShift

/// Session restore after iOS closes the app (D-2, D-25). Serialized: the
/// cache lives in one shared Caches folder.
@Suite(.serialized)
struct SessionCaptureCacheTests {

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
        }.jpegData(compressionQuality: 0.8)!
    }

    private func writeSession(lastCaptureAt: Date, ids: [UUID], withImages: [UUID]) -> SessionCaptureCache {
        let cache = SessionCaptureCache()
        cache.removeAll()
        for id in withImages { cache.saveImageData(jpeg(), id: id) }
        cache.saveManifest(.init(
            lastCaptureAt: lastCaptureAt,
            shots: ids.map { .init(id: $0, capturedAt: lastCaptureAt, referenceID: nil, burstID: nil, isBurstBest: false) }
        ))
        return cache
    }

    @Test func openSessionComesBackAfterRelaunch() {
        let ids = [UUID(), UUID()]
        let cache = writeSession(lastCaptureAt: Date().addingTimeInterval(-60), ids: ids, withImages: ids)
        let restored = cache.restoreOpenSession(limit: 30 * 60)
        #expect(restored?.shots.map(\.shot.id) == ids)
        #expect(cache.loadFullImage(id: ids[0]) != nil)
        cache.removeAll()
    }

    @Test func staleSessionIsClearedOnLaunch() {
        let id = UUID()
        let cache = writeSession(lastCaptureAt: Date().addingTimeInterval(-31 * 60), ids: [id], withImages: [id])
        #expect(cache.restoreOpenSession(limit: 30 * 60) == nil)
        #expect(cache.loadFullImage(id: id) == nil)
    }

    @Test func shotsWhoseFilesWerePurgedAreDropped() {
        let kept = UUID(), purged = UUID()
        let cache = writeSession(lastCaptureAt: Date(), ids: [kept, purged], withImages: [kept])
        let restored = cache.restoreOpenSession(limit: 30 * 60)
        #expect(restored?.shots.map(\.shot.id) == [kept])
        cache.removeAll()
    }

    @Test func photosAssetIDSurvivesRestore() {
        let id = UUID()
        let cache = SessionCaptureCache()
        cache.removeAll()
        cache.saveImageData(jpeg(), id: id)
        cache.saveManifest(.init(
            lastCaptureAt: Date(),
            shots: [.init(id: id, capturedAt: Date(), referenceID: nil, burstID: nil,
                          isBurstBest: false, photosAssetID: "ABC/L0/001")]
        ))
        #expect(cache.restoreOpenSession(limit: 30 * 60)?.shots.first?.shot.photosAssetID == "ABC/L0/001")
        cache.removeAll()
    }

    /// Manifests written before Delete (1.2) have no asset id and must still load.
    @Test func legacyManifestWithoutAssetIDDecodes() throws {
        let json = #"{"lastCaptureAt":0,"shots":[{"id":"\#(UUID().uuidString)","capturedAt":0,"isBurstBest":false}]}"#
        let manifest = try JSONDecoder().decode(SessionCaptureCache.Manifest.self, from: Data(json.utf8))
        #expect(manifest.shots.first?.photosAssetID == nil)
    }

    @Test func noManifestMeansNoSession() {
        let cache = SessionCaptureCache()
        cache.removeAll()
        cache.saveImageData(jpeg(), id: UUID())   // orphan file
        #expect(cache.restoreOpenSession(limit: 30 * 60) == nil)
    }
}
