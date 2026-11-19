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
        GeometryReader { _ in
            ZStack {
                Color.black
                    .opacity(isLeaving ? 0 : 1)
                    .ignoresSafeArea()

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
            .overlay(alignment: .topLeading) { backButton }
            .overlay(alignment: .top) { importStatus }
            .overlay(alignment: .bottom) { recreateButton }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .onAppear {
            currentID = request.startID
            appState.ensureCutoutLoaded(for: request.startID)
            if !isImportPreparing { noteImportReady() }
        }
        // Preload the page's person cutout so Recreate's subject lift has it.
        .onChange(of: currentID) { _, id in
            if let id { appState.ensureCutoutLoaded(for: id) }
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

    /// Recreate: switch the (always mounted) camera to this reference and
    /// hand the photo to the camera-hosted `RecreateMorphView`, starting from
    /// exactly where it's drawn here. The morph must not live in this cover:
    /// leaving the gallery removes the view that presents it, which tore the
    /// cover (and an in-cover morph) down instantly.
    private func recreate() {
        guard !isLeaving,
              let photo = photos.first(where: { $0.id == currentID }) ?? photos.first
        else { return }
        appState.useReference(id: photo.id)

        guard !appState.viewfinderFrame.isEmpty else {
            appState.selectedTab = .camera
            withAnimation(.easeOut(duration: 0.25)) { isLeaving = true }
            finishLeaving(after: 0.25)
            return
        }

        // Start from where the photo is drawn now: full-bleed (cropped)
        // for portrait, aspect-fit for landscape.
        let size = photo.image.size
        let screen = UIScreen.main.bounds
        let start = size.height >= size.width
            ? screen
            : ImageContentMapper.contentRect(contentSize: size, in: screen.size, mode: .fit)

        isLeaving = true
        appState.morphReferenceID = photo.id
        appState.recreateMorph = RecreateMorphRequest(referenceID: photo.id, image: photo.image, from: start)
        // The morph now covers this photo pixel-for-pixel, so the cover can
        // vanish without its slide-down; the gallery fades under the morph.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { dismiss() }
        withAnimation(.easeOut(duration: 0.25)) { appState.selectedTab = .camera }
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
