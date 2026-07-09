import SwiftUI

/// Target framing guide derived from the reference's ShotSpec.
/// A faint full outline + emphasized rounded corner brackets. Static —
/// it reflects the reference, it does not track the live subject.
struct BoundingBoxOverlay: View {
    let spec: ShotSpec
    let isLocked: Bool   // true when focus is tapped — turns camera yellow

    private let armLength: CGFloat = 24
    private let cornerRadius: CGFloat = 10

    private var strokeColor: Color {
        isLocked ? .boxLocked : .boxIdle
    }

    var body: some View {
        GeometryReader { geo in
            let rect = spec.boxRect(in: geo.size)
            Canvas { ctx, _ in
                // Faint connecting outline
                ctx.stroke(
                    Path(roundedRect: rect, cornerRadius: cornerRadius),
                    with: .color(strokeColor.opacity(0.30)),
                    style: StrokeStyle(lineWidth: 1)
                )
                // Emphasized corner brackets
                ctx.stroke(
                    brackets(for: rect),
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 2)
            .animation(.easeOut(duration: 0.15), value: isLocked)
        }
    }

    // MARK: Path

    private func brackets(for rect: CGRect) -> Path {
        var p = Path()
        let a = armLength
        let r = cornerRadius

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + a))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                       control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + a, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - a, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                       control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + a))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - a))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - a, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + a, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - a))

        return p
    }
}
