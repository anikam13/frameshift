import SwiftUI
import PhotosUI

/// Reference photos the user wants to recreate. Imported from the photo
/// library (v2: shared Instagram / Pinterest links) and grouped by detected
/// style. Tapping a reference makes it active and jumps to the camera.
struct ReferencesView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = ReferencesViewModel()
    @State private var picks: [PhotosPickerItem] = []
    @State private var showSettings = false
    @State private var showHowTo = false

    // Long-press multi-select for batch delete.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDeleteSelection = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if appState.references.isEmpty {
                    emptyState
                } else {
                    groupedGrid
                }
            }
            .navigationTitle("References")
            // No toolbar "+": this view only ever appears in reference mode,
            // where the shutter-position picker below is already the add
            // button — two plus buttons on one screen read as a bug.
            // Selection controls live in the toolbar (like Photos' Select
            // mode): a bottom bar can't work here — the camera chrome is a
            // safe-area inset layered over this whole view, and it swallows
            // taps aimed at anything near the bottom edge.
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { exitSelection() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(selectedIDs.isEmpty
                             ? "Select photos"
                             : "\(selectedIDs.count) selected")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            confirmDeleteSelection = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(selectedIDs.isEmpty ? Color.secondary : .red)
                        }
                        .disabled(selectedIDs.isEmpty)
                        .accessibilityIdentifier("delete-selected-references")
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        wordmark
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showHowTo = true } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
            }
            // Presenting from navigation content — outside the stack the
            // dialog silently never appears.
            .confirmationDialog(
                "Delete \(selectedIDs.count) reference\(selectedIDs.count == 1 ? "" : "s")?",
                isPresented: $confirmDeleteSelection,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteSelection() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onChange(of: picks) { _, items in
            vm.importPhotos(items: items, into: appState)
            picks = []
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showHowTo) {
            HowToSheet()
        }
        .onAppear {
            #if DEBUG
            // UI-test hook: synthetic taps/long-presses on the grid cells are
            // unreliable, so tests enter selection mode with two references
            // pre-selected and drive only the delete path.
            if ProcessInfo.processInfo.arguments.contains("-uitest-start-selecting") {
                isSelecting = true
                selectedIDs = Set(appState.references.prefix(2).map(\.id))
            }
            #endif
        }
    }

    /// App wordmark in the bar above the References title. System font only
    /// (design-token rule) — the bare viewfinder outline and "Frame" in
    /// camera yellow carry the brand.
    private var wordmark: some View {
        HStack(spacing: 6) {
            Image(systemName: "viewfinder")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.cameraYellow)
            (
                Text("Frame").foregroundStyle(Color.cameraYellow)
                + Text("Shift").foregroundStyle(.white)
            )
            .font(.system(size: 21, weight: .semibold, design: .rounded))
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.secondary)

            Text("Recreate a shot you love")
                .font(.title3.weight(.semibold))

            Text("Save a photo from Pinterest or Instagram — FrameShift shows you exactly how to frame it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                Text("Add Photos")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Grouped grid

    private var groupedGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                if !appState.unanalyzedReferences.isEmpty {
                    section(title: "Analyzing…",
                            subtitle: nil,
                            photos: appState.unanalyzedReferences)
                }
                ForEach(appState.styleGroups, id: \.category) { group in
                    section(title: group.category.rawValue,
                            subtitle: "\(group.photos.count)",
                            photos: group.photos)
                }
                if !appState.noSubjectReferences.isEmpty {
                    section(title: "No subject detected",
                            subtitle: "\(appState.noSubjectReferences.count)",
                            photos: appState.noSubjectReferences,
                            selectable: false)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        // The camera chrome is a safe-area inset applied around this whole
        // view, but that inset doesn't propagate through the NavigationStack
        // to this ScrollView — without an explicit margin the last row stops
        // behind the chrome and can never scroll clear of it.
        .contentMargins(.bottom, CameraView.bottomChromeHeight, for: .scrollContent)
    }

    // MARK: Selection

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func exitSelection() {
        withAnimation(.easeOut(duration: 0.2)) {
            isSelecting = false
            selectedIDs = []
        }
    }

    private func deleteSelection() {
        for id in selectedIDs {
            appState.removeReference(id: id)
        }
        exitSelection()
    }

    private func section(
        title: String, subtitle: String?, photos: [ReferencePhoto], selectable: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(photos) { photo in
                    ReferenceCell(photo: photo,
                                  isActive: appState.activeReference?.id == photo.id,
                                  isSelecting: isSelecting,
                                  isSelected: selectedIDs.contains(photo.id))
                        .onTapGesture {
                            if isSelecting {
                                toggleSelection(photo.id)
                                return
                            }
                            guard selectable else { return }
                            appState.setActiveReference(id: photo.id)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                appState.selectedTab = .camera
                            }
                        }
                        // Long-press enters selection mode (replaces the old
                        // context-menu Remove — batch delete covers it).
                        .onLongPressGesture {
                            guard !isSelecting else { return }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) {
                                isSelecting = true
                                selectedIDs = [photo.id]
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - ReferenceCell

private struct ReferenceCell: View {
    let photo: ReferencePhoto
    let isActive: Bool
    var isSelecting: Bool = false
    var isSelected: Bool = false

    private var isAnalyzing: Bool { photo.spec == nil && !photo.analysisFailed }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: isActive ? 3 : 0)
            )
            // Centered, backgrounded spinner reads as "processing" against any
            // photo brightness — a small corner badge was easy to miss,
            // especially on the longer analyses (e.g. heavily tilted photos).
            .overlay {
                if isAnalyzing {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo.analysisFailed {
                    Image(systemName: "person.fill.questionmark")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(6)
                } else if isActive && !isSelecting {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            // Selection mode: dim selected photos and badge them top-right,
            // like the Photos app.
            .overlay {
                if isSelecting && isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.3))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            isSelected ? Color.white : Color.white.opacity(0.85),
                            Color.accentColor
                        )
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(5)
                }
            }
            .opacity(photo.analysisFailed ? 0.6 : (isAnalyzing ? 0.7 : 1.0))
    }
}
