import AVFoundation
import UIKit
import Combine

/// Manages capture session, multi-lens zoom (0.5×–3×), and live frame delivery.
class CameraService: NSObject, ObservableObject {

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "frameshift.session")
    private let videoQueue = DispatchQueue(label: "frameshift.video", qos: .userInitiated)

    private var videoInput: AVCaptureDeviceInput?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var captureCompletion: ((UIImage?) -> Void)?
    private var captureCropRect: CGRect?
    private var displayZoom: CGFloat = 1
    private var subjectAreaObserver: NSObjectProtocol?
    private var interruptionEndedObserver: NSObjectProtocol?

    /// Set by ViewfinderView. The preview aspect-fills the screen, so it shows only part of
    /// the 4:3 sensor frame; captures are cropped to this layer's visible region so the saved
    /// photo matches what the user framed.
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    /// Called on `videoQueue` with each sampled frame (throttled to ~1 fps by the consumer).
    var onVideoFrame: ((CVPixelBuffer) -> Void)?

    enum AuthorizationState { case unknown, authorized, denied }

    @Published var isRunning = false
    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var hasUltraWide = false

    /// Derived from the back virtual device's lens switchover points, like the
    /// native app (e.g. [0.5, 1, 2, 5] on a 5× telephoto body).
    @Published private(set) var backZoomLevels: [CGFloat] = [0.5, 1, 2]
    static let frontZoomLevels: [CGFloat] = [1, 2, 3]

    /// Back camera as a single virtual device (triple/dual-wide). All lenses
    /// live behind one videoZoomFactor, so zoom ramps smoothly across the
    /// ultrawide→wide→tele boundaries instead of hard-swapping inputs.
    private var backDevice: AVCaptureDevice?
    /// videoZoomFactor per 1× of display zoom: 2 when the widest constituent
    /// is the ultrawide (its native FOV is 0.5×), 1 for wide-only fallback.
    private var backZoomFactorScale: CGFloat = 1

    // MARK: Setup

    /// Safe to call repeatedly (e.g. on every foreground return): re-resolves
    /// authorization in case it changed in Settings, and setupSession() is
    /// itself a no-op once the session is already running.
    func configure() {
        observeInterruptions()
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            authorizationState = .authorized
        case .denied, .restricted:
            authorizationState = .denied
            return
        case .notDetermined:
            break
        @unknown default:
            authorizationState = .denied
            return
        }
        Task {
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run { self.authorizationState = granted ? .authorized : .denied }
                guard granted else { return }
            }
            sessionQueue.async { self.setupSession() }
        }
    }

    /// Restarts the session after a same-foreground interruption (phone call,
    /// Control Center camera grab) ends. Complements CameraViewModel's
    /// foreground-notification handling, which catches Settings round-trips.
    private func observeInterruptions() {
        if let interruptionEndedObserver { NotificationCenter.default.removeObserver(interruptionEndedObserver) }
        interruptionEndedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.sessionQueue.async {
                guard !self.session.isRunning else { return }
                self.session.startRunning()
                DispatchQueue.main.async { self.isRunning = self.session.isRunning }
            }
        }
    }

    private func setupSession() {
        guard !session.isRunning else { return }

        resolveBackDevice()
        let ultraWideAvailable = hasUltraWide

        session.beginConfiguration()
        session.sessionPreset = .photo
        if let backDevice { swapInput(to: backDevice) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            updateMaxPhotoDimensions()
        }
        if session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        displayZoom = 1
        applyZoom(1, animated: false)

        session.startRunning()
        DispatchQueue.main.async {
            self.isRunning = self.session.isRunning
            self.hasUltraWide = ultraWideAvailable
        }
    }

    /// Picks the most capable back virtual device and derives the display zoom
    /// pills from its lens switchover factors.
    private func resolveBackDevice() {
        let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
            ?? Self.wideDevice(position: .back)
        backDevice = device
        guard let device else { return }

        let hasUltraWideLens = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        backZoomFactorScale = hasUltraWideLens ? 2 : 1
        hasUltraWide = hasUltraWideLens

        var levels: [CGFloat] = hasUltraWideLens ? [0.5, 1, 2] : [1, 2]
        // The last switchover is the telephoto engagement point (e.g. factor 10
        // on a 5× body → display 5×).
        if let teleFactor = device.virtualDeviceSwitchOverVideoZoomFactors.last.map({ CGFloat(truncating: $0) }) {
            let teleDisplay = teleFactor / backZoomFactorScale
            if teleDisplay > 2 { levels.append(teleDisplay) }
        }
        if !hasUltraWideLens && levels.count < 3 { levels.append(3) }
        let resolved = levels
        DispatchQueue.main.async { self.backZoomLevels = resolved }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async {
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: Camera / zoom

    func switchCamera() {
        sessionQueue.async {
            let next: AVCaptureDevice.Position = (self.currentPosition == .back) ? .front : .back
            self.session.beginConfiguration()
            self.currentPosition = next
            let zoom: CGFloat = (next == .back) ? self.displayZoom : max(1, self.displayZoom)
            let device = (next == .back) ? self.backDevice : Self.wideDevice(position: .front)
            if let device { self.swapInput(to: device) }
            self.session.commitConfiguration()
            self.updateMaxPhotoDimensions()
            self.displayZoom = zoom
            self.applyZoom(zoom, animated: false)
            // The incoming device may hold a bias from its last use.
            if let device = self.videoInput?.device, device.exposureTargetBias != 0 {
                do {
                    try device.lockForConfiguration()
                    device.setExposureTargetBias(0)
                    device.unlockForConfiguration()
                } catch { }
            }
            let ultraWideActive = (next == .back) && self.backZoomFactorScale == 2
            DispatchQueue.main.async {
                self.hasUltraWide = ultraWideActive
            }
        }
    }

    /// Display zoom: continuous 0.5×–6×. The virtual device handles lens
    /// switchover internally, so this is cheap enough to call per pinch tick.
    /// `animated` ramps the zoom like the native app's tap-on-a-pill behavior.
    func setZoom(_ factor: CGFloat, animated: Bool = false) {
        sessionQueue.async {
            self.displayZoom = factor
            self.applyZoom(factor, animated: animated)
        }
    }

    // MARK: Focus / exposure

    /// One-shot focus + exposure at a preview-layer point, like the native Camera app.
    /// Continuous auto resumes when the scene changes (subject-area monitoring).
    func focusAndExpose(atLayerPoint point: CGPoint) {
        guard let layer = previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
                // Fresh metering at the new point; any previous drag bias is discarded.
                device.setExposureTargetBias(0)
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
            } catch { }
        }
    }

    /// EV compensation from the exposure drag slider, applied on top of the
    /// tapped point's auto exposure.
    func setExposureBias(_ bias: Float) {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias,
                                  min(bias, device.maxExposureTargetBias))
                device.setExposureTargetBias(clamped)
                device.unlockForConfiguration()
            } catch { }
        }
    }

    private func resetToContinuousAutoFocus() {
        sessionQueue.async {
            guard let device = self.videoInput?.device else { return }
            let center = CGPoint(x: 0.5, y: 0.5)
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = center
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = center
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(0)
                device.isSubjectAreaChangeMonitoringEnabled = false
                device.unlockForConfiguration()
            } catch { }
        }
    }

    private func observeSubjectAreaChanges(for device: AVCaptureDevice) {
        if let observer = subjectAreaObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        subjectAreaObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: nil
        ) { [weak self] _ in
            self?.resetToContinuousAutoFocus()
        }
    }

    func capturePhoto(
        flashMode: AVCaptureDevice.FlashMode = .off,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Visible preview region in normalized capture coordinates.
        // Layer bounds must be read on the main thread, so resolve before hopping queues.
        let cropRect = previewLayer.map {
            $0.metadataOutputRectConverted(fromLayerRect: $0.bounds)
        }
        sessionQueue.async {
            self.captureCompletion = completion
            self.captureCropRect = cropRect
            if let connection = self.photoOutput.connection(with: .video),
               connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (self.currentPosition == .front)
            }

            // Match the native Camera app: HEVC, full resolution, Deep Fusion /
            // Smart HDR via quality prioritization.
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.hevc]
                )
            } else {
                settings = AVCapturePhotoSettings()
            }
            if self.photoOutput.maxPhotoDimensions.width > 0 {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            settings.photoQualityPrioritization = .quality
            // Front camera reports screen-flash support here on modern iPhones.
            if self.photoOutput.supportedFlashModes.contains(flashMode) {
                settings.flashMode = flashMode
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: Zoom

    /// Maps display zoom onto the active device's videoZoomFactor. On the back
    /// virtual device 1× display = factor 2 (the ultrawide's native FOV is
    /// 0.5×), and the device blends lenses itself — which is what makes the
    /// ramped animation seamless across 0.5× → 1× → tele.
    private func applyZoom(_ display: CGFloat, animated: Bool) {
        guard let device = videoInput?.device else { return }
        let scale: CGFloat = (currentPosition == .back) ? backZoomFactorScale : 1
        let target = max(device.minAvailableVideoZoomFactor,
                         min(display * scale, device.maxAvailableVideoZoomFactor))

        do {
            try device.lockForConfiguration()
            if animated {
                // Rate is in doublings/sec; 6 lands a 1×→5× jump in ~0.4s,
                // close to the native app's feel.
                device.ramp(toVideoZoomFactor: target, withRate: 6)
            } else {
                device.videoZoomFactor = target
            }
            device.unlockForConfiguration()
        } catch { }
    }

    /// Requests the largest supported photo dimensions up to 24MP — the native
    /// Camera app's default on 24/48MP-capable sensors. Lens-dependent, so this
    /// re-runs on every lens swap.
    private func updateMaxPhotoDimensions() {
        guard
            session.outputs.contains(photoOutput),
            let device = videoInput?.device
        else { return }

        let cap = 5712 * 4284  // 24MP
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        let best = supported
            .filter { Int($0.width) * Int($0.height) <= cap }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            ?? supported.first

        if let best {
            photoOutput.maxPhotoDimensions = best
        }
    }

    private func swapInput(to device: AVCaptureDevice) {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if let existing = videoInput { session.removeInput(existing) }
        guard session.canAddInput(input) else {
            if let existing = videoInput { session.addInput(existing) }
            return
        }
        session.addInput(input)
        videoInput = input
        observeSubjectAreaChanges(for: device)
    }

    private static func wideDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

// MARK: - Video frames

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onVideoFrame?(buffer)
    }
}

// MARK: - Photo capture

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completion = captureCompletion
        let cropRect = captureCropRect
        captureCompletion = nil
        captureCropRect = nil
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }
        let result = Self.cropped(image, toNormalizedRect: cropRect)
        DispatchQueue.main.async { completion?(result) }
    }

    /// Crops to the preview-visible region. `rect` is in metadata-output space, which matches
    /// the CGImage's unrotated pixel layout, so it applies directly before EXIF orientation.
    private static func cropped(_ image: UIImage, toNormalizedRect rect: CGRect?) -> UIImage {
        guard
            let rect, rect.width > 0, rect.height > 0,
            rect != CGRect(x: 0, y: 0, width: 1, height: 1),
            let cgImage = image.cgImage
        else { return image }

        let pixelRect = CGRect(
            x: rect.origin.x * CGFloat(cgImage.width),
            y: rect.origin.y * CGFloat(cgImage.height),
            width: rect.width * CGFloat(cgImage.width),
            height: rect.height * CGFloat(cgImage.height)
        ).integral

        guard let croppedCG = cgImage.cropping(to: pixelRect) else { return image }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
