import SwiftUI

/// Pitch guide — target line + live line; merge to yellow when aligned.
struct TiltPitchGuide: View {
    let roll: Double
    let pitch: Double
    let targetRoll: Double
    let targetPitch: Double
    let isLevel: Bool
    /// False when the reference's pitch confidence is below the FR-8 floor —
    /// pitch lines and chevrons hide.
    var showPitch: Bool = true
    /// False when roll isn't EXIF-trusted (horizon-only / none) — leveler
    /// hides so we neither invent a dutch target nor assert known-level.
    var showRoll: Bool = true

    @State private var showYellowMerge = false

    private let lineLength: CGFloat = 56
    private let thickness: CGFloat = 2
    private let pixelsPerRadian: CGFloat = 120
    private let maxOffset: CGFloat = 34

    /// Hysteresis only for the yellow lock — does not affect line tracking.
    private let mergeEnter: Double = 0.028
    private let mergeExit: Double = 0.045
    private let showChevronThreshold: Double = 0.025

    private var pitchError: Double { pitch - targetPitch }
    private var pitchMagnitude: Double { abs(pitchError) }

    private var displayOffsetY: CGFloat {
        let raw = -CGFloat(pitchError) * pixelsPerRadian
        return min(max(raw, -maxOffset), maxOffset)
    }

    private var needsTiltUp: Bool { showPitch && !showYellowMerge && pitchError < -showChevronThreshold }
    private var needsTiltDown: Bool { showPitch && !showYellowMerge && pitchError > showChevronThreshold }

    var body: some View {
        VStack(spacing: 5) {
            chevronSlot(pointingDown: true, visible: needsTiltDown)

            ZStack {
                if showPitch {
                    pitchLines
                }
                if showRoll {
                    LevelIndicator(
                        roll: roll,
                        targetRoll: targetRoll,
                        isLevel: isLevel
                    )
                }
            }
            .frame(width: lineLength * 1.2, height: 44)

            chevronSlot(pointingDown: false, visible: needsTiltUp)
        }
        .onChange(of: pitch) { _, _ in updateMergeState() }
        .onChange(of: targetPitch) { _, _ in updateMergeState(targetChanged: true) }
        .onAppear { updateMergeState() }
        // Pure indicator — let viewfinder taps/pinches pass through.
        .allowsHitTesting(false)
    }

    private var pitchLines: some View {
        ZStack {
            Capsule()
                .fill(showYellowMerge ? Color.levelLocked : Color.levelNeutral)
                .frame(
                    width: showYellowMerge ? lineLength * 1.7 : lineLength,
                    height: thickness
                )

            Capsule()
                .fill(Color.levelNeutral.opacity(0.75))
                .frame(width: lineLength, height: thickness)
                .offset(y: displayOffsetY)
                .opacity(showYellowMerge ? 0 : 1)
                .transaction { $0.animation = nil }
        }
        .animation(.easeOut(duration: 0.12), value: showYellowMerge)
    }

    /// Writes `showYellowMerge` only on an actual transition — CoreMotion
    /// delivers updates faster than the display refresh, and unconditional
    /// state writes from onChange trip SwiftUI's "tried to update multiple
    /// times per frame" warning. A new target must re-earn the lock at the
    /// enter threshold instead of keeping it through hysteresis.
    private func updateMergeState(targetChanged: Bool = false) {
        let merged: Bool
        if showYellowMerge && !targetChanged {
            merged = pitchMagnitude <= mergeExit
        } else {
            merged = pitchMagnitude < mergeEnter
        }
        if merged != showYellowMerge { showYellowMerge = merged }
    }

    /// Slot height for the maximum chevron tier (3 × 12pt rows + 2pt).
    private var chevronSlotHeight: CGFloat { 38 }

    /// Chevrons render inside an always-present fixed-height slot. Inserting
    /// and removing them from the VStack changed its height, which shifted
    /// the leveler itself — right at lock, pitch noise straddling the
    /// thresholds made the whole guide visibly jump up and down.
    private func chevronSlot(pointingDown: Bool, visible: Bool) -> some View {
        chevronStack(pointingDown: pointingDown)
            .frame(height: chevronSlotHeight, alignment: pointingDown ? .bottom : .top)
            .opacity(visible ? 1 : 0)
    }

    private func chevronStack(pointingDown: Bool) -> some View {
        let tier = chevronTier
        return VStack(spacing: 1) {
            ForEach(0..<tier, id: \.self) { index in
                Image(systemName: pointingDown ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.levelNeutral.opacity(chevronOpacity(tier: tier, index: index)))
            }
        }
    }

    private var chevronTier: Int {
        let magnitude = pitchMagnitude
        if magnitude < showChevronThreshold { return 0 }
        if magnitude < 0.06 { return 1 }
        if magnitude < 0.09 { return 2 }
        return 3
    }

    private func chevronOpacity(tier: Int, index: Int) -> Double {
        let base = 0.45 + Double(tier) * 0.12
        let falloff = Double(tier - index - 1) * 0.08
        return min(base + falloff, 0.95)
    }
}
