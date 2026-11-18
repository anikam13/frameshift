import SwiftUI

/// Burst review (Paper page "07"). Page through one burst, pick a frame on
/// the filmstrip, and Set as Cover — the frame the session grid shows.
struct BurstReviewView: View {
    let burstID: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: UUID?

    private var shots: [CapturedPhoto] {
        // Oldest first reads as capture order on the filmstrip.
        appState.sessionShots.filter { $0.burstID == burstID }.reversed()
    }

    private var current: CapturedPhoto? {
        shots.first { $0.id == currentID } ?? shots.first
    }

    var body: some View {
        // Text scales with Dynamic Type up to the largest standard size;
        // fixed-height controls would clip at accessibility sizes (D-32).
        screen.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var screen: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $currentID) {
                ForEach(shots) { shot in
                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(Optional(shot.id))
                        .accessibilityLabel("Burst photo")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            filmstrip
            coverButton
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            // Open on the frame the grid shows: the picked cover, else the newest.
            currentID = (shots.first { $0.isBurstBest } ?? shots.last)?.id
        }
        .onChange(of: shots.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    private var topBar: some View {
        ZStack {
            Text(titleText)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white)
                .monospacedDigit()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(.body, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private var titleText: String {
        guard let current, let index = shots.firstIndex(where: { $0.id == current.id }) else { return "" }
        return "\(index + 1) of \(shots.count)"
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(shots) { shot in
                        let selected = shot.id == current?.id
                        Image(uiImage: shot.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.cameraYellow, lineWidth: selected ? 2 : 0)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                if shot.isBurstBest {
                                    Image(systemName: "star.fill")
                                        .font(.system(.caption2))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 1)
                                        .padding(3)
                                }
                            }
                            .id(shot.id)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) { currentID = shot.id }
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(height: 56)
        .padding(.top, 14)
    }

    private var coverButton: some View {
        let isCover = current?.isBurstBest ?? false
        return Button {
            guard let current else { return }
            appState.setBurstBest(id: current.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(isCover ? "Cover" : "Set as Cover", systemImage: isCover ? "checkmark" : "")
                .labelStyle(CoverLabelStyle(showsIcon: isCover))
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(Color(hex: "#262626")))
        }
        .buttonStyle(.plain)
        .disabled(isCover)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }
}

private struct CoverLabelStyle: LabelStyle {
    let showsIcon: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if showsIcon { configuration.icon }
            configuration.title
        }
    }
}
