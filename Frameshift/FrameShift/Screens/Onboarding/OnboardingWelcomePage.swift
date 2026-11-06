import SwiftUI

/// Opening onboarding screen: wordmark, promise, Get started.
/// Parent owns the vertical scroll-up that reveals the rest of onboarding.
struct OnboardingWelcomePage: View {
    var onGetStarted: () -> Void

    @State private var logoVisible = false
    @State private var welcomeVisible = false
    @State private var nameVisible = false
    @State private var subtitleVisible = false
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            FrameShiftMark()
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .padding(.top, 12)
                .accessibilityHidden(true)
                .opacity(logoVisible ? 1 : 0)
                .offset(y: logoVisible ? 0 : 8)

            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome to")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(welcomeVisible ? 1 : 0)
                    .offset(y: welcomeVisible ? 0 : 14)

                (Text("Frame").foregroundStyle(.white)
                    + Text("Shift").foregroundStyle(Color.cameraYellow))
                    .font(.system(size: 40, weight: .bold))
                    .padding(.top, -4)
                    .opacity(nameVisible ? 1 : 0)
                    .offset(y: nameVisible ? 0 : 14)

                (Text("Make every shot ")
                    .foregroundStyle(.white.opacity(0.55))
                    + Text("the shot")
                        .italic()
                        .foregroundStyle(.white.opacity(0.9)))
                    .font(.system(size: 18, weight: .regular))
                    .padding(.top, 10)
                    .opacity(subtitleVisible ? 1 : 0)
                    .offset(y: subtitleVisible ? 0 : 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: onGetStarted) {
                Text("Get started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.cameraYellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get started")
            .opacity(buttonVisible ? 1 : 0)
            .offset(y: buttonVisible ? 0 : 12)
        }
        .padding(.horizontal, 28)
        .safeAreaPadding(.bottom, 16)
        .onAppear(perform: playEntrance)
    }

    private func playEntrance() {
        withAnimation(.easeOut(duration: 0.5)) {
            logoVisible = true
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.12)) {
            welcomeVisible = true
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.32)) {
            nameVisible = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.50)) {
            subtitleVisible = true
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.64)) {
            buttonVisible = true
        }
    }
}
