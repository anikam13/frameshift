import Testing
import UIKit
@testable import FrameShift

struct FilterPresetStoreTests {

    @Test func roundTripSavesAndRestoresPresets() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilterPresetStore(directory: directory)

        let first = UUID()
        let second = UUID()
        #expect(store.saveImageData(Self.jpegData(.systemOrange), id: first))
        #expect(store.saveImageData(Self.jpegData(.systemTeal), id: second))
        store.saveManifest(FilterPresetStore.Manifest(presets: [
            .init(id: first, name: "Preset 1", createdAt: Date()),
            .init(id: second, name: "Preset 2", createdAt: Date())
        ]))

        let restored = store.loadAll()
        #expect(restored.map(\.id) == [first, second])
        #expect(restored.map(\.name) == ["Preset 1", "Preset 2"])
    }

    @Test func deletedPresetDoesNotRestore() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilterPresetStore(directory: directory)

        let kept = UUID()
        let deleted = UUID()
        store.saveImageData(Self.jpegData(.systemOrange), id: kept)
        store.saveImageData(Self.jpegData(.systemTeal), id: deleted)
        store.saveManifest(FilterPresetStore.Manifest(presets: [
            .init(id: kept, name: "Preset 1", createdAt: Date()),
            .init(id: deleted, name: "Preset 2", createdAt: Date())
        ]))

        // Mirrors AppState.removeFilterPreset: drop the image, rewrite the manifest.
        store.deleteImage(id: deleted)
        store.saveManifest(FilterPresetStore.Manifest(presets: [
            .init(id: kept, name: "Preset 1", createdAt: Date())
        ]))

        #expect(store.loadAll().map(\.id) == [kept])
    }

    @Test func manifestEntryWithMissingImageIsDropped() throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilterPresetStore(directory: directory)

        let missing = UUID()
        store.saveManifest(FilterPresetStore.Manifest(presets: [
            .init(id: missing, name: "Preset 1", createdAt: Date())
        ]))

        #expect(store.loadAll().isEmpty)
    }

    // MARK: Helpers

    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FilterPresetStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func jpegData(_ color: UIColor) -> Data {
        let size = CGSize(width: 32, height: 32)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
