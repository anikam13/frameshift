import SwiftUI

/// Full library grid of every captured shot, opened from the gallery
/// preview's top-right grid button. Bursts appear as one tile with a count
/// badge; tapping any tile jumps the preview back to that item.
struct GalleryLibraryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// The preview pager's selection — set on tile tap, then this dismisses.
    @Binding var selectedID: UUID

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
    }

    // MARK: Header

    private var header: some View {
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
            VStack(spacing: 0) {
                Text("Library")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(countString)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var countString: String {
        let count = appState.capturedShots.count
        return count == 1 ? "1 photo" : "\(count) photos"
    }

    // MARK: Tiles

    private func tile(_ item: GalleryItem) -> some View {
        Button {
            selectedID = item.id
            dismiss()
        } label: {
            Color.clear
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
                    if item.cover.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(5)
                    }
                }
                .overlay {
                    if item.id == selectedID {
                        Rectangle().stroke(Color.cameraYellow, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
