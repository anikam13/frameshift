import SwiftUI

/// Step 1: a snapping carousel of references. Cards land, then the floral
/// portrait is selected automatically. Interaction is off — this is a demo.
struct OnboardingChoosePage: View {
    @Binding var selectedAsset: String
    /// Set once the welcome slide has settled so the intro isn't cancelled
    /// mid-flight by the parent layout animation.
    var playIntro: Bool = true

    @State private var cardsIn = false
    @State private var didPlayChoice = false
    @State private var focusedAsset: String?

    private let names = OnboardingReferenceChoices.assetNames
    private let featured = OnboardingReferenceChoices.featured

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Step 1")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.cameraYellow)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text("Choose your reference photo")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .opacity(cardsIn ? 1 : 0)
            .offset(y: cardsIn ? 0 : 10)

            Spacer(minLength: 16)

            GeometryReader { geo in
                let cardWidth = geo.size.width * 0.52
                let peek = (geo.size.width - cardWidth) / 2
                let cardHeight = min(cardWidth * 4.0 / 3.0, geo.size.height)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(names, id: \.self) { name in
                            card(name, width: cardWidth, height: cardHeight)
                                .id(name)
                                .opacity(cardsIn ? 1 : 0)
                                .scaleEffect(cardsIn ? 1 : 0.94)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(true)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedAsset)
                .contentMargins(.horizontal, peek, for: .scrollContent)
                .frame(height: cardHeight)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                .allowsHitTesting(false)
            }
            .opacity(cardsIn ? 1 : 0)

            Spacer(minLength: 16)
        }
        .onAppear { startIntroIfNeeded() }
        .onChange(of: playIntro) { _, _ in startIntroIfNeeded() }
    }

    private func card(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        let selected = focusedAsset == name
        return Color.clear
            .frame(width: width, height: height)
            .overlay(
                Image(name)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? Color.cameraYellow : Color.white.opacity(0.14),
                        lineWidth: selected ? 2.5 : 1
                    )
            )
            .scaleEffect(selected ? 1.0 : 0.92)
            .opacity(selected ? 1 : 0.78)
            .shadow(color: selected ? Color.cameraYellow.opacity(0.35) : .clear, radius: 12)
            .animation(.snappy(duration: 0.22), value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityLabel("Reference photo")
            .accessibilityHidden(true)
    }

    private func startIntroIfNeeded() {
        guard playIntro, !didPlayChoice else { return }
        didPlayChoice = true
        selectedAsset = featured
        focusedAsset = names.first
        withAnimation(.easeOut(duration: 0.45)) {
            cardsIn = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                focusedAsset = featured
            }
        }
    }
}
