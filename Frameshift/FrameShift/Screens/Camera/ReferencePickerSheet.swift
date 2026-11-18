import SwiftUI

/// Camera reference picker (Paper: "09 · Reference picker — Compact" and
/// "10 · Expanded picker"). Opens compact over the live camera with
/// favorites & recent; expands to the whole Explore / Yours collection.
/// Choosing a reference switches it in place — the shooting session and its
/// capture count carry on.
struct ReferencePickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Binding var detent: PresentationDetent

    static let compactDetent = PresentationDetent.height(374)

    enum Collection: String, CaseIterable { case explore = "Explore", yours = "Yours" }
    @State private var collection: Collection = .explore
    @State private var filter: CompositionFilter = .all

    private var isExpanded: Bool { detent == .large }

    var body: some View {
        // Text scales with Dynamic Type up to the largest standard size;
        // fixed-height controls would clip at accessibility sizes (D-32).
        screen.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isExpanded)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("References")
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
            HStack(spacing: 8) {
                Button {
                    withAnimation { detent = isExpanded ? Self.compactDetent : .large }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(.body, weight: .regular))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isExpanded ? "Collapse" : "Show all references")

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(.body, weight: .regular))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .foregroundStyle(.primary)
        }
        .frame(height: isExpanded ? 56 : 48)
        .padding(.horizontal, 16)
    }

    // MARK: Compact

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites & recent")
                .font(.system(.footnote))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            if appState.quickAccessReferences.isEmpty {
                Text("References you use or favorite appear here.")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                Button("Browse all references") {
                    withAnimation { detent = .large }
                }
                .font(.system(.subheadline, weight: .semibold))
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(appState.quickAccessReferences) { ref in
                            quickTile(ref, width: 104, height: 142, radius: 10)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.quickAccessReferences.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(appState.quickAccessReferences) { ref in
                            quickTile(ref, width: 62, height: 76, radius: 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }

            Picker("Collection", selection: $collection) {
                ForEach(Collection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if collection == .explore {
                chips
            }

            ScrollView {
                let items = visibleReferences
                if items.isEmpty {
                    Text(collection == .yours
                         ? "Photos you import appear here."
                         : "No references in this category yet.")
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(items) { ref in gridTile(ref) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, collection == .explore ? 0 : 14)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableFilters, id: \.self) { option in
                    let selected = filter == option
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        filter = option
                    } label: {
                        Text(option.title)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(
                                selected ? Color.primary : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: Tiles

    private func quickTile(_ ref: ReferencePhoto, width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        let isActive = ref.id == appState.activeReference?.id
        return Button { choose(ref) } label: {
            Image(uiImage: ref.image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(Color.cameraYellow, lineWidth: isActive ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .contextMenu { favoriteAction(ref) }
        .accessibilityLabel(isActive ? "Current reference" : "Reference")
    }

    private func gridTile(_ ref: ReferencePhoto) -> some View {
        Button { choose(ref) } label: {
            Color.clear
                .aspectRatio(173.0 / 228.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: ref.image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    // Bookmark marks favorited curated photos only.
                    if ref.isFavorite && ref.isCurated {
                        Image(systemName: "bookmark.fill")
                            .font(.system(.subheadline))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .padding(10)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu { favoriteAction(ref) }
    }

    @ViewBuilder
    private func favoriteAction(_ ref: ReferencePhoto) -> some View {
        Button {
            appState.setReferenceFavorite(id: ref.id, isFavorite: !ref.isFavorite)
        } label: {
            Label(ref.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: ref.isFavorite ? "bookmark.slash" : "bookmark")
        }
    }

    private func choose(_ ref: ReferencePhoto) {
        UISelectionFeedbackGenerator().selectionChanged()
        appState.useReference(id: ref.id)
        dismiss()
    }

    // MARK: Filtering

    private var visibleReferences: [ReferencePhoto] {
        switch collection {
        case .yours:   return appState.importedReferences
        case .explore: return appState.curatedReferences.filter(filter.matches)
        }
    }

    /// Only categories the analyzer can actually classify. Seated / Couples /
    /// Groups need curated tags (gallery phase) and stay hidden until then.
    private var availableFilters: [CompositionFilter] {
        CompositionFilter.allCases.filter { option in
            option == .all || appState.curatedReferences.contains(where: option.matches)
        }
    }
}

/// Explore composition chips. Curated photos use their hand tags
/// (`SampleReferencePack.tags`); imports fall back to `ShotSpec.framing`.
enum CompositionFilter: CaseIterable, Hashable {
    case all, fullBody, portraits, seated, couples, groups

    var title: String {
        switch self {
        case .all:       return "All"
        case .fullBody:  return "Full Body"
        case .portraits: return "Portraits"
        case .seated:    return "Seated"
        case .couples:   return "Couples"
        case .groups:    return "Groups"
        }
    }

    func matches(_ ref: ReferencePhoto) -> Bool {
        if self != .all, let name = ref.bundledAssetName, let tags = SampleReferencePack.tags[name] {
            return tags.contains(self)
        }
        switch self {
        case .all:       return true
        case .fullBody:  return ref.spec?.framing == .wide
        case .portraits: return ref.spec.map { $0.framing != .wide } ?? false
        case .seated, .couples, .groups: return false
        }
    }
}
