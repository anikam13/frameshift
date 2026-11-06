import Vision
import CoreGraphics

/// Import-time inference of how the reference camera was rolled (tilted
/// left/right around the lens axis) — mirrors PitchEstimator's tiered
/// approach (US-103/US-104).
///
/// T1 (EXIF gravity vector) is preferred: it's present on any original
/// iPhone capture regardless of scene content. T2 (VNDetectHorizonRequest)
/// only succeeds when the photo has a visible sky/ground horizon line, which
/// most portrait references — the common case — don't have. Horizon is
/// stored for diagnostics / pitch helpers but is never high-trust enough
/// for hard roll coaching (screenshots / web crops).
/// nonisolated: import-time only, called from VisionAnalyzer off MainActor.
nonisolated enum RollEstimator {

    enum Tier: String {
        case exifAttitude      // T1 — only tier that trusts roll for UI
        case horizonDetection  // T2 — low trust; omit roll coaching
        case none               // T3 — no signal; omit roll coaching
    }

    struct Estimate {
        /// Radians; matches MotionService.roll's atan2(x, -y) convention so
        /// live roll and this target are directly comparable. Zeroed below
        /// `rollNoiseFloor`.
        let roll: Double
        let confidence: Double
        let tier: Tier
    }

    /// Roll below this is treated as level noise, not a target (FR-9).
    static let rollNoiseFloor = 0.015
    static let exifConfidence = 0.95

    static func estimate(exif: ReferenceEXIF, horizonObservation: VNHorizonObservation?) -> Estimate {
        if let roll = exifRoll(exif) {
            return zeroed(roll: roll, confidence: exifConfidence, tier: .exifAttitude)
        }
        if let horizonObservation {
            return zeroed(
                roll: Double(horizonObservation.angle),
                confidence: Double(horizonObservation.confidence),
                tier: .horizonDetection
            )
        }
        return Estimate(roll: 0, confidence: 0, tier: .none)
    }

    /// T1: same gravity-vector sanity check as PitchEstimator.exifPitch, but
    /// projected onto the screen plane (x,y) — the same quantity
    /// MotionService derives live from CoreMotion — rather than PitchEstimator's
    /// z-axis projection.
    private static func exifRoll(_ exif: ReferenceEXIF) -> Double? {
        guard let a = exif.accelerationVector else { return nil }
        let norm = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        guard norm > 0.8, norm < 1.2 else { return nil }
        return atan2(a.x, -a.y)
    }

    private static func zeroed(roll: Double, confidence: Double, tier: Tier) -> Estimate {
        guard abs(roll) > rollNoiseFloor else { return Estimate(roll: 0, confidence: confidence, tier: tier) }
        return Estimate(roll: roll, confidence: confidence, tier: tier)
    }
}
