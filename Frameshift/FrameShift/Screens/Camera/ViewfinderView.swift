import SwiftUI
import AVFoundation

/// UIViewRepresentable that hosts an AVCaptureVideoPreviewLayer.
struct ViewfinderView: UIViewRepresentable {
    let camera: CameraService

    func makeUIView(context: Context) -> _PreviewView {
        let view = _PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        camera.previewLayer = view.previewLayer
        return view
    }

    func updateUIView(_ uiView: _PreviewView, context: Context) {}
}

final class _PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
