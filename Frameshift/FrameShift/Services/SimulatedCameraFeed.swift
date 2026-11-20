#if DEBUG && targetEnvironment(simulator)
import UIKit
import CoreVideo

/// Simulator-only stand-in for the camera (debug builds only; never ships).
/// Feeds a still photo through the same paths as the real session: the
/// preview layer, `onVideoFrame` (so live Vision, guides and coaching run),
/// and `capturePhoto`.
///
/// Launch arguments:
///   -frameshift.simCamera <asset name or absolute path>   e.g. SampleRefBeachWalk
///                         or `reference` to show the active reference itself
///   -frameshift.simCameraShift "dx,dy,scale"               e.g. "0.08,0.04,1.1"
/// `dx`/`dy` move the scene as a fraction of the frame; `scale` zooms in.
/// They put the subject off target, so coaching has something to say.
final class SimulatedCameraFeed {
    static let shared: SimulatedCameraFeed? = SimulatedCameraFeed()
    static let frameChanged = Notification.Name("SimulatedCameraFeed.frameChanged")

    private let lock = NSLock()
    private var _frame: UIImage
    private var buffer: CVPixelBuffer?
    private var timer: DispatchSourceTimer?
    private let followsReference: Bool
    private var dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1

    /// Upright 3:4 frame, like the back camera's 4:3 sensor held in portrait.
    var frame: UIImage { lock.withLock { _frame } }

    private init?() {
        guard let source = UserDefaults.standard.string(forKey: "frameshift.simCamera") else { return nil }
        followsReference = source == "reference"
        if let shift = UserDefaults.standard.string(forKey: "frameshift.simCameraShift") {
            let parts = shift.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count > 0 { dx = parts[0] }
            if parts.count > 1 { dy = parts[1] }
            if parts.count > 2 { scale = max(parts[2], 0.2) }
        }
        let image = followsReference ? nil : (UIImage(named: source) ?? UIImage(contentsOfFile: source))
        if !followsReference && image == nil { return nil }
        _frame = UIImage()
        show(image)
    }

    /// With `-frameshift.simCamera reference`, the feed shows the reference
    /// being recreated (shifted, so coaching has something to fix).
    func follow(reference image: UIImage) {
        guard followsReference else { return }
        show(image)
    }

    private func show(_ image: UIImage?) {
        let size = CGSize(width: 1080, height: 1440)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let (dx, dy, scale) = (dx, dy, scale)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            guard let image else { return }
            // Aspect-fill, then the requested zoom and shift.
            let fill = max(size.width / image.size.width, size.height / image.size.height) * scale
            let drawn = CGSize(width: image.size.width * fill, height: image.size.height * fill)
            let origin = CGPoint(
                x: (size.width - drawn.width) / 2 + dx * size.width,
                y: (size.height - drawn.height) / 2 + dy * size.height
            )
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        // The sensor delivers landscape buffers that LiveVisionAnalyzer reads
        // with orientation .right — so store the frame rotated 90° CCW.
        let pixelBuffer = rendered.cgImage.flatMap(Self.landscapeBuffer(from:))
        lock.withLock {
            _frame = rendered
            buffer = pixelBuffer
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.frameChanged, object: nil)
        }
    }

    /// ~15 fps, like a throttled camera feed.
    func start(on queue: DispatchQueue, deliver: @escaping (CVPixelBuffer) -> Void) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(66))
        timer.setEventHandler { [weak self] in
            guard let buffer = self?.lock.withLock({ self?.buffer }) else { return }
            deliver(buffer)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// The part of the frame visible in a layer of `bounds` that aspect-fills it.
    func capture(visibleIn bounds: CGSize) -> UIImage {
        let frame = frame
        guard bounds.width > 0, bounds.height > 0, let cg = frame.cgImage else { return frame }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let fill = max(bounds.width / w, bounds.height / h)
        let crop = CGRect(
            x: (w - bounds.width / fill) / 2,
            y: (h - bounds.height / fill) / 2,
            width: bounds.width / fill,
            height: bounds.height / fill
        ).integral
        guard let cropped = cg.cropping(to: crop) else { return frame }
        return UIImage(cgImage: cropped)
    }

    private static func landscapeBuffer(from image: CGImage) -> CVPixelBuffer? {
        let width = image.height, height = image.width
        var out: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &out) == kCVReturnSuccess,
              let out else { return nil }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(out), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(out),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Rotate 90° CCW: the image's top edge becomes the buffer's left edge,
        // which `.right` rotates back to upright.
        ctx.translateBy(x: CGFloat(width), y: 0)
        ctx.rotate(by: .pi / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return out
    }
}
#endif

#if targetEnvironment(simulator)
import Vision
import CoreML

extension VNRequest {
    /// The Simulator can't create Neural Engine / GPU inference contexts
    /// ("Could not create inference context"), so run Vision on the CPU.
    nonisolated static func simulatorCPU<S: Sequence>(_ requests: S) where S.Element == VNRequest {
        let cpu = MLComputeDevice.allComputeDevices.first { if case .cpu = $0 { return true } else { return false } }
        for request in requests {
            for stage in (try? request.supportedComputeStageDevices.keys).map(Array.init) ?? [.main] {
                request.setComputeDevice(cpu, for: stage)
            }
        }
    }
}
#endif
