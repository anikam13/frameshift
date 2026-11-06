@preconcurrency import Vision
@preconcurrency import CoreVideo
import ImageIO

/// Runs live human detection + body pose on camera frames (~3 fps).
/// nonisolated: frame callbacks arrive on the capture video queue; Vision
/// work stays off MainActor (project default isolation is MainActor).
nonisolated final class LiveVisionAnalyzer: @unchecked Sendable {

    /// One live frame's subject, normalized UIKit coordinates in oriented
    /// buffer space.
    struct Subject {
        /// Full-body bounding box; nil when no human was detected.
        var box: CGRect?
        /// Head-guide center computed with HeadBoundsEstimator's pose tier —
        /// the same convention the reference circle was built with, so
        /// comparing the two carries no systematic offset. nil when body
        /// pose failed (subject too small / mostly out of frame).
        var headCenter: CGPoint?
        /// Pose shoulders; nil when pose failed or a joint was occluded.
        var leftShoulder: CGPoint?
        var rightShoulder: CGPoint?

        var isEmpty: Bool { box == nil && headCenter == nil }
    }

    private var lastProcessed = Date.distantPast
    /// ~3 fps: fast enough that framing feedback tracks a moving subject;
    /// rectangles + pose at this cadence stay a rounding error next to the
    /// preview pipeline itself.
    private let interval: TimeInterval = 0.35

    var onUpdate: ((Subject, Double, CGSize) -> Void)?

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

        let rectsRequest = VNDetectHumanRectanglesRequest()
        rectsRequest.upperBodyOnly = false
        let poseRequest = VNDetectHumanBodyPoseRequest()

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )

        // CVPixelBuffer isn't Sendable; the utility hop only reads it under
        // the lock in estimateLighting, after Vision has already retained it.
        nonisolated(unsafe) let lightingBuffer = pixelBuffer

        // Utility: live pose must not outrank AVCaptureSession / restore analysis.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([rectsRequest, poseRequest])
            } catch {
                self.publish(subject: Subject(), lighting: 0.4, contentSize: orientedSize)
                return
            }

            var subject = Subject()
            if let obs = rectsRequest.results?.first {
                let box = obs.boundingBox
                subject.box = CGRect(
                    x: box.minX,
                    y: 1.0 - box.maxY,
                    width: box.width,
                    height: box.height
                )
            }
            if let pose = poseRequest.results?.first {
                subject.leftShoulder = Self.uiKitPoint(pose, .leftShoulder)
                subject.rightShoulder = Self.uiKitPoint(pose, .rightShoulder)
                // Head center needs at least nose + neck, mirroring the
                // reference-side estimator's pose-tier requirements.
                if let nose = Self.uiKitPoint(pose, .nose),
                   let neck = Self.uiKitPoint(pose, .neck) {
                    let head = HeadBoundsEstimator.estimate(
                        faceRect: nil,
                        landmarks: nil,
                        pose: HeadBoundsEstimator.PoseInput(
                            nose: nose,
                            neck: neck,
                            leftEye: Self.uiKitPoint(pose, .leftEye),
                            rightEye: Self.uiKitPoint(pose, .rightEye)
                        ),
                        upperBody: subject.box ?? CGRect(x: 0, y: 0, width: 1, height: 1),
                        imageSize: orientedSize
                    )
                    subject.headCenter = CGPoint(x: head.centerX, y: head.centerY)
                }
            }

            let lighting = subject.box.map {
                self.estimateLighting(buffer: lightingBuffer, subject: $0)
            } ?? 0.4
            self.publish(subject: subject, lighting: lighting, contentSize: orientedSize)
        }
    }

    private static func uiKitPoint(
        _ pose: VNHumanBodyPoseObservation,
        _ joint: VNHumanBodyPoseObservation.JointName
    ) -> CGPoint? {
        guard let p = try? pose.recognizedPoint(joint), p.confidence > 0.25 else { return nil }
        return CGPoint(x: p.location.x, y: 1.0 - p.location.y)
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

    private func publish(subject: Subject, lighting: Double, contentSize: CGSize) {
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
