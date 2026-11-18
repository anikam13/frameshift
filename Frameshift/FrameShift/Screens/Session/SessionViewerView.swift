import SwiftUI

/// Comparison-first viewer (D-26). Swipe through the session; hold the photo
/// to see the reference it was shot against, release to return. The Compare
/// button toggles the same thing for people who can't press and hold (O-8).
/// No filters, editor, or Save button — photos are already in Apple Photos.
struct SessionViewerView: View {
    let startItemID: UUID
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentID: UUID?
    @State private var isHolding = false
    @State private var isComparing = false
    @State private var toast: String?

    private var items: [GalleryItem] { GalleryItem.group(appState.sessionShots) }

    private var currentItem: GalleryItem? {
        items.first { $0.id == currentID } ?? items.first
    }

    private var currentReference: ReferencePhoto? {
        appState.reference(for: currentItem?.cover.referenceID)
    }

    private var showsReference: Bool {
        currentReference != nil && (isHolding || isComparing)
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
                ForEach(items) { item in
                    page(item)
                        .tag(Optional(item.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            if let toast {
                ConfirmationToast(message: toast)
                    .padding(.bottom, 96)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .onAppear { currentID = startItemID }
        .onChange(of: currentID) { _, _ in
            isComparing = false
            isHolding = false
        }
        .onChange(of: items.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    // MARK: Top bar

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
                if let item = currentItem {
                    Menu {
                        Button {
                            saveAsReference(item.cover)
                        } label: {
                            Label("Save as Reference", systemImage: "plus.square.on.square")
                        }
                        ShareLink(
                            item: ShareableShot(shot: item.cover, appState: appState),
                            preview: SharePreview("FrameShift Photo", image: Image(uiImage: item.cover.image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private var titleText: String {
        if showsReference { return "Reference" }
        guard let item = currentItem,
              let index = items.firstIndex(where: { $0.id == item.id }) else { return "" }
        return "\(index + 1) of \(items.count)"
    }

    // MARK: Page

    private func page(_ item: GalleryItem) -> some View {
        let reference = appState.reference(for: item.cover.referenceID)
        let showRef = item.id == currentItem?.id && showsReference
        return ZStack {
            Image(uiImage: item.cover.image)
                .resizable()
                .scaledToFit()
                .opacity(showRef ? 0 : 1)
            if let reference {
                Image(uiImage: reference.image)
                    .resizable()
                    .scaledToFit()
                    .opacity(showRef ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.12), value: showRef)
        .contentShape(Rectangle())
        // Hold to compare; release returns to the capture.
        .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 30) {
        } onPressingChanged: { pressing in
            guard reference != nil else { return }
            if pressing && !isHolding {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            isHolding = pressing
        }
        .accessibilityLabel(showRef ? "Reference photo" : "Captured photo")
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        Group {
            if currentReference != nil {
                Button {
                    isComparing.toggle()
                } label: {
                    Text(showsReference ? "Show Photo" : "Compare")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 172, height: 48)
                        .background(Capsule().fill(Color(hex: "#262626")))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the reference this photo was taken with. You can also press and hold the photo.")
            } else {
                Color.clear.frame(height: 48)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 20)
    }

    private func saveAsReference(_ shot: CapturedPhoto) {
        Task {
            let added = await appState.addCapturedShotsAsReferences(ids: [shot.id])
            guard added > 0 else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            toast = "Added to Yours"
            try? await Task.sleep(for: .seconds(2))
            toast = nil
        }
    }
}
