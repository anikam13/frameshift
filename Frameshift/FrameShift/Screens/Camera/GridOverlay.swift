import SwiftUI

/// Rule-of-thirds grid — 2 horizontal + 2 vertical lines.
/// Matches the native iOS Camera grid exactly.
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let style = StrokeStyle(lineWidth: 0.5)
                let color = GraphicsContext.Shading.color(.gridLine)

                for fraction in [1.0 / 3.0, 2.0 / 3.0] as [Double] {
                    // Horizontal
                    var h = Path()
                    h.move(to:    CGPoint(x: 0,          y: size.height * fraction))
                    h.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    ctx.stroke(h, with: color, style: style)

                    // Vertical
                    var v = Path()
                    v.move(to:    CGPoint(x: size.width * fraction, y: 0))
                    v.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                    ctx.stroke(v, with: color, style: style)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
