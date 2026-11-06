import SwiftUI

/// Viewfinder brackets plus a head circle shifted left of center —
/// the same mark as the app icon / onboarding logo.
struct FrameShiftMark: View {
    var body: some View {
        Canvas { ctx, size in
            let stroke = size.width * 0.072
            let inset = size.width * 0.215
            let arm = size.width * 0.175

            var corners = Path()
            func armPath(_ a: CGPoint, _ b: CGPoint) {
                corners.move(to: a)
                corners.addLine(to: b)
            }

            let l = inset
            let r = size.width - inset
            let t = inset
            let b = size.height - inset

            armPath(CGPoint(x: l, y: t + arm), CGPoint(x: l, y: t))
            armPath(CGPoint(x: l, y: t), CGPoint(x: l + arm, y: t))
            armPath(CGPoint(x: r - arm, y: t), CGPoint(x: r, y: t))
            armPath(CGPoint(x: r, y: t), CGPoint(x: r, y: t + arm))
            armPath(CGPoint(x: l, y: b - arm), CGPoint(x: l, y: b))
            armPath(CGPoint(x: l, y: b), CGPoint(x: l + arm, y: b))
            armPath(CGPoint(x: r - arm, y: b), CGPoint(x: r, y: b))
            armPath(CGPoint(x: r, y: b), CGPoint(x: r, y: b - arm))

            ctx.stroke(
                corners,
                with: .foreground,
                style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
            )

            let circleD = size.width * 0.235
            let circle = CGRect(
                x: size.width * 0.445 - circleD / 2,
                y: (size.height - circleD) / 2,
                width: circleD,
                height: circleD
            )
            ctx.stroke(
                Path(ellipseIn: circle),
                with: .foreground,
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
