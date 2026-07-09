import SwiftUI

/// Camera-look filters for a captured shot, opened from the gallery's wand
/// button. Previews render from the display-sized bitmap; saving re-applies
/// the look to the full-resolution JPEG from disk and adds the result as a
/// new shot (the original is never modified).
struct FilterPresetSheet: View {
    let shot: CapturedPhoto
    /// Called with the new shot's id after a filtered copy is saved.
    var onSaved: (UUID) -> Void = { _ in }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: FilterPreset?
    @State private var previews: [FilterPreset: UIImage] = [:]
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                previewImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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

    private var previewImage: some View {
        Image(uiImage: currentPreview)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var currentPreview: UIImage {
        guard let selected else { return shot.image }
        return previews[selected] ?? shot.image
    }

    // MARK: Preset row

    private var presetRow: some View {
        HStack(spacing: 14) {
            presetThumb(label: "Original", image: shot.image, isSelected: selected == nil) {
                selected = nil
            }
            ForEach(FilterPreset.allCases) { preset in
                presetThumb(
                    label: preset.rawValue,
                    image: previews[preset],
                    isSelected: selected == preset
                ) {
                    selected = preset
                }
            }
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
        guard let preset = selected, !isSaving else { return }
        isSaving = true
        let shotID = shot.id
        let referenceID = shot.referenceID
        let displayFallback = shot.image
        Task {
            // Full-res from disk when available; the display bitmap otherwise.
            let source = await appState.loadFullShot(id: shotID) ?? displayFallback
            let filtered = await Task.detached(priority: .userInitiated) {
                FilterService.apply(preset, to: source)
            }.value
            guard let filtered else {
                isSaving = false
                appState.showTransientNotice("Couldn't apply that filter")
                return
            }
            let newID = appState.addCapturedShot(filtered, referenceID: referenceID)
            isSaving = false
            dismiss()
            onSaved(newID)
        }
    }

    // MARK: Preview generation

    private func generatePreviews() async {
        let source = shot.image
        let rendered = await Task.detached(priority: .userInitiated) {
            var result: [FilterPreset: UIImage] = [:]
            for preset in FilterPreset.allCases {
                result[preset] = FilterService.apply(preset, to: source)
            }
            return result
        }.value
        previews = rendered
    }
}
