import SwiftUI
import PhotosUI

/// The gallery home (Paper page "02 · Discovery"). Compact FrameShift
/// wordmark with Resume Camera, `+` import and `⋯`; one merged favorites +
/// recent row; an Explore / Yours switch; Explore composition chips; and a
/// 2-column photo grid. The switch and chips stay pinned while the quick row
/// scrolls away. Follows the system appearance (the camera is always dark).
struct GalleryHomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var importer = ReferencesViewModel()

    enum Source: Hashable { case explore, yours }

    @State private var source: Source = .explore
    @State private var filter: CompositionFilter = .all
    @State private var picks: [PhotosPickerItem] = []
    @State private var preview: PreviewRequest?
    @State private var removeCandidate: ReferencePhoto?
    @State private var showSettings = false
    @State private var showHowTo = false
    @AppStorage(FirstUseTour.exploreDoneKey) private var exploreTourDone = false
    @State private var tourStep: Int?

    /// The photos the preview pages through, the one it opens on, and (for
    /// a fresh import) which one shows the preparing / added toast.
    struct PreviewRequest: Identifiable {
        let id = UUID()
        let ids: [UUID]
        let startID: UUID
        var importedID: UUID?
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// Resume Camera shows only while a capture session is active (D-4).
    private var hasActiveSession: Bool {
        !appState.sessionShots.isEmpty
    }

    private var gridPhotos: [ReferencePhoto] {
        switch source {
        case .explore: return appState.curatedReferences.filter(filter.matches)
        case .yours:   return appState.importedReferences
        }
    }

    var body: some View {
        // Text scales with Dynamic Type up to the largest standard size;
        // fixed-height controls would clip at accessibility sizes (D-32).
        screen.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var screen: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    quickRow
                    Section {
                        grid
                    } header: {
                        pinnedControls
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            TourOverlay(steps: FirstUseTour.explore, index: $tourStep, anchors: anchors) {
                exploreTourDone = true
            }
        }
        .task(id: tourTrigger) { await startTourIfNeeded() }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            importer.importPhotos(items: items, into: appState) { id in
                source = .yours
                preview = PreviewRequest(
                    ids: appState.importedReferences.map(\.id),
                    startID: id,
                    importedID: id
                )
            }
            picks = []
        }
        .task(id: appState.hasFinishedRestoringReferences) {
            // Explore is the curated catalog: keep it whole. First launch
            // seeds it; this fills gaps for older libraries.
            guard appState.hasFinishedRestoringReferences,
                  !appState.missingBundledSampleNames.isEmpty
            else { return }
            appState.importBundledSamples()
        }
        .fullScreenCover(item: $preview) { request in
            ReferencePreviewView(request: request)
                .environmentObject(appState)
                // Transparent so Recreate can morph the photo onto the camera.
                .presentationBackground(.clear)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showHowTo) {
            NavigationStack {
                HowToUseView {
                    showHowTo = false
                    FirstUseTour.reset()
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showHowTo = false }
                    }
                }
            }
        }
        .alert(
            "Remove Reference?",
            isPresented: Binding(
                get: { removeCandidate != nil },
                set: { if !$0 { removeCandidate = nil } }
            ),
            presenting: removeCandidate
        ) { photo in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                appState.removeReference(id: photo.id)
            }
        } message: { _ in
            Text("This removes it from FrameShift. The original photo stays in Photos.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 0) {
            Text("FrameShift")
                .font(.system(.title2, weight: .bold))
                .tracking(-0.77)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if hasActiveSession {
                    headerButton(systemName: "camera", label: "Resume Camera") {
                        openCamera()
                    }
                }
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                    headerGlyph("plus")
                }
                .tourAnchor(.exploreImport)
                .accessibilityLabel("Add Photo")
                Menu {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button { showHowTo = true } label: {
                        Label("How to Use", systemImage: "questionmark.circle")
                    }
                } label: {
                    headerGlyph("ellipsis")
                }
                .accessibilityLabel("More")
            }
            .tint(.primary)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func headerGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(.title3, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func headerButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { headerGlyph(systemName) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    // MARK: Quick access

    /// Favorites first, then recently used. Tapping goes straight to the
    /// camera (D-8): these are photos the user has already chosen.
    @ViewBuilder
    private var quickRow: some View {
        let quick = appState.quickAccessReferences
        if !quick.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(quick) { photo in
                        Button {
                            recreate(photo.id)
                        } label: {
                            thumbnail(photo, width: 62, height: 76)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.isFavorite ? "Favorite reference" : "Recent reference")
                        .contextMenu { referenceActions(photo) } preview: { contextPreview(photo) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    // MARK: Pinned switch + chips

    private var pinnedControls: some View {
        VStack(spacing: 0) {
            SourceSwitch(selection: $source)
                .padding(.horizontal, 16)
            if source == .explore {
                chips
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .padding(.top, appState.quickAccessReferences.isEmpty ? 8 : 0)
        .background(Color(.systemBackground))
    }

    private var availableFilters: [CompositionFilter] {
        CompositionFilter.allCases.filter { option in
            option == .all || appState.curatedReferences.contains(where: option.matches)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(availableFilters, id: \.self) { option in
                    let selected = option == filter
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { filter = option }
                    } label: {
                        Text(option.title)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                Capsule().fill(selected ? Color.primary : Color(.systemGray6))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Grid

    @ViewBuilder
    private var grid: some View {
        let photos = gridPhotos
        if photos.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(photos) { photo in
                    Button {
                        preview = PreviewRequest(ids: photos.map(\.id), startID: photo.id)
                    } label: {
                        GalleryReferenceTile(photo: photo)
                    }
                    .buttonStyle(.plain)
                    .modifier(FirstTileAnchor(isFirst: photo.id == photos.first?.id && source == .explore))
                    .contextMenu { referenceActions(photo) } preview: { contextPreview(photo) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch source {
        case .explore:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
        case .yours:
            VStack(spacing: 0) {
                Text("No imported references")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Add a photo from your library.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                    Label("Add Photo", systemImage: "plus")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 26)
                        .frame(height: 50)
                        .background(Capsule().fill(Color.primary))
                }
                .padding(.top, 18)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 170)
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private func referenceActions(_ photo: ReferencePhoto) -> some View {
        Button {
            appState.setReferenceFavorite(id: photo.id, isFavorite: !photo.isFavorite)
        } label: {
            Label(photo.isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: photo.isFavorite ? "heart.slash" : "heart")
        }
        ShareLink(
            item: Image(uiImage: photo.image),
            preview: SharePreview("Reference", image: Image(uiImage: photo.image))
        ) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if !photo.isCurated {
            Button(role: .destructive) {
                removeCandidate = photo
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func contextPreview(_ photo: ReferencePhoto) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 300, maxHeight: 420)
    }

    private func thumbnail(_ photo: ReferencePhoto, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Tour

    private var tourTrigger: String {
        "\(exploreTourDone)-\(appState.curatedReferences.isEmpty)-\(appState.selectedTab == .references)"
    }

    /// Explore tour: first time the curated grid is on screen (or after
    /// Replay Tutorial).
    private func startTourIfNeeded() async {
        guard !exploreTourDone, tourStep == nil,
              appState.selectedTab == .references,
              !appState.curatedReferences.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, !exploreTourDone else { return }
        source = .explore
        filter = .all
        tourStep = 0
    }

    // MARK: Actions

    private func recreate(_ id: UUID) {
        appState.useReference(id: id)
        openCamera()
    }

    private func openCamera() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            appState.selectedTab = .camera
        }
    }
}

// MARK: - Explore / Yours switch

/// Segmented control drawn to the Paper spec (36pt, r9, 3pt inset thumb) —
/// the system segmented control can't take these metrics.
private struct SourceSwitch: View {
    @Binding var selection: GalleryHomeView.Source
    @Namespace private var thumb

    private static let thumbFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray4 : .white
    })

    var body: some View {
        HStack(spacing: 0) {
            segment("Explore", .explore)
            segment("Yours", .yours)
        }
        .padding(3)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.systemGray6)))
    }

    private func segment(_ title: String, _ value: GalleryHomeView.Source) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selection = value }
        } label: {
            Text(title)
                .font(.system(.subheadline, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Self.thumbFill)
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Grid tile

/// 173×228 r8 photo tile. Favorited curated photos carry a bookmark (D-9);
/// imports show analysis state.
struct GalleryReferenceTile: View {
    let photo: ReferencePhoto

    private var isAnalyzing: Bool { photo.spec == nil && !photo.analysisFailed }

    var body: some View {
        Color(.systemGray6)
            .aspectRatio(173.0 / 228.0, contentMode: .fit)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if photo.isCurated && photo.isFavorite {
                    Image(systemName: "bookmark.fill")
                        .font(.system(.subheadline))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(10)
                        .accessibilityLabel("Favorite")
                }
            }
            .overlay {
                if isAnalyzing && !photo.isCurated {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Curated photos are vetted; only imports can fail analysis.
                if photo.analysisFailed && !photo.isCurated {
                    Label("No person found", systemImage: "person.fill.questionmark")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.coachPill, in: Capsule())
                        .padding(8)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(photo.isCurated ? "Curated reference" : "Your reference")
    }
}

private struct FirstTileAnchor: ViewModifier {
    let isFirst: Bool
    func body(content: Content) -> some View {
        if isFirst {
            content.tourAnchor(.exploreFirstTile)
        } else {
            content
        }
    }
}
