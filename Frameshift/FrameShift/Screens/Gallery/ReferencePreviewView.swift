import SwiftUI

/// Immersive reference preview (Paper "Reference Preview" and import
/// "Preparing / Added to Yours"). Full-bleed photo, swipe sideways through
/// the list it was opened from, round back button, and one white Recreate
/// action that takes the photo into the camera.
struct ReferencePreviewView: View {
    let request: GalleryHomeView.PreviewRequest
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var currentID: UUID?
    @State private var showAddedToast = false
    @State private var addedToastShown = false

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
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentID) {
                ForEach(photos) { photo in
                    page(photo)
                        .tag(Optional(photo.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .topLeading) { backButton }
        .overlay(alignment: .top) { importStatus }
        .overlay(alignment: .bottom) { recreateButton }
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
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .background(Circle().fill(.ultraThinMaterial))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 10)
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
            .transition(.opacity)
            .animation(.easeOut(duration: 0.25), value: isImportPreparing)
            .animation(.easeOut(duration: 0.25), value: showAddedToast)
        }
    }

    private func statusPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Capsule().fill(Color.coachPill))
            .accessibilityElement(children: .combine)
    }

    private var recreateButton: some View {
        Button {
            guard let id = currentID ?? photos.first?.id else { return }
            appState.useReference(id: id)
            appState.selectedTab = .camera
            dismiss()
        } label: {
            Text("Recreate")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
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
