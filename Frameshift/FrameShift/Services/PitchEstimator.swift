import Vision
import CoreGraphics

/// Import-time inference of how the reference camera was pitched (US-103).
///
/// Sign convention matches `MotionService.pitch`: positive = camera tilted up
/// (top of the phone leaning toward the user in portrait), radians.
///
/// Tiers are evaluated T1 → T2 → T4 → T3. The PRD table lists T4 after T3,
/// but T3 always succeeds, so the ultrawide prior must be checked first or
/// it would never fire.
enum PitchEstimator {

    // MARK: - Tunable constants

    static let shoulderMinConfidence: Float = 0.5 // FR-5 gate
    static let shoulderWeight = 0.6               // FR-6 w1
    static let verticalWeight = 0.4               // FR-6 w2 (w1 + w2 = 1)

    /// Scales shoulder-line angle into a pitch contribution. The sign needs
    /// one on-device calibration pass (OQ-5): a camera above the subject
    /// foreshortens the near shoulder downward in the upright image. Flip
    /// negative if device QA shows inverted chevrons on R2/R3 references.
    static let shoulderPitchGain = 0.5

    static let maxPitch = 0.35                    // clamp, radians

    // T3 mapping (FR-4 table): top third → +0.12, bottom third → -0.10.
    static let topThirdPitch = 0.12
    static let bottomThirdPitch = -0.10

    static let ultrawideFocalThreshold: CGFloat = 20 // T4
    static let ultrawidePitchPrior = -0.08

    // FR-7 confidences per tier.
    static let exifConfidence = 0.95
    static let shoulderConfidence = 0.75
    static let verticalConfidence = 0.35
    static let ultrawideConfidence = 0.5

    // MARK: - Types

    enum Tier: String {
        case exifAttitude      // T1
        case shoulderGeometry  // T2
        case verticalPosition  // T3
        case ultrawidePrior    // T4
    }

    struct Estimate {
        /// Radians; already zeroed when confidence is below the FR-8 floor.
        let pitch: Double
        let confidence: Double
        let tier: Tier
    }

    // MARK: - Entry point

    static func estimate(
        exif: ReferenceEXIF,
        pose: VNHumanBodyPoseObservation?,
        horizonAngle: Double?,
        subjectCenterY: CGFloat,
        imageSize: CGSize
    ) -> Estimate {
        let raw = rawEstimate(
            exif: exif,
            pose: pose,
            horizonAngle: horizonAngle,
            subjectCenterY: subjectCenterY,
            imageSize: imageSize
        )
        // FR-8: below the floor, coach against 0 rather than chase noise.
        guard raw.confidence >= ShotSpec.minimumPitchConfidence else {
            return Estimate(pitch: 0, confidence: raw.confidence, tier: raw.tier)
        }
        return raw
    }

    // MARK: - Tiers

    private static func rawEstimate(
        exif: ReferenceEXIF,
        pose: VNHumanBodyPoseObservation?,
        horizonAngle: Double?,
        subjectCenterY: CGFloat,
        imageSize: CGSize
    ) -> Estimate {
        // T1: maker-note gravity vector — direct capture attitude.
        if let pitch = exifPitch(exif) {
            return Estimate(pitch: clamp(pitch), confidence: exifConfidence, tier: .exifAttitude)
        }

        // T2: shoulder-line slope blended with vertical offset (FR-5/FR-6).
        if let shoulderPitch = shoulderPitch(pose: pose, horizonAngle: horizonAngle, imageSize: imageSize) {
            let combined = shoulderWeight * shoulderPitch
                + verticalWeight * verticalPitch(subjectCenterY)
            return Estimate(pitch: clamp(combined), confidence: shoulderConfidence, tier: .shoulderGeometry)
        }

        // T4: ultrawide lens implies a low, tilted-down vantage prior.
        if let focal = exif.focalLength35mm, focal < ultrawideFocalThreshold {
            return Estimate(pitch: ultrawidePitchPrior, confidence: ultrawideConfidence, tier: .ultrawidePrior)
        }

        // T3: subject vertical position — always available, low trust.
        return Estimate(
            pitch: clamp(verticalPitch(subjectCenterY)),
            confidence: verticalConfidence,
            tier: .verticalPosition
        )
    }

    /// T1: the camera optical axis is the device -Z axis, so the pitch above
    /// horizontal is asin of the gravity vector's z component — independent
    /// of capture orientation (portrait vs landscape).
    private static func exifPitch(_ exif: ReferenceEXIF) -> Double? {
        guard let a = exif.accelerationVector else { return nil }
        let norm = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        // A static capture reads ~1g; anything far off means motion or junk data.
        guard norm > 0.8, norm < 1.2 else { return nil }
        return asin(min(max(a.z / norm, -1), 1))
    }

    /// T2 shoulder component: angle of the leftShoulder → rightShoulder line
    /// vs horizontal in the upright image, in pixel space (normalized coords
    /// would distort the angle on non-square images). Scene roll from the
    /// horizon is subtracted so roll is not mixed into pitch (US-104).
    private static func shoulderPitch(
        pose: VNHumanBodyPoseObservation?,
        horizonAngle: Double?,
        imageSize: CGSize
    ) -> Double? {
        guard
            let pose,
            let ls = try? pose.recognizedPoint(.leftShoulder), ls.confidence > shoulderMinConfidence,
            let rs = try? pose.recognizedPoint(.rightShoulder), rs.confidence > shoulderMinConfidence,
            imageSize.width > 0, imageSize.height > 0
        else { return nil }

        // Vision bottom-left → UIKit top-left, then to pixels.
        let dx = Double((rs.location.x - ls.location.x) * imageSize.width)
        let dy = Double((ls.location.y - rs.location.y) * imageSize.height)
        guard abs(dx) > imageSize.width * 0.02 else { return nil } // shoulders stacked: profile pose

        var angle = atan2(dy, dx)
        if let horizonAngle { angle -= horizonAngle }
        // The shoulder segment is undirected, but Vision's left/right are the
        // subject's anatomy: facing the camera puts the left shoulder on the
        // image's right, so dx < 0 and atan2 lands near ±π instead of the
        // line's slope. Unfolded, the gain saturates that into a full
        // ±maxPitch target whose sign is pixel noise in dy — the "chevrons
        // demand a big tilt in a random direction" bug. Fold to the tilt
        // from horizontal in (-π/2, π/2].
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        return angle * shoulderPitchGain
    }

    /// T3: linear map of subject center Y. Top third → +0.12, bottom third
    /// → -0.10, interpolated in between.
    private static func verticalPitch(_ centerY: CGFloat) -> Double {
        let y = Double(min(max(centerY, 0), 1))
        let lower = 1.0 / 3.0
        let upper = 2.0 / 3.0
        if y <= lower { return topThirdPitch }
        if y >= upper { return bottomThirdPitch }
        let t = (y - lower) / (upper - lower)
        return topThirdPitch + t * (bottomThirdPitch - topThirdPitch)
    }

    private static func clamp(_ pitch: Double) -> Double {
        min(max(pitch, -maxPitch), maxPitch)
    }
}
