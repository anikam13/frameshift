import SwiftUI

struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            (Text("Frame").foregroundStyle(.white) + Text("Shift").foregroundStyle(Color.cameraYellow))
                .font(.system(size: 40, weight: .bold))

            Text("Recreate any shot.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()
            Spacer()
        }
        .padding(.bottom, 100)
    }
}
