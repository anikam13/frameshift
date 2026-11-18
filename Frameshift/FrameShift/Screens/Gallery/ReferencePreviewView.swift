import SwiftUI

/// Immersive reference preview (Paper "Reference Preview" and import
/// "Preparing / Added to Yours"). Full-bleed photo, swipe sideways through
/// the list it was opened from, round back button, and one white Recreate
/// action that takes the photo into the camera.
struct ReferencePreviewView: View {
    let request: GalleryHomeView.PreviewRequest
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentID: UUID?
    @State private var showAddedToast = false
    @State private var addedToastShown = false

    // Recreate morph (D-29): the photo shrinks onto the viewfinder and fades
    // into the overlay while the camera shows through.
    @State private var morphPhoto: ReferencePhoto?
    @State private var morphFrame: CGRect = .zero
    @State private var morphOpacity: Double = 1
    @State private var isLeaving = false

    /// Only ids still in the library (a page can be removed elsewhere).
    private var photos: [ReferencePhoto] {
        request.ids.compactMap { id in appState.references.first { $0.id == id } }
    }

    private var importedPhoto: ReferencePhoto? {
        guard let id = request.importedID else { return nil }
        return appState.references.first { $0.id == id }
    }

    private var isImportPreparing: Bool {
        guard let photo = importedPhoto else { return false }
        return photo.spec == nil && !photo.analysisFailed
    }

    var body: some View {
        // Text scales with Dynamic Type up to the largest standard size;
        // fixed-height controls would clip at accessibility sizes (D-32).
        screen.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var screen: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(isLeaving ? 0 : 1)
                    .ignoresSafeArea()

                if let morphPhoto {
                    let origin = proxy.frame(in: .global).origin
                    Image(uiImage: morphPhoto.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: morphFrame.width, height: morphFrame.height)
                        .clipped()
                        .opacity(morphOpacity)
                        .position(x: morphFrame.midX - origin.x, y: morphFrame.midY - origin.y)
                        .allowsHitTesting(false)
                } else {
                    TabView(selection: $currentID) {
                        ForEach(photos) { photo in
                            page(photo)
                                .tag(Optional(photo.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .opacity(isLeaving ? 0 : 1)
                    .ignoresSafeArea()
                }
            }
            .overlay(alignment: .topLeading) { backButton }
            .overlay(alignment: .top) { importStatus }
            .overlay(alignment: .bottom) { recreateButton }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .onAppear {
            currentID = request.startID
            if !isImportPreparing { noteImportReady() }
        }
        .onChange(of: isImportPreparing) { _, preparing in
            if !preparing { noteImportReady() }
        }
    }

    private func page(_ photo: ReferencePhoto) -> some View {
        GeometryReader { geo in
            let portrait = photo.image.size.height >= photo.image.size.width
            Image(uiImage: photo.image)
                .resizable()
                .aspectRatio(contentMode: portrait ? .fill : .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .accessibilityLabel("Reference photo")
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 10)
        .opacity(isLeaving ? 0 : 1)
        .accessibilityLabel("Back")
    }

    /// Import status pill — only on the freshly imported photo's page.
    @ViewBuilder
    private var importStatus: some View {
        if let imported = importedPhoto, currentID == imported.id {
            Group {
                if isImportPreparing {
                    statusPill {
                        ProgressView().tint(.white).controlSize(.small)
                        Text("Preparing reference…")
                    }
                } else if imported.analysisFailed, showAddedToast {
                    statusPill {
                        Image(systemName: "person.fill.questionmark")
                        Text("No person found — overlay unavailable")
                    }
                } else if showAddedToast {
                    statusPill {
                        Image(systemName: "checkmark")
                        Text("Added to Yours")
                    }
                }
            }
            .padding(.top, 72)
            .opacity(isLeaving ? 0 : 1)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.25), value: isImportPreparing)
            .animation(.easeOut(duration: 0.25), value: showAddedToast)
        }
    }

    private func statusPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(Color.coachPill))
            .accessibilityElement(children: .combine)
    }

    private var recreateButton: some View {
        Button {
            recreate()
        } label: {
            Text("Recreate")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .opacity(isLeaving ? 0 : 1)
        .disabled(isLeaving)
        .accessibilityHint("Opens the camera with this reference")
    }

    /// Recreate: switch the (already mounted) camera to this reference, then
    /// morph the photo onto the viewfinder and fade it into the overlay.
    /// Reduce Motion: a plain cross-fade.
    private func recreate() {
        guard !isLeaving,
              let photo = photos.first(where: { $0.id == currentID }) ?? photos.first
        else { return }
        appState.useReference(id: photo.id)
        appState.selectedTab = .camera

        let viewfinder = appState.viewfinderFrame
        if reduceMotion || viewfinder.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) { isLeaving = true }
            finishLeaving(after: 0.25)
            return
        }

        // Fly from where the photo is drawn now to exactly where the camera
        // overlay draws it (aspect-fit in the viewfinder), so the hand-off
        // has no jump. Both rects share the photo's aspect except the
        // full-bleed portrait start, whose crop unwinds during the flight.
        let size = photo.image.size
        let screen = UIScreen.main.bounds
        let start = size.height >= size.width
            ? screen
            : ImageContentMapper.contentRect(contentSize: size, in: screen.size, mode: .fit)
        let fit = ImageContentMapper.contentRect(contentSize: size, in: viewfinder.size, mode: .fit)
        let target = fit.offsetBy(dx: viewfinder.minX, dy: viewfinder.minY)

        // Choreography (see docs/design-decisions.md D-29):
        // 1. Flight — critically damped spring (no bounce: nothing was flung),
        //    the photo goes semi-transparent as it travels so the live feed
        //    reads through it. The overlay is held back so the person isn't
        //    double-exposed.
        // 2. Hand-off, slightly before the spring settles — photo fades out
        //    while the overlay fades in, in one transaction.
        morphPhoto = photo
        morphFrame = start
        morphOpacity = 1
        appState.isRecreateMorphInFlight = true
        withAnimation(.spring(duration: 0.45, bounce: 0)) {
            isLeaving = true
            morphFrame = target
            morphOpacity = 0.6
        }
        Task {
            try? await Task.sleep(for: .seconds(0.38))
            withAnimation(.easeOut(duration: 0.25)) {
                morphOpacity = 0
                appState.isRecreateMorphInFlight = false
            }
        }
        finishLeaving(after: 0.68)
    }

    /// The cover is fully transparent by now, so its own dismissal is invisible.
    private func finishLeaving(after delay: Double) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }

    private func noteImportReady() {
        guard importedPhoto != nil, !addedToastShown else { return }
        addedToastShown = true
        showAddedToast = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            showAddedToast = false
        }
    }
}
