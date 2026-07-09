import SwiftUI

/// Illustrates the before/after export card, and closes onboarding with the
/// on-device processing disclosure — the app's core privacy promise, so it
/// belongs at the very end of the pitch, right before the user starts shooting.
struct OnboardingComparePage: View {
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Compare & share your best shot.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("After you shoot, open it in your gallery and tap compare to create your before & after card.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 60)

            VStack(spacing: 2) {
                cardHalf(label: "REFERENCE", hue: 0.58)
                cardHalf(label: "YOUR SHOT", hue: 0.62, showWordmark: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            Spacer()

            Text("Processed entirely on-device. Nothing leaves your phone.\nPowered by Apple's on-device Vision models.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 140)
        }
    }

    private func cardHalf(label: String, hue: Double, showWordmark: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(Color(hue: hue, saturation: 0.3, brightness: 0.5))
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.cameraYellow)
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if showWordmark {
                    Text("FrameShift")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(10)
                }
            }
    }
}
