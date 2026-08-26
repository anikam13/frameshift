import SwiftUI

/// Expanded reference view, opened by tapping a grid cell: the photo,
/// aspect-fit on black, with the two actions — use it on the camera, or
/// delete it.
struct ReferenceDetailView: View {
    let photo: ReferencePhoto
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDelete = false

    /// Live copy from AppState so an in-flight analysis can enable the Use
    /// button while this view is up; the presented value is the fallback.
    private var current: ReferencePhoto {
        appState.references.first { $0.id == photo.id } ?? photo
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                actions
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Delete this reference?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.removeReference(id: photo.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            // No spec → nothing to coach against, so no Use button; the
            // grid's old behavior (no-subject cells weren't activatable)
            // carries over.
            if current.spec != nil {
                Button {
                    useReference()
                } label: {
                    Text(isActive ? "In Use — Open Camera" : "Use Reference")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.cameraYellow, in: Capsule())
                }
            }

            Button {
                confirmDelete = true
            } label: {
                Text("Delete Reference")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private var isActive: Bool { appState.activeReference?.id == photo.id }

    private func useReference() {
        appState.setActiveReference(id: photo.id)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            appState.selectedTab = .camera
        }
        dismiss()
    }
}
