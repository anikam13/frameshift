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
        Task {
            var importedAny = false
            for name in SampleReferencePack.assetNames {
                // Decode + re-encode off the main actor; assets are catalog
                // JPEGs, so this is the one full-res pass per sample.
                guard let pair = await Task.detached(priority: .utility, operation: {
                    guard
                        let image = UIImage(named: name),
                        let data = image.jpegData(compressionQuality: 0.92),
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
                appState.importReference(raw: pair.1, data: pair.0)
            }
            if !importedAny {
                await MainActor.run {
                    appState.showTransientNotice("Couldn't load sample photos")
                }
            }
        }
    }
}
