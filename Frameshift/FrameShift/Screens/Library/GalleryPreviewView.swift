import SwiftUI

/// Apple Camera-style photo preview, opened from the bottom-left thumbnail.
/// Back chevron + date pill up top, swipeable photo, filmstrip, and the
/// share · heart · info · export toolbar.
struct GalleryPreviewView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var selectedID: UUID
    @State private var confirmDelete = false
    @State private var showInfoSheet = false
    @State private var filterTarget: CapturedPhoto?

    private let exportService = ExportService()

    private var shots: [CapturedPhoto] { appState.capturedShots }
    private var current: CapturedPhoto? { shots.first { $0.id == selectedID } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(shots) { shot in
                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFit()
                        .tag(shot.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                Spacer()
                filmstrip
                    .padding(.bottom, 14)
                bottomBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("", isPresented: $confirmDelete, titleVisibility: .hidden) {
            Button("Delete Photo", role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showInfoSheet) {
            CaptureInfoSheet(shot: current, reference: appState.reference(for: current?.referenceID))
        }
        .fullScreenCover(item: $filterTarget) { shot in
            FilterPresetSheet(shot: shot) { newID in
                withAnimation(.easeOut(duration: 0.2)) { selectedID = newID }
            }
            .environmentObject(appState)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()
        }
        .overlay {
            datePill
        }
    }

    private var datePill: some View {
        VStack(spacing: 0) {
            Text(dayString)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(timeString)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var dayString: String {
        guard let date = current?.capturedAt else { return "" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var timeString: String {
        guard let date = current?.capturedAt else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(shots) { shot in
                        filmstripThumb(shot)
                            .id(shot.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 42)
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, id in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func filmstripThumb(_ shot: CapturedPhoto) -> some View {
        let isSelected = shot.id == selectedID
        return Image(uiImage: shot.image)
            .resizable()
            .scaledToFill()
            .frame(width: isSelected ? 40 : 26, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: isSelected ? 5 : 2))
            .overlay(
                RoundedRectangle(cornerRadius: isSelected ? 5 : 2)
                    .stroke(.white, lineWidth: isSelected ? 1.5 : 0)
            )
            // Surface favorites where you scan for them — the filmstrip.
            .overlay(alignment: .bottomTrailing) {
                if shot.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: isSelected ? 9 : 7))
                        .foregroundStyle(.red)
                        .padding(2)
                }
            }
            .padding(.horizontal, isSelected ? 4 : 0)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { selectedID = shot.id }
            }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            if let current {
                ShareLink(
                    item: Image(uiImage: current.image),
                    preview: SharePreview("FrameShift Photo", image: Image(uiImage: current.image))
                ) {
                    circleIcon("square.and.arrow.up")
                }
            }

            Spacer()

            HStack(spacing: 32) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isFavorite ? .red : .white)
                }
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                Button {
                    filterTarget = current
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                if let reference = appState.reference(for: current?.referenceID) {
                    Button {
                        exportCard(reference: reference)
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 30)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button { confirmDelete = true } label: {
                circleIcon("trash")
            }
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var isFavorite: Bool { current?.isFavorite ?? false }

    private func toggleFavorite() {
        guard let current else { return }
        appState.setFavorite(id: current.id, isFavorite: !current.isFavorite)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func exportCard(reference: ReferencePhoto) {
        guard
            let current,
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = windowScene.windows.first?.rootViewController
        else { return }
        let shotID = current.id
        let referenceID = reference.id
        Task {
            // Prefer full-res from disk; fall back to in-memory display images.
            let images = await appState.loadExportImages(shotID: shotID, referenceID: referenceID)
            let referenceImage = images?.reference ?? reference.image
            let shotImage = images?.shot ?? current.image
            guard let card = exportService.generateCard(
                reference: referenceImage, shot: shotImage, format: .story
            ) else { return }
            exportService.saveAndShare(image: card, from: root, appState: appState)
        }
    }

    private func deleteCurrent() {
        guard let index = shots.firstIndex(where: { $0.id == selectedID }) else { return }
        let deletedID = selectedID
        if shots.count > 1 {
            let nextIndex = index == shots.count - 1 ? index - 1 : index + 1
            selectedID = shots[nextIndex].id
            appState.removeCapturedShot(id: deletedID)
        } else {
            appState.removeCapturedShot(id: deletedID)
            dismiss()
        }
    }
}
