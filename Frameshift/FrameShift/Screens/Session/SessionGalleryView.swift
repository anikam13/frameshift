import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// Session gallery (Paper page "03 · Session & viewer"). This shoot's photos,
/// already saved to Apple Photos — not a second archive (D-25). Bursts
/// collapse to one tile with a count badge. Select → Add to References or
/// Share. Opened from the camera's session thumbnail; the camera glyph
/// returns to the camera.
struct SessionGalleryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var viewerStart: ViewerRequest?
    @State private var burstReview: GalleryItem?
    @State private var toast: String?
    @State private var isAdding = false

    struct ViewerRequest: Identifiable {
        let id = UUID()
        let startItemID: UUID
    }

    private var shots: [CapturedPhoto] { appState.sessionShots }
    private var items: [GalleryItem] { GalleryItem.group(shots) }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(items) { item in
                            tile(item)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting { selectionBar }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ConfirmationToast(message: toast)
                    .padding(.bottom, isSelecting ? 96 : 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toast)
        .animation(.easeOut(duration: 0.2), value: isSelecting)
        .preferredColorScheme(.system)
        .onAppear { appState.endSessionIfStale() }
        .fullScreenCover(item: $viewerStart) { request in
            SessionViewerView(startItemID: request.startItemID)
                .environmentObject(appState)
        }
        .fullScreenCover(item: $burstReview) { item in
            BurstReviewView(burstID: item.id)
                .environmentObject(appState)
        }
    }

    private var subtitle: String {
        let count = shots.count
        return "\(count) photo\(count == 1 ? "" : "s") · Saved to Photos"
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .accessibilityAddTraits(.isHeader)
            HStack {
                if !isSelecting {
                    Button { dismiss() } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 19))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to Camera")
                }
                Spacer()
                if !items.isEmpty {
                    Button(isSelecting ? "Cancel" : "Select") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isSelecting.toggle()
                            selectedIDs = []
                        }
                    }
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    private var title: String {
        guard isSelecting else { return "Session" }
        return selectedIDs.isEmpty ? "Select Photos" : "\(selectedIDs.count) Selected"
    }

    // MARK: Grid

    private func tile(_ item: GalleryItem) -> some View {
        let selected = selectedIDs.contains(item.id)
        return Color(.systemGray6)
            .aspectRatio(193.0 / 258.0, contentMode: .fit)
            .overlay {
                Image(uiImage: item.cover.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .bottomLeading) {
                if item.isBurst {
                    Label("Burst \(item.shots.count)", systemImage: "square.on.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSelecting {
                    SelectionMark(isSelected: selected)
                        .padding(10)
                }
            }
            .onTapGesture {
                if isSelecting {
                    if selected { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
                    UISelectionFeedbackGenerator().selectionChanged()
                } else if item.isBurst {
                    burstReview = item
                } else {
                    viewerStart = ViewerRequest(startItemID: item.id)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.isBurst ? "Burst, \(item.shots.count) photos" : "Photo")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No photos yet")
                .font(.system(size: 20, weight: .bold))
            Text("Photos you take are saved to Apple Photos\nand appear here for this session.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    // MARK: Selection bar

    private var selectedShots: [CapturedPhoto] {
        items.filter { selectedIDs.contains($0.id) }.map(\.cover)
    }

    private var selectionBar: some View {
        let enabled = !selectedIDs.isEmpty && !isAdding
        return HStack(spacing: 16) {
            Button {
                addSelectionToReferences()
            } label: {
                Text("Add to References")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? Color(.systemBackground) : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Capsule().fill(enabled ? Color.primary : Color(.systemGray5)))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)

            ShareLink(
                items: selectedShots.map { ShareableShot(shot: $0, appState: appState) },
                preview: { _ in SharePreview("FrameShift Photo") }
            ) {
                Text("Share")
                    .font(.system(size: 17))
                    .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    .frame(height: 48)
            }
            .disabled(!enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemGray6).ignoresSafeArea(edges: .bottom))
    }

    private func addSelectionToReferences() {
        let ids = selectedShots.map(\.id)
        guard !ids.isEmpty else { return }
        isAdding = true
        Task {
            let added = await appState.addCapturedShotsAsReferences(ids: ids)
            isAdding = false
            withAnimation(.easeOut(duration: 0.2)) {
                isSelecting = false
                selectedIDs = []
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show(toast: "\(added) added to Yours")
        }
    }

    private func show(toast message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

// MARK: - Shared pieces

/// Photos-style selection circle: white ring, or filled blue check.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(Color.white).frame(width: 22, height: 22)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(.systemBlue))
            } else {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// Short dark confirmation capsule ("2 added to Yours").
struct ConfirmationToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .background(Capsule().fill(Color(hex: "#1C1C1E")))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Shares a capture's full-resolution JPEG from disk (falls back to the
/// display image), loaded only when the share sheet asks for it.
struct ShareableShot: Transferable {
    let fallback: UIImage
    let load: @Sendable () async -> UIImage?

    @MainActor
    init(shot: CapturedPhoto, appState: AppState) {
        let id = shot.id
        fallback = shot.image
        load = { await appState.loadFullShot(id: id) }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { item in
            let image = await item.load() ?? item.fallback
            return image.jpegData(compressionQuality: 0.95) ?? Data()
        }
        .suggestedFileName("FrameShift.jpg")
    }
}

extension ColorScheme {
    /// The device's appearance, ignoring the camera's dark override on the
    /// window — for light/dark surfaces presented from the camera.
    static var system: ColorScheme {
        UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}
