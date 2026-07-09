import Vision
import CoreVideo
import ImageIO

/// Runs live human detection on camera frames (~1 fps).
final class LiveVisionAnalyzer {

    private var lastProcessed = Date.distantPast
    private let interval: TimeInterval = 1.0

    private(set) var liveSubject: CGRect?
    private(set) var lightingScore: Double = 0.5
    /// Oriented buffer dimensions Vision uses (matches preview aspect-fill mapping).
    private(set) var contentSize: CGSize = .zero

    var onUpdate: ((CGRect?, Double, CGSize) -> Void)?

    func process(pixelBuffer: CVPixelBuffer, isFrontCamera: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessed) >= interval else { return }
        lastProcessed = now

        let orientation: CGImagePropertyOrientation = isFrontCamera ? .leftMirrored : .right
        let bufferW = CVPixelBufferGetWidth(pixelBuffer)
        let bufferH = CVPixelBufferGetHeight(pixelBuffer)
        let orientedSize = Self.orientedContentSize(
            bufferWidth: bufferW,
            bufferHeight: bufferH,
            orientation: orientation
        )

        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([request])
            } catch {
                self.publish(subject: nil, lighting: 0.4, contentSize: orientedSize)
                return
            }

            guard let obs = request.results?.first else {
                self.publish(subject: nil, lighting: 0.4, contentSize: orientedSize)
                return
            }

            let box = obs.boundingBox
            let uiRect = CGRect(
                x: box.minX,
                y: 1.0 - box.maxY,
                width: box.width,
                height: box.height
            )
            let lighting = self.estimateLighting(buffer: pixelBuffer, subject: uiRect)
            self.publish(subject: uiRect, lighting: lighting, contentSize: orientedSize)
        }
    }

    // MARK: - Private

    private static func orientedContentSize(
        bufferWidth: Int,
        bufferHeight: Int,
        orientation: CGImagePropertyOrientation
    ) -> CGSize {
        switch orientation {
        case .right, .left, .leftMirrored, .rightMirrored:
            return CGSize(width: CGFloat(bufferHeight), height: CGFloat(bufferWidth))
        default:
            return CGSize(width: CGFloat(bufferWidth), height: CGFloat(bufferHeight))
        }
    }

    private func publish(subject: CGRect?, lighting: Double, contentSize: CGSize) {
        liveSubject = subject
        lightingScore = lighting
        self.contentSize = contentSize
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onUpdate?(subject, lighting, contentSize)
        }
    }

    /// Average luma in the subject region as a proxy for exposure quality.
    private func estimateLighting(buffer: CVPixelBuffer, subject: CGRect) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return 0.5 }
        let width  = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        let x0 = max(0, Int(subject.minX * CGFloat(width)))
        let y0 = max(0, Int(subject.minY * CGFloat(height)))
        let x1 = min(width - 1, Int(subject.maxX * CGFloat(width)))
        let y1 = min(height - 1, Int(subject.maxY * CGFloat(height)))
        guard x1 > x0, y1 > y0 else { return 0.5 }

        var sum: Double = 0
        var count = 0
        let step = 8
        for y in stride(from: y0, to: y1, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: x0, to: x1, by: step) {
                let px = row.advanced(by: x * 4)
                let b = Double(px[0]), g = Double(px[1]), r = Double(px[2])
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
            }
        }
        guard count > 0 else { return 0.5 }
        let avg = sum / Double(count) / 255.0
        if avg < 0.18 || avg > 0.92 { return 0.25 }
        if avg < 0.28 || avg > 0.82 { return 0.45 }
        return 0.75
    }
}
