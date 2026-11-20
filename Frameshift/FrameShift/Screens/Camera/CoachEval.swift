#if DEBUG
import SwiftUI
import Combine

/// On-device coaching eval (debug builds only; `⋯` → Coaching Eval).
/// Shows the live signals the coach decides on and counts the events the
/// eval protocol scores (`docs/coaching-eval.md`): tip changes and flicker,
/// alignments, level haptics, detection drops, time to first alignment.
@MainActor
final class CoachEval: ObservableObject {

    struct Snapshot {
        var subjectDetected = false
        /// Head center offset from the target circle, in circle radii.
        var headOffset: CGFloat?
        /// live / reference shoulder width.
        var shoulderRatio: CGFloat?
        /// Degrees off the reference; nil when that axis isn't coached.
        var rollErrorDegrees: Double?
        var pitchErrorDegrees: Double?
        var lighting: Double = 0
        var progress = CompositionProgress()
        var tip: String?
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var startedAt = Date()
    @Published private(set) var tipChanges = 0
    /// Tip changes less than 1s after the previous change — the flicker count.
    @Published private(set) var rapidTipChanges = 0
    @Published private(set) var alignments = 0
    @Published private(set) var levelHaptics = 0
    @Published private(set) var detectionDrops = 0
    @Published private(set) var firstAlignmentAfter: TimeInterval?

    private var lastTip: String??
    private var lastTipChangeAt: Date?
    private var wasDetected = false
    private var lastPublish = Date.distantPast

    func record(_ next: Snapshot) {
        let now = Date()
        if lastTip != .some(next.tip) {
            if lastTip != nil {
                tipChanges += 1
                if let last = lastTipChangeAt, now.timeIntervalSince(last) < 1 { rapidTipChanges += 1 }
            }
            lastTip = .some(next.tip)
            lastTipChangeAt = now
        }
        if wasDetected && !next.subjectDetected { detectionDrops += 1 }
        wasDetected = next.subjectDetected

        // Coaching runs at motion rate; ~10 HUD refreshes a second is plenty.
        guard now.timeIntervalSince(lastPublish) > 0.1 else { return }
        lastPublish = now
        snapshot = next
    }

    func noteAlignment() {
        alignments += 1
        if firstAlignmentAfter == nil { firstAlignmentAfter = Date().timeIntervalSince(startedAt) }
    }

    func noteLevelHaptic() { levelHaptics += 1 }

    func reset() {
        startedAt = Date()
        tipChanges = 0
        rapidTipChanges = 0
        alignments = 0
        levelHaptics = 0
        detectionDrops = 0
        firstAlignmentAfter = nil
        lastTip = nil
        lastTipChangeAt = nil
    }

    var elapsed: TimeInterval { Date().timeIntervalSince(startedAt) }

    /// One line per run, pasted into the results table.
    func report(scenario: String) -> String {
        let first = firstAlignmentAfter.map { String(format: "%.1fs", $0) } ?? "never"
        return String(
            format: "%@ | %.0fs | first align %@ | aligns %d | tip changes %d (rapid %d) | level haptics %d | drops %d",
            scenario, elapsed, first, alignments, tipChanges, rapidTipChanges, levelHaptics, detectionDrops
        )
    }
}

/// Compact readout over the viewfinder. ✓ = that axis is inside its band.
struct CoachEvalHUD: View {
    @ObservedObject var eval: CoachEval
    let onClose: () -> Void

    var body: some View {
        let s = eval.snapshot
        let p = s.progress
        VStack(alignment: .leading, spacing: 3) {
            row("subject", s.subjectDetected ? "yes" : "no", ok: s.subjectDetected)
            row("head off", s.headOffset.map { String(format: "%.2f r", $0) } ?? "—", ok: p.framingOK)
            row("shoulder", s.shoulderRatio.map { String(format: "×%.2f", $0) } ?? "—", ok: p.framingOK)
            row("roll err", s.rollErrorDegrees.map { String(format: "%+.1f°", $0) } ?? "off", ok: p.levelOK)
            row("pitch err", s.pitchErrorDegrees.map { String(format: "%+.1f°", $0) } ?? "off", ok: p.tiltOK)
            row("light", String(format: "%.2f", s.lighting), ok: p.lightingOK)
            Divider().overlay(Color.white.opacity(0.3))
            Text("tip: \(s.tip ?? "—")").lineLimit(1)
            Text("aligns \(eval.alignments) · tips \(eval.tipChanges) (rapid \(eval.rapidTipChanges))")
            Text("level \(eval.levelHaptics) · drops \(eval.detectionDrops) · 1st \(eval.firstAlignmentAfter.map { String(format: "%.1fs", $0) } ?? "—")")
            HStack(spacing: 14) {
                Button("Reset") { eval.reset() }
                Button("Copy") {
                    UIPasteboard.general.string = eval.report(scenario: "S?")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                Spacer()
                Button { onClose() } label: { Image(systemName: "xmark") }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.top, 4)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: 230, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.7)))
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
            Image(systemName: ok ? "checkmark" : "xmark")
                .foregroundStyle(ok ? Color.cameraYellow : Color.white.opacity(0.5))
                .frame(width: 12)
        }
    }
}
#endif
