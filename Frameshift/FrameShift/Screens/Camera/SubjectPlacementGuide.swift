import SwiftUI

/// Face circle mapped with aspect-fit to match the reference ghost.
struct SubjectPlacementGuide: View {
    let spec: ShotSpec
    let isLocked: Bool
    var isSatisfied: Bool = false

    // Deliberately translucent so the circle reads as a hint, not a UI frame.
    private var strokeColor: Color {
        if isSatisfied { return .boxLocked.opacity(0.35) }
        return isLocked ? .boxLocked.opacity(0.6) : .white.opacity(0.5)
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                drawGuide(in: size, context: &ctx)
            }
            .opacity(isSatisfied ? 0 : 1)
            .animation(.easeOut(duration: 0.25), value: isSatisfied)
            .animation(.easeOut(duration: 0.15), value: isLocked)
        }
        // The canvas spans the whole viewfinder; without this it swallows
        // the tap-to-focus and pinch gestures underneath.
        .allowsHitTesting(false)
    }

    private func drawGuide(in size: CGSize, context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
        let head = spec.headCircle(in: size)

        var headPath = Path()
        headPath.addEllipse(in: CGRect(
            x: head.center.x - head.radius,
            y: head.center.y - head.radius,
            width: head.radius * 2,
            height: head.radius * 2
        ))
        context.stroke(headPath, with: .color(strokeColor), style: style)
    }
}
