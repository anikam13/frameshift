import SwiftUI

/// iOS-style horizon leveler — fixed bar + rotating bar; yellow when level.
struct LevelIndicator: View {
    let roll: Double
    let targetRoll: Double
    let isLevel: Bool

    private let length: CGFloat = 56
    private let thickness: CGFloat = 2
    /// Deviation (radians) at which the live line starts fading into yellow.
    private let fadeStart: Double = 0.08
    /// Deviation at which it reads as fully locked — matches MotionService's
    /// level threshold so the visual lock lines up with the haptic.
    private let fadeEnd: Double = 0.02

    private var deviation: Double { roll - targetRoll }

    /// 0 = fully white/live, 1 = fully yellow/locked. Ramps continuously with
    /// deviation instead of switching on `isLevel` so residual roll jitter
    /// near lock reads as a smooth fade rather than the white line snapping
    /// in and out as it straddles the threshold. Drives opacity only — it
    /// changes every frame, so anything layout-affecting (the bar width)
    /// keys off the latched `isLevel` instead.
    private var lockProgress: Double {
        if isLevel { return 1 }
        let magnitude = abs(deviation)
        guard magnitude < fadeStart else { return 0 }
        return min(max((fadeStart - magnitude) / (fadeStart - fadeEnd), 0), 1)
    }

    var body: some View {
        ZStack {
            // Target line — widens and turns yellow as the live line locks in.
            Capsule()
                .fill(Color.levelNeutral)
                .frame(width: length, height: thickness)
                .opacity(1 - lockProgress)

            // Width pops once on the latched lock (isLevel has hysteresis in
            // MotionService); tying it to lockProgress made every frame's
            // roll noise restart the ease-out mid-flight, so the bar's width
            // visibly quivered right as the user closed in on the target.
            Capsule()
                .fill(Color.levelLocked)
                .frame(width: isLevel ? length * 1.7 : length, height: thickness)
                .opacity(lockProgress)

            // Live line — rotates with roll, fades out as it nears the
            // target so sensor jitter near lock disappears instead of shaking.
            // No implicit animation on rotation: roll updates ~60x/sec, and
            // animating a value that changes every frame just makes SwiftUI
            // restart an ease-out curve before the last one settles, which
            // reads as jitter regardless of how clean the input signal is
            // (same reasoning as the live offset in TiltPitchGuide.pitchLines).
            Capsule()
                .fill(Color.levelNeutral)
                .frame(width: length, height: thickness)
                .rotationEffect(.radians(-deviation))
                .opacity(1 - lockProgress)
                .transaction { $0.animation = nil }
        }
        // Animate only the discrete lock/unlock transition. lockProgress is
        // already smooth by construction (MotionService smooths roll), and an
        // implicit animation keyed on it restarts 60×/sec near lock — the
        // jitter this file's live-line comment describes, just via width.
        .animation(.easeOut(duration: 0.15), value: isLevel)
    }
}
