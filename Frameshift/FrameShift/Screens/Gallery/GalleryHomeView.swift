import SwiftUI
import PhotosUI

/// The gallery home (Paper page "02 · Discovery"). Compact FrameShift
/// wordmark with Resume Camera, `+` import and `⋯`; one merged favorites +
/// recent row; an Explore / Yours switch; Explore composition chips; and a
/// 2-column photo grid. The switch and chips stay pinned while the quick row
/// scrolls away. Follows the system appearance (the camera is always dark).
struct GalleryHomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var importer = ReferencesViewModel()

    enum Source: Hashable { case explore, yours }

    @State private var source: Source = .explore
    @State private var filter: CompositionFilter = .all
    /// Explore's Women / Men toggle; nil = everyone.
    @State private var subject: SampleReferencePack.Subject?
    @State private var picks: [PhotosPickerItem] = []
    @State private var preview: PreviewRequest?
    @State private var removeCandidate: ReferencePhoto?
    @State private var shareImage: SessionViewerView.ShareImage?
    @State private var showSettings = false
    @State private var showHowTo = false
    @AppStorage(FirstUseTour.exploreDoneKey) private var exploreTourDone = false
    @AppStorage(Welcome.doneKey) private var welcomeDone = false
    @State private var tourStep: Int?
    /// Sideways page drag between Explore and Yours: how far the grid has
    /// moved, and whether this drag turned out to be horizontal.
    @State private var pageOffset: CGFloat = 0
    @State private var pageDragIsHorizontal: Bool?
    @State private var isPaging = false
    /// A sideways drag that started on a tile must not also open it.
    @State private var suppressTileTap = false

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

    private func gridPhotos(_ source: Source) -> [ReferencePhoto] {
        switch source {
        case .explore:
            return appState.curatedReferences
                .filter(filter.matches)
                .filter { photo in
                    guard let subject else { return true }
                    return photo.bundledAssetName.flatMap(CuratedCatalog.subject(for:)) == subject
                }
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
                        pagedGrid
                    } header: {
                        pinnedControls
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(pageDragIsHorizontal == true)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            TourOverlay(steps: FirstUseTour.explore, index: $tourStep, anchors: anchors) {
                exploreTourDone = true
            }
        }
        .task(id: tourTrigger) { await startTourIfNeeded() }
        // Tour step 1 is completed by tapping the spotlighted sample.
        .onChange(of: preview?.id) { _, id in
            if id != nil, tourStep == 0 { tourStep = 1 }
        }
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
        .sheet(item: $shareImage) { item in
            ActivityView(items: [item.image])
                .presentationDetents([.medium, .large])
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

    /// Favorites first, then recently used, each under its own small label
    /// so the two read as separate groups. Tapping goes straight to the
    /// camera (D-8): these are photos the user has already chosen.
    @ViewBuilder
    private var quickRow: some View {
        let quick = appState.quickAccessReferences
        let favorites = quick.filter(\.isFavorite)
        let recents = quick.filter { !$0.isFavorite }
        if !quick.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    if !favorites.isEmpty { quickGroup("Favorites", favorites) }
                    if !recents.isEmpty { quickGroup("Recents", recents) }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .transition(.opacity)
        }
    }

    private func quickGroup(_ title: String, _ photos: [ReferencePhoto]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                ForEach(photos) { photo in quickTile(photo) }
            }
        }
    }

    private func quickTile(_ photo: ReferencePhoto) -> some View {
        // The tile's on-screen rect is where the Recreate morph takes off from.
        GeometryReader { geo in
            Button {
                recreate(photo, from: geo.frame(in: .global))
            } label: {
                thumbnail(photo, width: 62, height: 76)
                    .overlay(alignment: .bottomTrailing) {
                        if photo.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "#FF375F"))
                                .padding(4)
                                .background(Circle().fill(.white))
                                .padding(4)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 62, height: 76)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .onAppear { appState.ensureCutoutLoaded(for: photo.id) }
        .accessibilityLabel(photo.isFavorite ? "Favorite reference" : "Recent reference")
        .contextMenu { referenceActions(photo) } preview: { contextPreview(photo) }
    }

    // MARK: Pinned switch + chips

    private var pinnedControls: some View {
        VStack(spacing: 0) {
            SourceSwitch(selection: source, progress: pageProgress) { switchSource(to: $0) }
                .padding(.horizontal, 16)
            // Explore's chips (62pt row) fold away with the page drag
            // instead of vanishing at the end of it, so the grid never jumps.
            let explore = 1 - pageProgress
            chips
                .frame(height: 20 + 42 * explore, alignment: .top)
                .clipped()
                .opacity(max(0, explore * 1.6 - 0.6))
                .allowsHitTesting(explore > 0.5)
                .accessibilityHidden(explore < 0.5)
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
                SubjectToggle(selection: $subject)
                Divider().frame(height: 20)
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

    /// The current grid follows a sideways drag, with the other source's grid
    /// riding alongside; past a third of the width (or a flick) it pages.
    private var pagedGrid: some View {
        let width = UIScreen.main.bounds.width
        let other: Source = source == .explore ? .yours : .explore
        let otherSide: CGFloat = source == .explore ? 1 : -1
        return grid(source, isMain: true)
            // Short grids (an empty Yours) still take the swipe below them.
            .frame(minHeight: UIScreen.main.bounds.height * 0.6, alignment: .top)
            .contentShape(Rectangle())
            .offset(x: pageOffset)
            .overlay(alignment: .top) {
                if pageOffset != 0 {
                    grid(other, isMain: false)
                        .offset(x: pageOffset + otherSide * width)
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(pageDrag(width: width), including: tourStep == nil ? .all : .subviews)
    }

    /// 0 = Explore, 1 = Yours; drives the switch's thumb during a drag.
    private var pageProgress: CGFloat {
        let width = UIScreen.main.bounds.width
        let base: CGFloat = source == .explore ? 0 : 1
        return min(max(base - pageOffset / width, 0), 1)
    }

    private func pageDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isPaging else { return }
                let t = value.translation
                if pageDragIsHorizontal == nil {
                    pageDragIsHorizontal = abs(t.width) > abs(t.height) * 1.3
                }
                guard pageDragIsHorizontal == true else { return }
                suppressTileTap = true
                // Nothing beyond Explore (left) or Yours (right): resist.
                let outward = (source == .explore && t.width > 0) || (source == .yours && t.width < 0)
                pageOffset = outward ? t.width * 0.2 : t.width
            }
            .onEnded { value in
                defer {
                    pageDragIsHorizontal = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        suppressTileTap = false
                    }
                }
                guard pageDragIsHorizontal == true, !isPaging else { return }
                let travel = value.translation.width
                let flick = value.predictedEndTranslation.width
                if source == .explore, travel < -width * 0.3 || flick < -width * 0.6 {
                    switchSource(to: .yours)
                } else if source == .yours, travel > width * 0.3 || flick > width * 0.6 {
                    switchSource(to: .explore)
                } else {
                    withAnimation(.spring(duration: 0.3, bounce: 0)) { pageOffset = 0 }
                }
            }
    }

    /// Slides the current grid out and the other in (tap or drag), then
    /// swaps which one is "current" with nothing visibly changing.
    private func switchSource(to target: Source) {
        guard target != source, !isPaging else { return }
        let width = UIScreen.main.bounds.width
        isPaging = true
        if pageOffset == 0 {
            // Tap: start from rest with the neighbour just off-screen.
            pageOffset = target == .yours ? -0.001 : 0.001
        }
        withAnimation(.spring(duration: 0.32, bounce: 0)) {
            pageOffset = target == .yours ? -width : width
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                source = target
                pageOffset = 0
            }
            isPaging = false
        }
    }

    @ViewBuilder
    private func grid(_ source: Source, isMain: Bool) -> some View {
        let photos = gridPhotos(source)
        if photos.isEmpty {
            emptyState(source)
        } else {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(photos) { photo in
                    Button {
                        guard !suppressTileTap, !isPaging else { return }
                        preview = PreviewRequest(ids: photos.map(\.id), startID: photo.id)
                    } label: {
                        GalleryReferenceTile(photo: photo)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) { favoriteButton(photo) }
                    .modifier(FirstTileAnchor(isFirst: isMain && photo.id == photos.first?.id && source == .explore))
                    .contextMenu { referenceActions(photo) } preview: { contextPreview(photo) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func emptyState(_ source: Source) -> some View {
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

    /// Empty heart on every tile; tap to favorite (joins the quick row).
    private func favoriteButton(_ photo: ReferencePhoto) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.smooth(duration: 0.3)) {
                appState.setReferenceFavorite(id: photo.id, isFavorite: !photo.isFavorite)
            }
        } label: {
            Image(systemName: photo.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(photo.isFavorite ? Color(hex: "#FF375F") : .white)
                .shadow(color: .black.opacity(0.4), radius: 3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .accessibilityLabel(photo.isFavorite ? "Remove from Favorites" : "Add to Favorites")
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
        // A plain button: ShareLink builds its transferable up front, which
        // made the first long-press slow to open.
        Button {
            shareImage = SessionViewerView.ShareImage(image: photo.image)
        } label: {
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
        "\(exploreTourDone)-\(welcomeDone)-\(appState.curatedReferences.isEmpty)-\(appState.selectedTab == .references)"
    }

    /// Explore tour: first time the curated grid is on screen (or after
    /// Replay Tutorial).
    private func startTourIfNeeded() async {
        guard !exploreTourDone, welcomeDone, tourStep == nil,
              appState.selectedTab == .references,
              !appState.curatedReferences.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, !exploreTourDone else { return }
        source = .explore
        filter = .all
        subject = nil
        tourStep = 0
    }

    // MARK: Actions

    private func recreate(_ id: UUID) {
        appState.useReference(id: id)
        openCamera()
    }

    /// Quick row: the tile flies into the camera (`RecreateMorphView`).
    private func recreate(_ photo: ReferencePhoto, from tile: CGRect) {
        guard !appState.viewfinderFrame.isEmpty else {
            recreate(photo.id)
            return
        }
        appState.useReference(id: photo.id)
        appState.morphReferenceID = photo.id
        appState.recreateMorph = RecreateMorphRequest(
            referenceID: photo.id, image: photo.image, from: tile
        )
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
    let selection: GalleryHomeView.Source
    /// 0 = Explore, 1 = Yours; follows the grid during a page drag.
    let progress: CGFloat
    let onSelect: (GalleryHomeView.Source) -> Void

    private static let thumbFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray4 : .white
    })

    var body: some View {
        GeometryReader { geo in
            let segment = geo.size.width / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Self.thumbFill)
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                    .frame(width: segment)
                    .offset(x: progress * segment)
                HStack(spacing: 0) {
                    segmentButton("Explore", .explore, emphasized: progress < 0.5)
                    segmentButton("Yours", .yours, emphasized: progress >= 0.5)
                }
            }
        }
        .padding(3)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(.systemGray6)))
    }

    private func segmentButton(_ title: String, _ value: GalleryHomeView.Source, emphasized: Bool) -> some View {
        Button {
            onSelect(value)
        } label: {
            Text(title)
                .font(.system(.subheadline, weight: emphasized ? .bold : .regular))
                .foregroundStyle(emphasized ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

// MARK: - Women / Men toggle

/// Two chips that act as one toggle: tap Women or Men to narrow Explore,
/// tap the selected one again to show everyone.
private struct SubjectToggle: View {
    @Binding var selection: SampleReferencePack.Subject?

    var body: some View {
        HStack(spacing: 8) {
            chip("Women", .women)
            chip("Men", .men)
        }
    }

    private func chip(_ title: String, _ value: SampleReferencePack.Subject) -> some View {
        let selected = selection == value
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selection = selected ? nil : value
            }
        } label: {
            Text(title)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule().fill(selected ? Color.primary : Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Grid tile

/// 173×228 r8 photo tile; imports show analysis state. The favorite heart
/// is a separate button laid over it by the grid.
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
