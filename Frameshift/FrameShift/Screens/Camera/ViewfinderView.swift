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
        #if DEBUG && targetEnvironment(simulator)
        if let feed = SimulatedCameraFeed.shared {
            let still = CALayer()
            still.contents = feed.frame.cgImage
            still.contentsGravity = .resizeAspectFill
            still.masksToBounds = true
            view.layer.addSublayer(still)
            view.simulatedFeedLayer = still
            view.feedObserver = NotificationCenter.default.addObserver(
                forName: SimulatedCameraFeed.frameChanged, object: nil, queue: .main
            ) { [weak still] _ in
                still?.contents = SimulatedCameraFeed.shared?.frame.cgImage
            }
        }
        #endif
        return view
    }

    func updateUIView(_ uiView: _PreviewView, context: Context) {}
}

final class _PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// Simulator-only still feed (see SimulatedCameraFeed).
    var simulatedFeedLayer: CALayer?
    var feedObserver: NSObjectProtocol?

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        simulatedFeedLayer?.frame = bounds
        CATransaction.commit()
    }
}
