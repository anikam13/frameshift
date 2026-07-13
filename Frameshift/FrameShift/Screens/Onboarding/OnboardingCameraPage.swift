import SwiftUI

/// Onboarding page 3: camera coaching screenshot (head circle, grid, tips).
struct OnboardingCameraPage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("We will guide your framing.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Line up the shot and we will handle the rest.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 48)
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            Image("OnboardingCameraGuide")
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .padding(.horizontal, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Spacer(minLength: 28)
        }
    }
}
