import CoreGraphics

/// Normalized framing derived from Vision analysis of a reference photo.
/// All landmark coordinates are 0.0–1.0, UIKit top-left origin.
struct ShotSpec: Equatable {
    // Full-body detection (distance / framing coaching)
    let subjectTop: CGFloat
    let subjectLeft: CGFloat
    let subjectWidth: CGFloat
    let subjectHeight: CGFloat

    // Upper-body bounding box
    let placementTop: CGFloat
    let placementLeft: CGFloat
    let placementWidth: CGFloat
    let placementHeight: CGFloat

    // Body-pose landmarks from the reference (normalized).
    let nose: CGPoint
    let neck: CGPoint
    let leftShoulder: CGPoint
    let rightShoulder: CGPoint
    let leftEye: CGPoint?
    let rightEye: CGPoint?

    // Authoritative head guide, computed once at import by HeadBoundsEstimator.
    // Center is normalized to image width/height; radius is normalized to
    // min(referenceSize.width, referenceSize.height) so it maps through
    // ImageContentMapper.scalar under uniform aspect-fit scaling.
    // Specs live in memory only and are recomputed on every import, so there
    // is no legacy-spec migration path — a schema change here is enough.
    let headCenterX: CGFloat
    let headCenterY: CGFloat
    let headRadius: CGFloat
    let headBoundsSource: HeadBoundsSource

    let targetRoll: Double?
    let targetPitch: Double?
    /// 0–1 trust in `targetPitch` per PitchEstimator tier. Below
    /// `ShotSpec.minimumPitchConfidence` the pitch guide is hidden and
    /// tilt coaching is relaxed (FR-8).
    let pitchConfidence: Double
    /// 0–1 trust in `targetRoll` (Vision horizon confidence, 0 when zeroed).
    let rollConfidence: Double
    let recommendedZoom: CGFloat

    enum HeadBoundsSource: String, Equatable {
        case faceRect, faceLandmarks, pose, fallback
    }

    /// Below this, `targetPitch` is stored as 0 and pitch coaching disabled.
    static let minimumPitchConfidence: Double = 0.4

    var hasTrustedPitch: Bool { pitchConfidence >= Self.minimumPitchConfidence }

    /// Oriented size Vision / UIImage use for display coordinates.
    let referenceSize: CGSize

    func boxRect(in size: CGSize) -> CGRect {
        CGRect(
            x: subjectLeft * size.width,
            y: subjectTop * size.height,
            width: subjectWidth * size.width,
            height: subjectHeight * size.height
        )
    }

    /// Subject bounds in 0–1 viewfinder coordinates (aspect-fit, matches placement guide).
    func subjectRect(inViewfinder containerSize: CGSize) -> CGRect {
        let normalized = CGRect(
            x: subjectLeft,
            y: subjectTop,
            width: subjectWidth,
            height: subjectHeight
        )
        return ImageContentMapper.viewfinderNormalized(
            normalized,
            contentSize: referenceSize,
            in: containerSize,
            mode: .fit
        )
    }

    /// Maps a normalized landmark into viewfinder coordinates (aspect-fit, full photo visible).
    func map(_ point: CGPoint, in containerSize: CGSize) -> CGPoint {
        ImageContentMapper.point(point, contentSize: referenceSize, in: containerSize, mode: .fit)
    }

    /// Head circle in container points. Mapper-only: geometry was decided at
    /// import by HeadBoundsEstimator, stored normalized (FR-4).
    func headCircle(in containerSize: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let center = map(CGPoint(x: headCenterX, y: headCenterY), in: containerSize)
        let radius = ImageContentMapper.scalar(
            headRadius,
            contentSize: referenceSize,
            in: containerSize,
            mode: .fit
        )
        return (center, max(radius, 12))
    }

    /// Shoulder arc endpoints from detected shoulder landmarks.
    func shoulderEndpoints(in containerSize: CGSize) -> (left: CGPoint, right: CGPoint) {
        (
            map(leftShoulder, in: containerSize),
            map(rightShoulder, in: containerSize)
        )
    }
}

// MARK: - Style classification

extension ShotSpec {
    enum Framing: String, CaseIterable {
        case wide    = "Full body"
        case medium  = "Medium shot"
        case closeUp = "Close-up"
    }

    /// References-tab grouping. Priority-ordered: each photo lands in the
    /// first category that matches, so the most distinctive thing about a
    /// shot (a deliberate tilt, an extreme angle, a lens choice) names its
    /// group rather than everything collapsing into the three framing sizes.
    enum StyleCategory: String, CaseIterable {
        case tilted     = "Tilted"
        case lowAngle   = "Low angle"
        case highAngle  = "High angle"
        case facingAway = "Facing away"
        case ultraWide  = "Ultra-wide"
        case telephoto  = "Zoomed in"
        case closeUp    = "Close-up"
        case medium     = "Medium shot"
        case fullBody   = "Full body"
    }

    /// ~3.4° — below this a horizon reads as level, not a dutch angle.
    private static let tiltedRollThreshold = 0.06
    /// ~8.5° of camera pitch before a shot reads as a low/high-angle look.
    private static let angledPitchThreshold = 0.15

    var styleCategory: StyleCategory {
        if let roll = targetRoll, rollConfidence >= 0.5,
           abs(roll) >= Self.tiltedRollThreshold {
            return .tilted
        }
        if hasTrustedPitch, let pitch = targetPitch {
            if pitch >= Self.angledPitchThreshold { return .lowAngle }
            if pitch <= -Self.angledPitchThreshold { return .highAngle }
        }
        // No detected face and no eye landmarks → subject has their back to
        // the camera (the classic lead-me travel shot). Face-derived head
        // bounds mean a face was found, so those can't be facing away.
        if leftEye == nil && rightEye == nil,
           headBoundsSource == .pose || headBoundsSource == .fallback {
            return .facingAway
        }
        if recommendedZoom <= 0.5 { return .ultraWide }
        if recommendedZoom >= 3 { return .telephoto }
        switch framing {
        case .wide:    return .fullBody
        case .medium:  return .medium
        case .closeUp: return .closeUp
        }
    }

    enum Placement: String {
        case left   = "Left"
        case center = "Centered"
        case right  = "Right"
    }

    var framing: Framing {
        switch subjectHeight {
        case ..<0.45: return .wide
        case ..<0.75: return .medium
        default:      return .closeUp
        }
    }

    var placement: Placement {
        let centerX = subjectLeft + subjectWidth / 2
        switch centerX {
        case ..<0.40:  return .left
        case 0.60...:  return .right
        default:       return .center
        }
    }
}
