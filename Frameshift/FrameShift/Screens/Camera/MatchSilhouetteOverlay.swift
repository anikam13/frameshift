import SwiftUI

/// Brief light-green outline of the live subject, flashed once when the
/// person's framing matches the reference, then fades away. Signal only —
/// not a persistent tracking overlay.
struct MatchSilhouetteOverlay: View {
    let path: Path?
    let isVisible: Bool

    var body: some View {
        Canvas { context, _ in
            guard let path else { return }

            // Soft blurred glow — feathers the edge outward instead of a
            // hard-cut line.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                layer.stroke(
                    path,
                    with: .color(.matchGreen.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            }

            // Thin, softened core — legible but no longer a rigid uniform stroke.
            context.stroke(
                path,
                with: .color(.matchGreen.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
    }
}
