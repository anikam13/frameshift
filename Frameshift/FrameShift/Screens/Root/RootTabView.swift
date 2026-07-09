import SwiftUI

/// App shell — the camera IS the app, like the native Camera. Mode switching
/// (REFERENCE · CAMERA) lives in CameraView's bottom pill, and the gallery
/// opens from the bottom-left thumbnail.
struct RootTabView: View {
    var body: some View {
        CameraView()
    }
}
