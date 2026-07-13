import SwiftUI

/// Onboarding page 2: three inspiring people-photo references that set the
/// product premise (recreate shots of others), not a fake Landscape/Urban grid.
struct OnboardingReferencesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Save a shot you love.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Upload a reference. FrameShift helps you recreate it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 48)
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            HStack(alignment: .center, spacing: 10) {
                referenceCard("OnboardingRefPortrait")
                    .rotationEffect(.degrees(-2.5))
                    .offset(y: 10)
                referenceCard("OnboardingRefCandid")
                referenceCard("OnboardingRefFullBody")
                    .rotationEffect(.degrees(2.5))
                    .offset(y: 10)
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 28)
        }
    }

    private func referenceCard(_ name: String) -> some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay(
                Image(name)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }
}
