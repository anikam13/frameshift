import SwiftUI

/// First-launch onboarding: four swipeable pages introducing the
/// reference → guided-framing → tips loop. Shown once; completion
/// is persisted so it never reappears after the user finishes it.
struct OnboardingView: View {
    /// True when reached via Settings' "Replay Onboarding" rather than the
    /// mandatory first-launch flow — adds a close button and dismisses via
    /// the environment instead of relying on the app root's if/else swap.
    var isReplay: Bool = false

    @AppStorage("frameshift.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    /// Blocks stacked Next taps — TabView page changes plus withAnimation
    /// were racing and freezing the carousel on double-tap.
    @State private var isAdvancing = false

    private let pageCount = 4

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingWelcomePage().tag(0)
                    // Prefetch only the adjacent image page so cold start
                    // doesn't decode every onboarding asset up front.
                    Group {
                        if page >= 1 {
                            OnboardingReferencesPage()
                        } else {
                            Color.clear
                        }
                    }
                    .tag(1)
                    Group {
                        if page >= 2 {
                            OnboardingCameraPage()
                        } else {
                            Color.clear
                        }
                    }
                    .tag(2)
                    OnboardingComparePage().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .disabled(isAdvancing)

                dots
                    .padding(.bottom, 18)
                actionButton
                    .frame(height: 54)
                    .padding(.bottom, 24)
                    .disabled(isAdvancing)
                    .opacity(isAdvancing ? 0.7 : 1)
            }

            if isReplay {
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .animation(nil, value: isAdvancing)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.cameraYellow : Color.white.opacity(0.3))
                    .frame(width: index == page ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy(duration: 0.25), value: page)
    }

    @ViewBuilder
    private var actionButton: some View {
        if page == 0 {
            pillButton(title: "Get Started") { advance() }
                .padding(.horizontal, 24)
        } else if page < pageCount - 1 {
            HStack {
                Spacer()
                Button { advance() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 52, height: 52)
                        .background(Color.cameraYellow, in: Circle())
                }
                .padding(.trailing, 24)
            }
        } else {
            pillButton(title: "Start Shooting", trailingChevron: true) { finish() }
                .padding(.horizontal, 24)
        }
    }

    private func pillButton(title: String, trailingChevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if trailingChevron {
                    Spacer()
                    Image(systemName: "chevron.right")
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Color.cameraYellow, in: Capsule())
        }
    }

    private func advance() {
        guard !isAdvancing, page < pageCount - 1 else { return }
        isAdvancing = true
        UISelectionFeedbackGenerator().selectionChanged()
        // Page TabView animates selection itself — wrapping in withAnimation
        // stacked transitions and froze on rapid Next taps.
        page += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            isAdvancing = false
        }
    }

    private func finish() {
        guard !isAdvancing else { return }
        isAdvancing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        hasCompletedOnboarding = true
        if isReplay { dismiss() }
    }
}
