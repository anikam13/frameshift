import SwiftUI
import PhotosUI

/// Camera-look filters for a captured shot, opened from the gallery's wand
/// button. Previews render from the display-sized bitmap; saving re-applies
/// the look to the full-resolution JPEG from disk and adds the result as a
/// new shot (the original is never modified). When the shot's reference is
/// still around, a "Match" look color-grades the shot toward the reference.
/// The trailing + thumb creates a custom preset from any picked photo;
/// long-press a custom preset to delete it.
struct FilterPresetSheet: View {
    let shot: CapturedPhoto
    /// Called with the new shot's id after a filtered copy is saved.
    var onSaved: (UUID) -> Void = { _ in }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// A selectable look: the reference-derived color match, the fixed camera
    /// presets, and the user's saved custom presets.
    /// nonisolated: used as a Hashable dictionary key inside detached
    /// preview-render tasks, so its conformance can't be MainActor-bound.
    nonisolated enum Look: Hashable {
        case matchReference
        case preset(FilterPreset)
        case custom(UUID)
    }

    @State private var selected: Look?
    @State private var previews: [Look: UIImage] = [:]
    @State private var isSaving = false
    @State private var newPresetItem: PhotosPickerItem?
    /// How much the selected look affects the photo (0 = original, 1 = full).
    @State private var strength: Double = 1

    private var referenceImage: UIImage? {
        appState.reference(for: shot.referenceID)?.image
    }

    private var looks: [Look] {
        (referenceImage != nil ? [.matchReference] : [])
            + FilterPreset.allCases.map(Look.preset)
            + appState.filterPresets.map { Look.custom($0.id) }
    }

    private func label(for look: Look) -> String {
        switch look {
        case .matchReference: "Match"
        case .preset(let preset): preset.rawValue
        case .custom(let id): appState.filterPresets.first { $0.id == id }?.name ?? "Preset"
        }
    }

    /// The image whose color stats a match-style look grades toward;
    /// nil for the fixed presets.
    private func matchTarget(for look: Look) -> UIImage? {
        switch look {
        case .matchReference: referenceImage
        case .custom(let id): appState.filterPresets.first { $0.id == id }?.image
        case .preset: nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                previewImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                strengthSlider

                presetRow

                saveButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .background(Color.black)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await generatePreviews() }
    }

    // MARK: Preview

    /// The full-strength render crossfades over the original by opacity —
    /// the same linear blend `FilterService` applies at save time, so the
    /// preview predicts the saved result exactly.
    private var previewImage: some View {
        ZStack {
            Image(uiImage: shot.image)
                .resizable()
                .scaledToFit()
            if let selected, let preview = previews[selected] {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .opacity(strength)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Strength

    private var strengthSlider: some View {
        HStack(spacing: 12) {
            Slider(value: $strength, in: 0...1)
                .tint(.cameraYellow)
            Text("\(Int(strength * 100))%")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, alignment: .trailing)
        }
        .opacity(selected == nil ? 0 : 1)
        .disabled(selected == nil)
        .animation(.easeInOut(duration: 0.15), value: selected == nil)
    }

    // MARK: Preset row

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                presetThumb(label: "Original", image: shot.image, isSelected: selected == nil) {
                    selected = nil
                }
                ForEach(looks, id: \.self) { look in
                    if case .custom(let id) = look {
                        presetThumb(
                            label: label(for: look),
                            image: previews[look],
                            isSelected: selected == look
                        ) {
                            selected = look
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deletePreset(id: id)
                            } label: {
                                Label("Delete Preset", systemImage: "trash")
                            }
                        }
                    } else {
                        presetThumb(
                            label: label(for: look),
                            image: previews[look],
                            isSelected: selected == look
                        ) {
                            selected = look
                        }
                    }
                }

                addPresetThumb
            }
        }
    }

    /// Picks a look-source photo and saves it as a new custom preset.
    private var addPresetThumb: some View {
        PhotosPicker(selection: $newPresetItem, matching: .images) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color.white.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5])
                    )
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                Text("New")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .onChange(of: newPresetItem) { _, item in
            guard let item else { return }
            newPresetItem = nil
            Task { await addPreset(from: item) }
        }
    }

    private func presetThumb(
        label: String, image: UIImage?, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                            .overlay { ProgressView().tint(.white) }
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.cameraYellow, lineWidth: isSelected ? 2 : 0)
                )

                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.cameraYellow : .white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private var saveButton: some View {
        Button {
            saveFiltered()
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text("Save as New Photo")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                selected == nil ? Color.white.opacity(0.25) : Color.white,
                in: Capsule()
            )
            .foregroundStyle(.black)
        }
        .disabled(selected == nil || isSaving)
    }

    private func saveFiltered() {
        guard let look = selected, !isSaving else { return }
        isSaving = true
        let shotID = shot.id
        let referenceID = shot.referenceID
        let displayFallback = shot.image
        let target = matchTarget(for: look)
        let renderStrength = Float(strength)
        Task {
            // Full-res from disk when available; the display bitmap otherwise.
            let source = await appState.loadFullShot(id: shotID) ?? displayFallback
            let filtered = await Task.detached(priority: .userInitiated) {
                Self.render(look, on: source, matchTarget: target, strength: renderStrength)
            }.value
            guard let filtered else {
                isSaving = false
                appState.showTransientNotice("Couldn't apply that filter")
                return
            }
            let newID = await appState.addCapturedShotAsync(filtered, referenceID: referenceID)
            isSaving = false
            dismiss()
            onSaved(newID)
        }
    }

    // MARK: Preview generation

    private func generatePreviews() async {
        let source = shot.image
        let jobs = looks.map { ($0, matchTarget(for: $0)) }
        // Utility + progressive: opening the sheet must not spike CPU against
        // the still-mounted camera session underneath the cover.
        for (look, target) in jobs {
            let rendered = await Task.detached(priority: .utility) {
                Self.render(look, on: source, matchTarget: target)
            }.value
            if let rendered, previews[look] == nil {
                previews[look] = rendered
            }
        }
    }

    // MARK: Custom presets

    private func addPreset(from item: PhotosPickerItem) async {
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage.downsampled(data: data, maxPixelSize: UIImage.overlayMaxPixelSize)
        else {
            appState.showTransientNotice("Couldn't load that photo")
            return
        }
        let preset = appState.addFilterPreset(from: image)
        let look = Look.custom(preset.id)
        selected = look

        let source = shot.image
        let target = preset.image
        previews[look] = await Task.detached(priority: .userInitiated) {
            FilterService.matchColors(of: source, toReference: target)
        }.value
    }

    private func deletePreset(id: UUID) {
        let look = Look.custom(id)
        if selected == look { selected = nil }
        previews[look] = nil
        appState.removeFilterPreset(id: id)
    }

    // MARK: Rendering

    /// `strength` scales the look linearly; previews render at full strength
    /// and crossfade by opacity instead, which is the same blend.
    private nonisolated static func render(
        _ look: Look, on source: UIImage, matchTarget: UIImage?, strength: Float = 1
    ) -> UIImage? {
        switch look {
        case .matchReference, .custom:
            guard let matchTarget else { return nil }
            // Match tops out at its 0.75 internal strength; the slider scales
            // within that.
            return FilterService.matchColors(
                of: source, toReference: matchTarget, strength: 0.75 * strength
            )
        case .preset(let preset):
            return FilterService.apply(preset, to: source, strength: strength)
        }
    }
}
