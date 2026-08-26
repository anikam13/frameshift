import Foundation
import CoreGraphics

/// Tracks which coaching dimensions the user has satisfied.
struct CompositionProgress: Equatable {
    var framingOK  = false
    var levelOK    = false
    var tiltOK     = false
    var zoomOK     = false
    var lightingOK = false

    /// Continuous 0–1 composition quality across every axis — no hysteresis,
    /// no latching. Drives the viewfinder's live match readout; "Ready"
    /// stays with the latched booleans below so the two never fight at a
    /// threshold. 0 whenever no subject is detected.
    var matchScore: Double = 0

    /// Zoom is deliberately absent: the recommendation is a heuristic guess
    /// (EXIF-stripped web references especially), and a wrong guess must
    /// never hold "Ready" hostage. `zoomOK` still drives the ambient
    /// recommendation pill by the zoom controls.
    var allSatisfied: Bool {
        framingOK && levelOK && tiltOK && lightingOK
    }
}

enum CoachTipKind: String, CaseIterable {
    case lighting, tilt, distance, horizontal, vertical, level
}

struct CompositionCoach {

    struct Input {
        let spec: ShotSpec
        /// Live subject in 0–1 viewfinder coordinates (aspect-fill), or nil if not detected.
        let liveSubject: CGRect?
        /// Reference subject in 0–1 viewfinder coordinates (aspect-fit).
        let referenceSubject: CGRect
        /// Live head-center offset from the reference head circle, in units
        /// of the circle's radius (viewfinder space). The preferred placement
        /// signal — it's the guide the user is actually looking at. nil when
        /// live pose is unavailable; falls back to box centers.
        let headOffset: CGVector?
        /// live/reference shoulder-width ratio — the preferred distance
        /// signal (box height distorts when raised arms grow the box). nil
        /// falls back to box-height comparison.
        let shoulderRatio: CGFloat?
        let roll: Double
        let pitch: Double
        let zoom: CGFloat
        let lightingScore: Double
    }

    struct Output {
        let progress: CompositionProgress
        let tip: String?
        let tipKind: CoachTipKind?
        /// Unlatched framing-match signal — true only while the live subject
        /// is currently within the tight satisfy band, with none of
        /// `progress.framingOK`'s anti-flicker stickiness. `progress.framingOK`
        /// is intentionally sticky (shared by the tip banner and checkmark UI,
        /// which shouldn't flicker on minor jitter); a one-shot flash needs a
        /// signal that actually drops out so it can re-arm.
        let rawFramingGood: Bool
    }

    private let satisfyThreshold: CGFloat = 0.10
    private let unsatisfyThreshold: CGFloat = 0.14
    /// Box-fallback vertical placement (headroom) — slightly looser than the
    /// horizontal band: the box's vertical center is noisier (legs cropping
    /// in and out moves it more than the subject does).
    private let verticalSatisfy: CGFloat = 0.12
    private let verticalUnsatisfy: CGFloat = 0.16
    /// Head-in-circle placement, in units of the circle's radius: satisfied
    /// while the live head center sits well inside the guide circle.
    private let headOffsetSatisfy: CGFloat = 0.75
    private let headOffsetUnsatisfy: CGFloat = 1.15
    /// Shoulder-width ratio distance band (|live/ref − 1|).
    private let shoulderRatioSatisfy: CGFloat = 0.16
    private let shoulderRatioUnsatisfy: CGFloat = 0.26
    private let angleSatisfy = 0.05
    private let angleUnsatisfy = 0.08
    private let levelSatisfy = 0.025
    private let levelUnsatisfy = 0.04
    private let lightingSatisfy = 0.50
    private let lightingUnsatisfy = 0.38

    /// Beyond ~52° of pitch, "level" barely means anything visually and the
    /// gravity-projected roll signal is mostly noise — stop coaching roll.
    static let rollCoachingPitchLimit = 0.9

    /// Roll is gravity projected onto the screen plane, so its noise grows by
    /// ~1/cos(pitch) as the phone tilts away from upright. Widen roll
    /// tolerances by the same factor (capped) so a leveled-but-tilted-down
    /// phone isn't nagged to "level" over sensor noise. Shared with
    /// MotionService so the leveler UI and the tip agree.
    static func rollToleranceScale(pitch: Double) -> Double {
        min(3, 1 / max(0.33, cos(pitch)))
    }

    func evaluate(_ input: Input, previous: CompositionProgress) -> Output {
        var progress = previous

        progress.zoomOK = hysteresis(
            current: abs(input.zoom - input.spec.recommendedZoom) < 0.15,
            wasOK: previous.zoomOK,
            bad: abs(input.zoom - input.spec.recommendedZoom) > 0.35
        )

        if input.spec.hasTrustedPitch {
            let targetPitch = input.spec.targetPitch ?? 0
            progress.tiltOK = hysteresis(
                current: abs(input.pitch - targetPitch) < angleSatisfy,
                wasOK: previous.tiltOK,
                bad: abs(input.pitch - targetPitch) > angleUnsatisfy
            )
        } else {
            // FR-8: pitch guide is hidden for this reference — don't coach
            // against a target we don't trust.
            progress.tiltOK = true
        }

        if input.spec.hasTrustedRoll, abs(input.pitch) <= Self.rollCoachingPitchLimit {
            let scale = Self.rollToleranceScale(pitch: input.pitch)
            let targetRoll = input.spec.coachRollTarget
            progress.levelOK = hysteresis(
                current: abs(input.roll - targetRoll) < levelSatisfy * scale,
                wasOK: previous.levelOK,
                bad: abs(input.roll - targetRoll) > levelUnsatisfy * scale
            )
        } else {
            // No EXIF attitude (screenshots / horizon-only / none): omit roll
            // matching — neither invent a dutch angle nor assert "level."
            progress.levelOK = true
        }

        let ref = input.referenceSubject
        var rawFramingGood = false
        if input.liveSubject != nil || input.headOffset != nil {
            // Placement: head-in-circle when live pose is available — the
            // circle is the guide the user is matching. Box centers (with
            // the vertical axis finally counted) otherwise.
            let positionGood: Bool
            let positionBad: Bool
            if let offset = input.headOffset {
                let distance = hypot(offset.dx, offset.dy)
                positionGood = distance < headOffsetSatisfy
                positionBad  = distance > headOffsetUnsatisfy
            } else if let live = input.liveSubject {
                let dx = abs(live.midX - ref.midX)
                let dy = abs(live.midY - ref.midY)
                positionGood = dx < satisfyThreshold && dy < verticalSatisfy
                positionBad  = dx > unsatisfyThreshold || dy > verticalUnsatisfy
            } else {
                positionGood = false
                positionBad = true
            }

            // Distance: shoulder-width ratio when pose gave both shoulders;
            // box height otherwise.
            let sizeGood: Bool
            let sizeBad: Bool
            if let ratio = input.shoulderRatio {
                sizeGood = abs(ratio - 1) < shoulderRatioSatisfy
                sizeBad  = abs(ratio - 1) > shoulderRatioUnsatisfy
            } else if let live = input.liveSubject {
                let heightDelta = abs(live.height - ref.height)
                sizeGood = heightDelta < satisfyThreshold
                sizeBad  = heightDelta > unsatisfyThreshold
            } else {
                sizeGood = false
                sizeBad = true
            }

            rawFramingGood = positionGood && sizeGood
            progress.framingOK = hysteresis(
                current: rawFramingGood,
                wasOK: previous.framingOK,
                bad: positionBad || sizeBad
            )
            // Lighting was only measured when the detector found a box.
            if input.liveSubject != nil {
                progress.lightingOK = hysteresis(
                    current: input.lightingScore >= lightingSatisfy,
                    wasOK: previous.lightingOK,
                    bad: input.lightingScore < lightingUnsatisfy
                )
            } else {
                progress.lightingOK = true
            }
        } else {
            progress.framingOK = false
            progress.lightingOK = true
        }

        progress.matchScore = matchScore(input: input, progress: progress)

        let tip = primaryTip(input: input, progress: progress)
        return Output(progress: progress, tip: tip?.message, tipKind: tip?.kind, rawFramingGood: rawFramingGood)
    }

    // MARK: - Private

    private struct Tip { let kind: CoachTipKind; let message: String }

    private func primaryTip(input: Input, progress: CompositionProgress) -> Tip? {
        if !progress.lightingOK && input.lightingScore < lightingUnsatisfy {
            return Tip(kind: .lighting, message: "Fix lighting — face your subject toward the light")
        }
        // No zoom tip: the recommendation is a guess, and as a banner tip it
        // shadowed every framing/tilt/level tip whenever the user (often
        // rightly) ignored it. The pill by the zoom controls carries it.
        if !progress.framingOK {
            let ref = input.referenceSubject

            // Distance first — shoulder ratio when pose has it, box height
            // otherwise. Fixing distance often fixes placement for free.
            if let ratio = input.shoulderRatio {
                if ratio - 1 > shoulderRatioUnsatisfy {
                    return Tip(kind: .distance, message: "Move back")
                }
                if 1 - ratio > shoulderRatioUnsatisfy {
                    return Tip(kind: .distance, message: "Move closer")
                }
            } else if let live = input.liveSubject {
                let heightDelta = live.height - ref.height
                if heightDelta > unsatisfyThreshold {
                    return Tip(kind: .distance, message: "Move back")
                }
                if heightDelta < -unsatisfyThreshold {
                    return Tip(kind: .distance, message: "Move closer")
                }
            }

            // Placement: dominant axis of the head offset when pose has it.
            // Vertical placement is a camera-height move, not a tilt — a
            // tilt tip here would fight the pitch coaching.
            if let offset = input.headOffset {
                if abs(offset.dx) >= abs(offset.dy) {
                    if offset.dx > headOffsetSatisfy { return Tip(kind: .horizontal, message: "Move the camera right") }
                    if offset.dx < -headOffsetSatisfy { return Tip(kind: .horizontal, message: "Move the camera left") }
                }
                if offset.dy > headOffsetSatisfy { return Tip(kind: .vertical, message: "Lower the camera") }
                if offset.dy < -headOffsetSatisfy { return Tip(kind: .vertical, message: "Raise the camera") }
            } else if let live = input.liveSubject {
                let centerDelta = live.midX - ref.midX
                if centerDelta > unsatisfyThreshold { return Tip(kind: .horizontal, message: "Move the camera right") }
                if centerDelta < -unsatisfyThreshold { return Tip(kind: .horizontal, message: "Move the camera left") }
                let verticalDelta = live.midY - ref.midY
                if verticalDelta > verticalUnsatisfy { return Tip(kind: .vertical, message: "Lower the camera") }
                if verticalDelta < -verticalUnsatisfy { return Tip(kind: .vertical, message: "Raise the camera") }
            }
        }
        // Angle tips only make sense while composing an actual subject —
        // with nobody detected they'd be the nonsense fallback instruction.
        if input.liveSubject != nil || input.headOffset != nil {
            if input.spec.hasTrustedPitch, !progress.tiltOK {
                let target = input.spec.targetPitch ?? 0
                return Tip(
                    kind: .tilt,
                    message: input.pitch > target ? "Tilt down a bit" : "Tilt up a bit"
                )
            }
            if input.spec.hasTrustedRoll, !progress.levelOK {
                return Tip(kind: .level, message: "Level your phone")
            }
        }
        return nil
    }

    private func hysteresis(current: Bool, wasOK: Bool, bad: Bool) -> Bool {
        if wasOK { return !bad }
        return current
    }

    // MARK: Match score

    /// Weighted blend of every axis's error into one 0–1 quality. Placement
    /// and distance dominate (they're what "matching the reference" mostly
    /// means); phone attitude and zoom refine; lighting nudges. Rounded to
    /// 2 decimals so downstream equality checks can actually dedupe.
    private func matchScore(input: Input, progress: CompositionProgress) -> Double {
        guard input.liveSubject != nil || input.headOffset != nil else { return 0 }
        let ref = input.referenceSubject

        let position: Double
        if let offset = input.headOffset {
            position = quality(hypot(offset.dx, offset.dy), fullyOffAt: 1.8)
        } else if let live = input.liveSubject {
            position = quality(hypot(live.midX - ref.midX, live.midY - ref.midY), fullyOffAt: 0.35)
        } else {
            position = 0
        }

        let size: Double
        if let ratio = input.shoulderRatio {
            size = quality(abs(ratio - 1), fullyOffAt: 0.45)
        } else if let live = input.liveSubject {
            size = quality(abs(live.height - ref.height), fullyOffAt: 0.32)
        } else {
            size = 0
        }

        let level: Double
        if input.spec.hasTrustedRoll, abs(input.pitch) <= Self.rollCoachingPitchLimit {
            let scale = Self.rollToleranceScale(pitch: input.pitch)
            level = quality(abs(input.roll - input.spec.coachRollTarget), fullyOffAt: 0.12 * scale)
        } else {
            level = 1
        }

        let tilt: Double
        if input.spec.hasTrustedPitch {
            tilt = quality(abs(input.pitch - (input.spec.targetPitch ?? 0)), fullyOffAt: 0.18)
        } else {
            tilt = 1
        }

        let zoom = quality(Double(abs(input.zoom - input.spec.recommendedZoom)), fullyOffAt: 0.7)
        // lightingScore buckets land at 0.25 / 0.45 / 0.75 — map to 0 / 0.4 / 1.
        // Unmeasured (no detector box) counts as fine, matching lightingOK.
        let lighting = input.liveSubject != nil
            ? min(max((input.lightingScore - 0.25) / 0.5, 0), 1)
            : 1

        let blended = 0.30 * position
                    + 0.25 * size
                    + 0.15 * level
                    + 0.10 * tilt
                    + 0.15 * zoom
                    + 0.05 * lighting
        return (blended * 100).rounded() / 100
    }

    /// Linear falloff: 1 at zero error, 0 at `fullyOffAt` and beyond.
    private func quality(_ error: Double, fullyOffAt: Double) -> Double {
        max(0, 1 - error / fullyOffAt)
    }

    private func quality(_ error: CGFloat, fullyOffAt: Double) -> Double {
        quality(Double(error), fullyOffAt: fullyOffAt)
    }
}
