import SwiftUI

/// Illustrates the live-guidance loop: the head-circle placement guide plus
/// the translucent reference-pose silhouette — matches SubjectPlacementGuide,
/// the overlay actually shown on the live camera screen.
struct OnboardingCameraPage: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("We'll guide your framing.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Line up the shot and we'll handle the rest.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 60)

            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        // Ghost silhouette of the reference pose.
                        Image(systemName: "figure.stand")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 140)
                            .foregroundStyle(Color.cameraYellow.opacity(0.4))

                        Canvas { context, size in
                            let center = CGPoint(x: size.width / 2, y: size.height * 0.32)
                            let radius: CGFloat = 30
                            let style = StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            var path = Path()
                            path.addEllipse(in: CGRect(
                                x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2
                            ))
                            context.stroke(path, with: .color(Color.cameraYellow), style: style)
                        }
                    }
                }
                .padding(.horizontal, 20)

            Spacer()
        }
    }
}
