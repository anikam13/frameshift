import SwiftUI
import PhotosUI
import Combine

@MainActor
class ReferencesViewModel: ObservableObject {

    /// Imports picked photos and kicks off Vision analysis for each.
    /// The photo appears immediately; its style/spec populates silently.
    func importPhotos(items: [PhotosPickerItem], into appState: AppState) {
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                // Decode off-main — PhotosPicker payloads can be multi‑MB HEICs.
                guard let raw = await Task.detached(priority: .utility, operation: {
                    UIImage(data: data)
                }).value else { continue }
                appState.importReference(raw: raw, data: data)
            }
        }
    }

    /// Imports the bundled starter pack through the normal pipeline, so the
    /// samples are analyzed, persisted, and deletable exactly like photos
    /// the user picked. Fully offline — the images ship in Assets.xcassets
    /// (see SampleReferencePack for provenance).
    func importSamplePack(into appState: AppState) {
        appState.importBundledSamples()
    }
}
