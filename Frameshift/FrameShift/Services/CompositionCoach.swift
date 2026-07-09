import Foundation
import CoreGraphics

/// Tracks which coaching dimensions the user has satisfied.
struct CompositionProgress: Equatable {
    var framingOK  = false
    var levelOK    = false
    var tiltOK     = false
    var zoomOK     = false
    var lightingOK = false

    var allSatisfied: Bool {
        framingOK && levelOK && tiltOK && zoomOK && lightingOK
    }
}

enum CoachTipKind: String, CaseIterable {
    case lighting, zoom, tilt, distance, horizontal, level
}

struct CompositionCoach {

    struct Input {
        let spec: ShotSpec
        /// Live subject in 0–1 viewfinder coordinates (aspect-fill), or nil if not detected.
        let liveSubject: CGRect?
        /// Reference subject in 0–1 viewfinder coordinates (aspect-fit).
        let referenceSubject: CGRect
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
    private let angleSatisfy = 0.05
    private let angleUnsatisfy = 0.08
    private let levelSatisfy = 0.025
    private let levelUnsatisfy = 0.04
    private let lightingSatisfy = 0.50
    private let lightingUnsatisfy = 0.38

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

        let targetRoll = input.spec.targetRoll ?? 0
        progress.levelOK = hysteresis(
            current: abs(input.roll - targetRoll) < levelSatisfy,
            wasOK: previous.levelOK,
            bad: abs(input.roll - targetRoll) > levelUnsatisfy
        )

        let ref = input.referenceSubject
        var rawFramingGood = false
        if let live = input.liveSubject {
            let heightDelta = abs(live.height - ref.height)
            let centerDelta = abs(live.midX - ref.midX)
            let framingGood = heightDelta < satisfyThreshold && centerDelta < satisfyThreshold
            let framingBad  = heightDelta > unsatisfyThreshold || centerDelta > unsatisfyThreshold
            rawFramingGood = framingGood
            progress.framingOK = hysteresis(current: framingGood, wasOK: previous.framingOK, bad: framingBad)
            progress.lightingOK = hysteresis(
                current: input.lightingScore >= lightingSatisfy,
                wasOK: previous.lightingOK,
                bad: input.lightingScore < lightingUnsatisfy
            )
        } else {
            progress.framingOK = false
            progress.lightingOK = true
        }

        let tip = primaryTip(input: input, progress: progress)
        return Output(progress: progress, tip: tip?.message, tipKind: tip?.kind, rawFramingGood: rawFramingGood)
    }

    // MARK: - Private

    private struct Tip { let kind: CoachTipKind; let message: String }

    private func primaryTip(input: Input, progress: CompositionProgress) -> Tip? {
        if !progress.lightingOK && input.lightingScore < lightingUnsatisfy {
            return Tip(kind: .lighting, message: "Fix lighting — face your subject toward the light")
        }
        if !progress.zoomOK {
            let label = zoomLabel(input.spec.recommendedZoom)
            return Tip(kind: .zoom, message: "Switch to \(label) to match the reference")
        }
        if let live = input.liveSubject, !progress.framingOK {
            let ref = input.referenceSubject
            let heightDelta = live.height - ref.height
            if heightDelta > unsatisfyThreshold {
                return Tip(kind: .distance, message: "Move back")
            }
            if heightDelta < -unsatisfyThreshold {
                return Tip(kind: .distance, message: "Move closer")
            }
            let centerDelta = live.midX - ref.midX
            if centerDelta > unsatisfyThreshold { return Tip(kind: .horizontal, message: "Step right") }
            if centerDelta < -unsatisfyThreshold { return Tip(kind: .horizontal, message: "Step left") }
        }
        if !progress.levelOK {
            return Tip(kind: .level, message: "Level your phone")
        }
        return nil
    }

    private func hysteresis(current: Bool, wasOK: Bool, bad: Bool) -> Bool {
        if wasOK { return !bad }
        return current
    }

    private func zoomLabel(_ z: CGFloat) -> String {
        z == 0.5 ? "0.5×" : (z == 1 ? "1×" : "\(Int(z))×")
    }
}
