import Vision
import CoreVideo
import ImageIO

/// Extracts a person's silhouette contour from a single live camera frame,
/// for the brief "framing matched" flash overlay. Person segmentation is
/// significantly heavier than the bounding-box detection LiveVisionAnalyzer
/// runs continuously, so this only runs once per framing-match event (see
/// CameraViewModel's framingOK transition handling), never every frame.
/// nonisolated: pure Vision work, runs on background tasks.
nonisolated struct LiveSilhouetteExtractor {

    /// Returns a CGPath in the same oriented, bottom-left-origin normalized
    /// space LiveVisionAnalyzer's `contentSize` describes, or nil if no
    /// person contour was found.
    func extractSilhouette(from pixelBuffer: CVPixelBuffer, isFrontCamera: Bool) async -> CGPath? {
        let orientation: CGImagePropertyOrientation = isFrontCamera ? .leftMirrored : .right

        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .fast   // one-shot on a match event, but still live-frame latency
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let segmentationHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]
        )
        do {
            try segmentationHandler.perform([segmentationRequest])
        } catch {
            return nil
        }
        guard let maskBuffer = segmentationRequest.results?.first?.pixelBuffer else { return nil }

        // The mask is already oriented upright by the segmentation request above.
        let contourRequest = VNDetectContoursRequest()
        contourRequest.contrastAdjustment = 1.5
        contourRequest.detectsDarkOnLight = false   // person mask: bright shape on a dark background
        contourRequest.maximumImageDimension = 512

        let contourHandler = VNImageRequestHandler(cvPixelBuffer: maskBuffer, orientation: .up, options: [:])
        do {
            try contourHandler.perform([contourRequest])
        } catch {
            return nil
        }
        guard
            let observation = contourRequest.results?.first,
            let silhouette = observation.topLevelContours.max(by: { $0.pointCount < $1.pointCount }),
            silhouette.pointCount > 8
        else { return nil }

        return silhouette.normalizedPath
    }
}
