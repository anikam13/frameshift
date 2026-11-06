import Vision
import UIKit
import ImageIO

/// nonisolated: Vision batch must never hop to MainActor (project default
/// isolation is MainActor; analysis runs on VisionWorkQueue / detached tasks).
nonisolated struct VisionAnalyzer {

    /// Analyze a reference photo and return a ShotSpec. Background thread only.
    /// The image must already be upright (`UIImage.upright()`); all stored
    /// normalized values are in upright image space, UIKit origin (FR-14).
    func analyze(image: UIImage, imageData: Data? = nil) async -> ShotSpec? {
        guard let cgImage = image.cgImage else { return nil }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false

        let upperRequest = VNDetectHumanRectanglesRequest()
        upperRequest.upperBodyOnly = true

        let horizonRequest = VNDetectHorizonRequest()
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let faceRectRequest = VNDetectFaceRectanglesRequest()
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()

        // FR-12: one batch per import. Landmarks piggyback on the same pass —
        // when no face exists the request just returns empty.
        do {
            try handler.perform([
                bodyRequest, upperRequest, horizonRequest, poseRequest,
                faceRectRequest, faceLandmarksRequest
            ])
        } catch {
            return nil
        }

        let bodyObs = bodyRequest.results?.first
        let upperObs = upperRequest.results?.first
        let subjectAnchor = (upperObs ?? bodyObs).map { uiKitBox($0.boundingBox) }
        let faceObs = primaryFace(
            rects: faceRectRequest.results,
            withLandmarks: faceLandmarksRequest.results,
            near: subjectAnchor
        )

        // A usable spec needs a body or at least a face (US-107: face-less
        // imports fall back; person-less imports return nil as before).
        guard bodyObs != nil || faceObs != nil else { return nil }

        let faceBox = faceObs.map { uiKitBox($0.boundingBox) }
        let body = bodyObs.map { uiKitBox($0.boundingBox) } ?? syntheticBody(from: faceBox!)
        let upper = upperObs.map { uiKitBox($0.boundingBox) }
            ?? faceBox.map { syntheticUpperBody(from: $0) }
            ?? body

        let pose = poseRequest.results?.first
        let landmarks = extractLandmarks(from: pose, upperBody: upper)
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)

        let head = HeadBoundsEstimator.estimate(
            faceRect: faceBox.map(\.cgRect),
            landmarks: faceObs.flatMap { landmarkExtremes(from: $0, pixelSize: pixelSize) },
            pose: pose != nil ? HeadBoundsEstimator.PoseInput(
                nose: landmarks.nose,
                neck: landmarks.neck,
                leftEye: landmarks.leftEye,
                rightEye: landmarks.rightEye
            ) : nil,
            upperBody: upper.cgRect,
            imageSize: pixelSize
        )

        // FR-9/FR-10: reference camera roll, preferring EXIF attitude over
        // horizon detection (RollEstimator) since most references have no
        // visible horizon for VNDetectHorizonRequest to find.
        let exif = ReferenceEXIF.parse(image: image, imageData: imageData)
        let horizonObs = horizonRequest.results?.first
        let roll = RollEstimator.estimate(exif: exif, horizonObservation: horizonObs)
        let targetRoll = roll.roll
        let rollConfidence = roll.confidence
        let rollSource: ShotSpec.RollSource = {
            switch roll.tier {
            case .exifAttitude:     return .exifAttitude
            case .horizonDetection: return .horizonDetection
            case .none:             return .none
            }
        }()

        let pitch = PitchEstimator.estimate(
            exif: exif,
            pose: pose,
            horizonAngle: roll.roll,
            subjectCenterY: body.centerY,
            imageSize: pixelSize
        )

        let recommendedZoom = inferZoom(exif: exif, subjectBox: body, faceBox: faceBox)
        let coverage = bodyCoverage(from: pose)
        let look = angleLook(from: pose, imageSize: pixelSize)

        return ShotSpec(
            subjectTop: body.top, subjectLeft: body.left,
            subjectWidth: body.width, subjectHeight: body.height,
            placementTop: upper.top, placementLeft: upper.left,
            placementWidth: upper.width, placementHeight: upper.height,
            nose: landmarks.nose,
            neck: landmarks.neck,
            leftShoulder: landmarks.leftShoulder,
            rightShoulder: landmarks.rightShoulder,
            leftEye: landmarks.leftEye,
            rightEye: landmarks.rightEye,
            headCenterX: head.centerX,
            headCenterY: head.centerY,
            headRadius: head.radius,
            headBoundsSource: head.source,
            targetRoll: targetRoll,
            targetPitch: pitch.pitch,
            pitchConfidence: pitch.confidence,
            rollConfidence: rollConfidence,
            rollSource: rollSource,
            recommendedZoom: recommendedZoom,
            bodyCoverage: coverage,
            angleLook: look,
            referenceSize: CGSize(width: image.size.width, height: image.size.height)
        )
    }

    // MARK: - Private

    private struct NormBox {
        let top, left, width, height: CGFloat
        var centerX: CGFloat { left + width / 2 }
        var centerY: CGFloat { top + height / 2 }
        var cgRect: CGRect { CGRect(x: left, y: top, width: width, height: height) }
    }

    private struct PoseLandmarks {
        let nose, neck, leftShoulder, rightShoulder: CGPoint
        let leftEye, rightEye: CGPoint?
    }

    private func uiKitBox(_ visionBox: CGRect) -> NormBox {
        NormBox(
            top:    1.0 - visionBox.maxY,
            left:   visionBox.minX,
            width:  visionBox.width,
            height: visionBox.height
        )
    }

    private func uiKitPoint(_ point: VNRecognizedPoint) -> CGPoint {
        CGPoint(x: point.location.x, y: 1.0 - point.location.y)
    }

    // MARK: Face selection

    /// The subject's face: largest face overlapping the detected person box,
    /// else the largest face in frame. Landmark observations are preferred
    /// since they carry both the rect and the contours.
    private func primaryFace(
        rects: [VNFaceObservation]?,
        withLandmarks landmarkFaces: [VNFaceObservation]?,
        near subject: NormBox?
    ) -> VNFaceObservation? {
        let candidates = (landmarkFaces?.isEmpty == false ? landmarkFaces : rects) ?? []
        guard !candidates.isEmpty else { return nil }
        if let subject {
            let subjectRect = subject.cgRect
            let overlapping = candidates.filter {
                uiKitBox($0.boundingBox).cgRect.intersects(subjectRect)
            }
            if !overlapping.isEmpty {
                return overlapping.max { area($0) < area($1) }
            }
        }
        return candidates.max { area($0) < area($1) }
    }

    private func area(_ obs: VNFaceObservation) -> CGFloat {
        obs.boundingBox.width * obs.boundingBox.height
    }

    /// Face contour + median line extremes in normalized UIKit coords (US-102).
    private func landmarkExtremes(
        from face: VNFaceObservation,
        pixelSize: CGSize
    ) -> HeadBoundsEstimator.LandmarkExtremes? {
        guard let all = face.landmarks else { return nil }
        let regions = [all.faceContour, all.medianLine].compactMap { $0 }
        let points = regions.flatMap { $0.pointsInImage(imageSize: pixelSize) }
        guard points.count >= 3, pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let xs = points.map { $0.x / pixelSize.width }
        let ys = points.map { 1.0 - $0.y / pixelSize.height } // flip to UIKit
        return HeadBoundsEstimator.LandmarkExtremes(
            topY: ys.min()!,
            chinY: ys.max()!,
            minX: xs.min()!,
            maxX: xs.max()!,
            confidence: all.confidence
        )
    }

    // MARK: Body synthesis (face-only references)

    /// Rough person box derived from a face when person detection fails —
    /// keeps framing/zoom coaching alive on tight head shots.
    private func syntheticBody(from face: NormBox) -> NormBox {
        let width = min(face.width * 3.0, 1)
        let height = min(face.height * 7.0, 1 - face.top)
        return NormBox(
            top: face.top,
            left: min(max(face.centerX - width / 2, 0), 1 - width),
            width: width,
            height: height
        )
    }

    private func syntheticUpperBody(from face: NormBox) -> NormBox {
        let width = min(face.width * 2.6, 1)
        let height = min(face.height * 3.2, 1 - face.top)
        return NormBox(
            top: face.top,
            left: min(max(face.centerX - width / 2, 0), 1 - width),
            width: width,
            height: height
        )
    }

    // MARK: Pose landmarks

    /// Raw body-pose landmarks in normalized UIKit space.
    private func extractLandmarks(
        from pose: VNHumanBodyPoseObservation?,
        upperBody: NormBox
    ) -> PoseLandmarks {
        guard let pose else { return fallbackLandmarks(upperBody: upperBody) }

        guard
            let nose = point(pose, .nose),
            let neck = point(pose, .neck),
            let leftShoulder = point(pose, .leftShoulder),
            let rightShoulder = point(pose, .rightShoulder)
        else { return fallbackLandmarks(upperBody: upperBody) }

        let leftEye  = point(pose, .leftEye).map { uiKitPoint($0) }
        let rightEye = point(pose, .rightEye).map { uiKitPoint($0) }

        return PoseLandmarks(
            nose: uiKitPoint(nose),
            neck: uiKitPoint(neck),
            leftShoulder: uiKitPoint(leftShoulder),
            rightShoulder: uiKitPoint(rightShoulder),
            leftEye: leftEye,
            rightEye: rightEye
        )
    }

    private func point(
        _ pose: VNHumanBodyPoseObservation,
        _ joint: VNHumanBodyPoseObservation.JointName
    ) -> VNRecognizedPoint? {
        guard let p = try? pose.recognizedPoint(joint), p.confidence > 0.25 else { return nil }
        return p
    }

    private func fallbackLandmarks(upperBody: NormBox) -> PoseLandmarks {
        let cx = upperBody.centerX
        let neckY = upperBody.top + upperBody.height * 0.42
        let noseY = upperBody.top + upperBody.height * 0.18
        let shoulderY = upperBody.top + upperBody.height * 0.82
        let shoulderHalf = upperBody.width * 0.40
        return PoseLandmarks(
            nose: CGPoint(x: cx, y: noseY),
            neck: CGPoint(x: cx, y: neckY),
            leftShoulder: CGPoint(x: cx - shoulderHalf, y: shoulderY),
            rightShoulder: CGPoint(x: cx + shoulderHalf, y: shoulderY),
            leftEye: CGPoint(x: cx - upperBody.width * 0.08, y: noseY - upperBody.height * 0.03),
            rightEye: CGPoint(x: cx + upperBody.width * 0.08, y: noseY - upperBody.height * 0.03)
        )
    }

    // MARK: Zoom

    /// EXIF focal is the only reliable zoom signal. Face/body fill used to
    /// map a large head to 2×/3×, which tagged arm's-length selfies as zoomed
    /// in. Without focal metadata, 1× is the safe guess — same rationale as
    /// never recommending 0.5× from fill alone.
    private func inferZoom(exif: ReferenceEXIF, subjectBox: NormBox, faceBox: NormBox?) -> CGFloat {
        if exif.isFrontCamera { return 1 }
        if let focal = exif.focalLength35mm {
            switch focal {
            case ..<20:  return 0.5
            case ..<32:  return 1
            case ..<55:  return 2
            default:     return 3
            }
        }
        return 1
    }

    // MARK: Coverage / angle look

    private func bodyCoverage(from pose: VNHumanBodyPoseObservation?) -> ShotSpec.BodyCoverage {
        guard let pose else { return .unknown }
        if point(pose, .leftAnkle) != nil || point(pose, .rightAnkle) != nil { return .feet }
        if point(pose, .leftKnee) != nil || point(pose, .rightKnee) != nil { return .knees }
        if point(pose, .leftHip) != nil || point(pose, .rightHip) != nil { return .torso }
        return .unknown
    }

    private func angleLook(
        from pose: VNHumanBodyPoseObservation?,
        imageSize: CGSize
    ) -> ShotSpec.AngleLook {
        guard let pose, imageSize.width > 0, imageSize.height > 0 else { return .none }
        func span(_ a: VNHumanBodyPoseObservation.JointName, _ b: VNHumanBodyPoseObservation.JointName) -> CGFloat? {
            guard let pa = point(pose, a), let pb = point(pose, b) else { return nil }
            let ax = pa.location.x * imageSize.width
            let ay = (1 - pa.location.y) * imageSize.height
            let bx = pb.location.x * imageSize.width
            let by = (1 - pb.location.y) * imageSize.height
            return hypot(ax - bx, ay - by)
        }
        let hasAnkles = point(pose, .leftAnkle) != nil || point(pose, .rightAnkle) != nil
        return ShotSpec.inferAngleLook(
            shoulderSpan: span(.leftShoulder, .rightShoulder),
            hipSpan: span(.leftHip, .rightHip),
            kneeSpan: span(.leftKnee, .rightKnee),
            hasAnkles: hasAnkles
        )
    }
}

private nonisolated extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:            self = .up
        case .upMirrored:    self = .upMirrored
        case .down:          self = .down
        case .downMirrored:  self = .downMirrored
        case .left:          self = .left
        case .leftMirrored:  self = .leftMirrored
        case .right:         self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}
