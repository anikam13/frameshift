import SwiftUI

/// Closing onboarding page: feature tips plus privacy, no mock photos.
/// Wired as page 3 of `OnboardingView` (filename kept for call-site stability).
struct OnboardingComparePage: View {
    private struct Tip: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let body: String
    }

    private let tips: [Tip] = [
        Tip(
            id: "guides",
            symbol: "viewfinder",
            title: "Camera guides",
            body: "Match your reference with the head circle, level, grid, and coaching tips. Open the menu for LEVEL, GRID, CIRCLE, TIPS, and MATCH."
        ),
        Tip(
            id: "gallery",
            symbol: "photo.on.rectangle",
            title: "Gallery and Settings",
            body: "Open the bottom-left thumbnail to like, share, or try filters. In REFERENCE mode, tap the gear for guide defaults, storage, and permissions."
        ),
        Tip(
            id: "privacy",
            symbol: "lock.shield",
            title: "Privacy",
            body: "FrameShift runs fully on-device. No accounts, no uploads, no tracking. Read the full privacy policy anytime in Settings."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("A few things to know.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Then you are ready to shoot.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 48)
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(tips) { tip in
                    tipRow(tip)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Spacer(minLength: 16)

            Text("Processed entirely on-device. Nothing leaves your phone.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }

    private func tipRow(_ tip: Tip) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: tip.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.cameraYellow)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(tip.body)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
