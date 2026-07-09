import SwiftUI
import PhotosUI
import Combine

@MainActor
class ReferencesViewModel: ObservableObject {

    private let analyzer = VisionAnalyzer()
    private let segmenter = PersonSegmenter()

    /// Imports picked photos and kicks off Vision analysis for each.
    /// The photo appears immediately; its style/spec populates silently.
    func importPhotos(items: [PhotosPickerItem], into appState: AppState) {
        Task {
            for item in items {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let raw = UIImage(data: data)
                else { continue }

                let full = raw.upright()
                let display = full.downsampled(maxPixelSize: UIImage.displayMaxPixelSize)

                let photo = ReferencePhoto(image: display)
                appState.addReference(photo, imageData: data)
                let photoId = photo.id
                let imageData = data

                Task.detached(priority: .userInitiated) {
                    let spec = await self.analyzer.analyze(image: full, imageData: imageData)
                    await MainActor.run {
                        if let spec {
                            appState.updateSpec(for: photoId, spec: spec)
                        } else {
                            appState.markAnalysisFailed(for: photoId)
                        }
                    }
                    // Person confirmed by the spec; cut them out for the ghost overlay.
                    guard spec != nil,
                          let cutout = await self.segmenter.cutout(from: full)
                    else { return }
                    let displayCutout = cutout.downsampled(maxPixelSize: UIImage.overlayMaxPixelSize)
                    await MainActor.run {
                        appState.updateCutout(for: photoId, cutout: displayCutout)
                    }
                }
            }
        }
    }
}
