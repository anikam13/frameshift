import SwiftUI

/// Full library grid of every captured shot, opened from the gallery
/// preview's top-right grid button. Bursts appear as one tile with a count
/// badge; tapping any tile jumps the preview back to that item. Long-press
/// or Select enters multi-select for batch delete.
struct GalleryLibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// The preview pager's selection — set on tile tap, then this dismisses.
    @Binding var selectedID: UUID

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDeleteSelection = false

    private var items: [GalleryItem] { GalleryItem.group(appState.capturedShots) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(items) { item in
                            tile(item)
                                .id(item.id)
                        }
                    }
                    .padding(.top, 6)
                }
                .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .background(.black)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $confirmDeleteSelection,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var deleteDialogTitle: String {
        let n = selectedShotCount
        if n == 1 { return "Delete 1 photo?" }
        return "Delete \(n) photos?"
    }

    private var selectedShotCount: Int {
        items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.shots.count }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if isSelecting {
                Button("Cancel") { exitSelection() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }

            Spacer()

            if isSelecting {
                Button {
                    confirmDeleteSelection = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selectedIDs.isEmpty ? Color.white.opacity(0.35) : .red)
                        .frame(width: 42, height: 42)
                }
                .disabled(selectedIDs.isEmpty)
                .accessibilityIdentifier("delete-selected-library")
            } else {
                Button("Select") {
                    withAnimation(.easeOut(duration: 0.2)) { isSelecting = true }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            }
        }
        .overlay {
            VStack(spacing: 0) {
                Text(isSelecting
                     ? (selectedIDs.isEmpty ? "Select photos" : "\(selectedIDs.count) selected")
                     : "Library")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                if !isSelecting {
                    Text(countString)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private var countString: String {
        let count = appState.capturedShots.count
        return count == 1 ? "1 photo" : "\(count) photos"
    }

    // MARK: Tiles

    private func tile(_ item: GalleryItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(uiImage: item.cover.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if item.isBurst {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.down.right")
                            .font(.system(size: 8, weight: .semibold))
                        Text("\(item.shots.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.cover.isFavorite && !isSelecting {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(5)
                }
            }
            .overlay {
                if isSelecting && isSelected {
                    Rectangle().fill(Color.white.opacity(0.28))
                } else if !isSelecting && item.id == selectedID {
                    Rectangle().stroke(Color.cameraYellow, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(
                            isSelected ? Color.white : Color.white.opacity(0.85),
                            Color.cameraYellow
                        )
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(5)
                }
            }
            .onTapGesture { handleTap(item) }
            .onLongPressGesture {
                guard !isSelecting else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeOut(duration: 0.2)) {
                    isSelecting = true
                    selectedIDs = [item.id]
                }
            }
    }

    private func handleTap(_ item: GalleryItem) {
        if isSelecting {
            toggleSelection(item.id)
            return
        }
        selectedID = item.id
        dismiss()
    }

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
        let doomed = items.filter { selectedIDs.contains($0.id) }
        let shotIDs = doomed.flatMap { $0.shots.map(\.id) }
        let remaining = items.filter { !selectedIDs.contains($0.id) }
        if selectedIDs.contains(selectedID) {
            selectedID = remaining.first?.id ?? selectedID
        }
        appState.removeCapturedShots(ids: shotIDs)
        exitSelection()
        if appState.capturedShots.isEmpty {
            dismiss()
        }
    }
}
