import CoreGraphics

/// Normalized framing derived from Vision analysis of a reference photo.
/// All landmark coordinates are 0.0–1.0, UIKit top-left origin.
/// nonisolated: produced by VisionAnalyzer off MainActor; UI reads it on-main.
/// Codable: persisted in `ReferenceStore` with `analyzerVersion` invalidation.
nonisolated struct ShotSpec: Equatable, Codable {

    /// Bump when VisionAnalyzer / estimator logic changes coaching geometry,
    /// categories, or trust rules. Mismatched stored versions reanalyze once.
    static let analyzerVersion = 1

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
    /// 0–1 trust in `targetRoll` (EXIF attitude = 0.95; Vision horizon
    /// passthrough; 0 when none). Horizon alone is never coaching-trusted.
    let rollConfidence: Double
    /// Where `targetRoll` came from. Only `.exifAttitude` is high-trust —
    /// screenshots/Pinterest crops have no attitude and must not invent a
    /// dutch angle or assert "level" from a horizon guess.
    let rollSource: RollSource
    let recommendedZoom: CGFloat

    enum HeadBoundsSource: String, Equatable, Codable {
        case faceRect, faceLandmarks, pose, fallback
    }

    /// Mirrors `RollEstimator.Tier`. Stored on the spec so category + coaching
    /// can distinguish EXIF attitude from horizon-only guesses.
    enum RollSource: String, Equatable, Codable {
        case exifAttitude
        case horizonDetection
        case none
    }

    /// Below this, `targetPitch` is stored as 0 and pitch coaching disabled.
    static let minimumPitchConfidence: Double = 0.4

    var hasTrustedPitch: Bool { pitchConfidence >= Self.minimumPitchConfidence }

    /// Only Apple maker-note gravity (EXIF attitude) is trustworthy enough
    /// for Tilted grouping and hard roll coaching. Horizon / none → omit
    /// roll matching entirely (neither dutch-angle nor forced-level).
    var hasTrustedRoll: Bool { rollSource == .exifAttitude }

    /// Roll target for live coaching when `hasTrustedRoll`. Meaningless
    /// otherwise — callers must gate on `hasTrustedRoll` (same pattern as
    /// pitch) rather than treating `0` as "known level."
    var coachRollTarget: Double {
        guard hasTrustedRoll, let targetRoll else { return 0 }
        return targetRoll
    }

    /// Oriented size Vision / UIImage use for display coordinates.
    let referenceSize: CGSize

    // MARK: Codable (CGPoint / CGSize)

    private enum CodingKeys: String, CodingKey {
        case subjectTop, subjectLeft, subjectWidth, subjectHeight
        case placementTop, placementLeft, placementWidth, placementHeight
        case nose, neck, leftShoulder, rightShoulder, leftEye, rightEye
        case headCenterX, headCenterY, headRadius, headBoundsSource
        case targetRoll, targetPitch, pitchConfidence, rollConfidence
        case rollSource, recommendedZoom, referenceSize
    }

    private struct PointDTO: Codable {
        var x: Double
        var y: Double
        init(_ p: CGPoint) { x = Double(p.x); y = Double(p.y) }
        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    private struct SizeDTO: Codable {
        var width: Double
        var height: Double
        init(_ s: CGSize) { width = Double(s.width); height = Double(s.height) }
        var size: CGSize { CGSize(width: width, height: height) }
    }

    init(
        subjectTop: CGFloat, subjectLeft: CGFloat,
        subjectWidth: CGFloat, subjectHeight: CGFloat,
        placementTop: CGFloat, placementLeft: CGFloat,
        placementWidth: CGFloat, placementHeight: CGFloat,
        nose: CGPoint, neck: CGPoint,
        leftShoulder: CGPoint, rightShoulder: CGPoint,
        leftEye: CGPoint?, rightEye: CGPoint?,
        headCenterX: CGFloat, headCenterY: CGFloat, headRadius: CGFloat,
        headBoundsSource: HeadBoundsSource,
        targetRoll: Double?, targetPitch: Double?,
        pitchConfidence: Double, rollConfidence: Double,
        rollSource: RollSource, recommendedZoom: CGFloat,
        referenceSize: CGSize
    ) {
        self.subjectTop = subjectTop
        self.subjectLeft = subjectLeft
        self.subjectWidth = subjectWidth
        self.subjectHeight = subjectHeight
        self.placementTop = placementTop
        self.placementLeft = placementLeft
        self.placementWidth = placementWidth
        self.placementHeight = placementHeight
        self.nose = nose
        self.neck = neck
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.headCenterX = headCenterX
        self.headCenterY = headCenterY
        self.headRadius = headRadius
        self.headBoundsSource = headBoundsSource
        self.targetRoll = targetRoll
        self.targetPitch = targetPitch
        self.pitchConfidence = pitchConfidence
        self.rollConfidence = rollConfidence
        self.rollSource = rollSource
        self.recommendedZoom = recommendedZoom
        self.referenceSize = referenceSize
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        subjectTop = CGFloat(try c.decode(Double.self, forKey: .subjectTop))
        subjectLeft = CGFloat(try c.decode(Double.self, forKey: .subjectLeft))
        subjectWidth = CGFloat(try c.decode(Double.self, forKey: .subjectWidth))
        subjectHeight = CGFloat(try c.decode(Double.self, forKey: .subjectHeight))
        placementTop = CGFloat(try c.decode(Double.self, forKey: .placementTop))
        placementLeft = CGFloat(try c.decode(Double.self, forKey: .placementLeft))
        placementWidth = CGFloat(try c.decode(Double.self, forKey: .placementWidth))
        placementHeight = CGFloat(try c.decode(Double.self, forKey: .placementHeight))
        nose = try c.decode(PointDTO.self, forKey: .nose).point
        neck = try c.decode(PointDTO.self, forKey: .neck).point
        leftShoulder = try c.decode(PointDTO.self, forKey: .leftShoulder).point
        rightShoulder = try c.decode(PointDTO.self, forKey: .rightShoulder).point
        leftEye = try c.decodeIfPresent(PointDTO.self, forKey: .leftEye)?.point
        rightEye = try c.decodeIfPresent(PointDTO.self, forKey: .rightEye)?.point
        headCenterX = CGFloat(try c.decode(Double.self, forKey: .headCenterX))
        headCenterY = CGFloat(try c.decode(Double.self, forKey: .headCenterY))
        headRadius = CGFloat(try c.decode(Double.self, forKey: .headRadius))
        // Defaults keep older on-disk specs decodable; analyzerVersion still
        // forces a reanalyze when coaching geometry actually changes.
        headBoundsSource = try c.decodeIfPresent(HeadBoundsSource.self, forKey: .headBoundsSource) ?? .fallback
        targetRoll = try c.decodeIfPresent(Double.self, forKey: .targetRoll)
        targetPitch = try c.decodeIfPresent(Double.self, forKey: .targetPitch)
        pitchConfidence = try c.decodeIfPresent(Double.self, forKey: .pitchConfidence) ?? 0
        rollConfidence = try c.decodeIfPresent(Double.self, forKey: .rollConfidence) ?? 0
        rollSource = try c.decodeIfPresent(RollSource.self, forKey: .rollSource) ?? .none
        recommendedZoom = CGFloat(try c.decode(Double.self, forKey: .recommendedZoom))
        referenceSize = try c.decode(SizeDTO.self, forKey: .referenceSize).size
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Double(subjectTop), forKey: .subjectTop)
        try c.encode(Double(subjectLeft), forKey: .subjectLeft)
        try c.encode(Double(subjectWidth), forKey: .subjectWidth)
        try c.encode(Double(subjectHeight), forKey: .subjectHeight)
        try c.encode(Double(placementTop), forKey: .placementTop)
        try c.encode(Double(placementLeft), forKey: .placementLeft)
        try c.encode(Double(placementWidth), forKey: .placementWidth)
        try c.encode(Double(placementHeight), forKey: .placementHeight)
        try c.encode(PointDTO(nose), forKey: .nose)
        try c.encode(PointDTO(neck), forKey: .neck)
        try c.encode(PointDTO(leftShoulder), forKey: .leftShoulder)
        try c.encode(PointDTO(rightShoulder), forKey: .rightShoulder)
        try c.encodeIfPresent(leftEye.map(PointDTO.init), forKey: .leftEye)
        try c.encodeIfPresent(rightEye.map(PointDTO.init), forKey: .rightEye)
        try c.encode(Double(headCenterX), forKey: .headCenterX)
        try c.encode(Double(headCenterY), forKey: .headCenterY)
        try c.encode(Double(headRadius), forKey: .headRadius)
        try c.encode(headBoundsSource, forKey: .headBoundsSource)
        try c.encodeIfPresent(targetRoll, forKey: .targetRoll)
        try c.encodeIfPresent(targetPitch, forKey: .targetPitch)
        try c.encode(pitchConfidence, forKey: .pitchConfidence)
        try c.encode(rollConfidence, forKey: .rollConfidence)
        try c.encode(rollSource, forKey: .rollSource)
        try c.encode(Double(recommendedZoom), forKey: .recommendedZoom)
        try c.encode(SizeDTO(referenceSize), forKey: .referenceSize)
    }

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

    /// ~3.4° — below this an EXIF roll reads as level, not a dutch angle.
    private static let tiltedRollThreshold = 0.06
    /// ~8.5° of camera pitch before a shot reads as a low/high-angle look.
    private static let angledPitchThreshold = 0.15

    var styleCategory: StyleCategory {
        // Horizon-only roll must not name the group — screenshots have no
        // attitude and Vision's horizon is too easy to false-positive.
        if hasTrustedRoll, let roll = targetRoll,
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
