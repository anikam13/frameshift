import SwiftUI
import UIKit

/// First-launch onboarding: welcome scrolls up into choose-a-reference,
/// then the coach loop on that photo.
struct OnboardingView: View {
    /// True when reached via Settings' "Replay Onboarding" rather than the
    /// mandatory first-launch flow — adds a close button and dismisses via
    /// the environment instead of relying on the app root's if/else swap.
    var isReplay: Bool = false

    @EnvironmentObject private var appState: AppState
    @AppStorage("frameshift.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.dismiss) private var dismiss
    /// Remaining-loop page (0 choose reference, 1 coach).
    @State private var page = 0
    @State private var hasLeftWelcome = false
    @State private var selectedSample = OnboardingReferenceChoices.featured
    /// Blocks stacked Next taps while the page transition is in flight.
    @State private var isAdvancing = false
    /// Fires the chooser intro after the welcome slide has finished.
    @State private var chooseIntroReady = false

    private let pageCount = 2
    private let pageSlide = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.62)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    OnboardingWelcomePage(onGetStarted: leaveWelcome)
                        .frame(width: geo.size.width, height: geo.size.height)

                    remaining
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .offset(y: hasLeftWelcome ? -geo.size.height : 0)
            }
            .clipped()

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
                        .padding(.trailing, 24)
                    }
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var remaining: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack {
                    if hasLeftWelcome {
                        OnboardingChoosePage(
                            selectedAsset: $selectedSample,
                            playIntro: chooseIntroReady
                        )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .offset(x: page == 0 ? 0 : -geo.size.width)
                            .animation(pageSlide, value: page)
                            .allowsHitTesting(page == 0)

                        OnboardingReferencesPage(
                            imageName: selectedSample.isEmpty
                                ? OnboardingReferenceChoices.featured
                                : selectedSample,
                            isActive: page == 1
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: page == 0 ? geo.size.width : 0)
                        .animation(pageSlide, value: page)
                        .allowsHitTesting(page == 1)
                    }
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            dots
                .padding(.bottom, 18)
            actionButton
                .frame(height: 54)
                .padding(.bottom, 24)
                .disabled(isAdvancing)
                .opacity(isAdvancing ? 0.7 : 1)
                .animation(nil, value: isAdvancing)
                .animation(nil, value: page)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.cameraYellow : Color.white.opacity(0.3))
                    .frame(width: index == page ? 20 : 7, height: 7)
            }
        }
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.52), value: page)
    }

    @ViewBuilder
    private var actionButton: some View {
        if page < pageCount - 1 {
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
            pillButton(title: "Start shooting", trailingChevron: true) { finish() }
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

    private func leaveWelcome() {
        guard !isAdvancing, !hasLeftWelcome else { return }
        isAdvancing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.72)) {
            hasLeftWelcome = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(740))
            isAdvancing = false
            chooseIntroReady = true
        }
    }

    private func advance() {
        guard !isAdvancing, page < pageCount - 1 else { return }
        isAdvancing = true
        if selectedSample.isEmpty {
            selectedSample = OnboardingReferenceChoices.featured
        }
        UISelectionFeedbackGenerator().selectionChanged()
        page += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(640))
            isAdvancing = false
        }
    }

    private func finish() {
        guard !isAdvancing else { return }
        isAdvancing = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        importStarterPack()
        appState.activateBundledSample(named: selectedSample.isEmpty
            ? OnboardingReferenceChoices.featured
            : selectedSample)
        appState.selectedTab = .references
        hasCompletedOnboarding = true
        if isReplay { dismiss() }
    }

    private func importStarterPack() {
        let name = selectedSample.isEmpty ? OnboardingReferenceChoices.featured : selectedSample
        appState.importBundledSamples(preferring: name)
    }
}
