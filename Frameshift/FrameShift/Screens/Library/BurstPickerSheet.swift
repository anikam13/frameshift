import SwiftUI

/// Flip through every shot of a burst and pick the best one. The pick commits
/// immediately (it becomes the burst's cover in the gallery); "Keep Only This
/// Photo" deletes the rest of the burst after confirmation.
struct BurstPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let burstID: UUID
    /// Called with the surviving shot's id after "Keep Only This Photo"
    /// collapses the burst, so the gallery can retarget its selection.
    var onKeepOnly: (UUID) -> Void

    @State private var confirmKeepOnly = false

    /// Chronological (oldest first) — flipping through a burst should read in
    /// the order it was shot, not the gallery's newest-first order.
    private var shots: [CapturedPhoto] {
        appState.capturedShots.filter { $0.burstID == burstID }.reversed()
    }

    private var best: CapturedPhoto? {
        shots.first { $0.isBurstBest } ?? shots.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if let best {
                Image(uiImage: best.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)
            } else {
                Spacer()
            }

            thumbStrip
                .padding(.bottom, 16)

            Button(role: .destructive) {
                confirmKeepOnly = true
            } label: {
                Text("Keep Only This Photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(white: 0.14), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .confirmationDialog("", isPresented: $confirmKeepOnly, titleVisibility: .hidden) {
            Button("Keep Only This Photo", role: .destructive) { keepOnlyBest() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The other \(max(shots.count - 1, 0)) photos in this burst will be deleted.")
        }
    }

    private var header: some View {
        HStack {
            Text("Pick the best shot")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.cameraYellow)
            }
        }
        .overlay {
            Text("\(shots.count) photos")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var thumbStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shots) { shot in
                        thumb(shot)
                            .id(shot.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 64)
            .onAppear {
                if let best { proxy.scrollTo(best.id, anchor: .center) }
            }
        }
    }

    private func thumb(_ shot: CapturedPhoto) -> some View {
        let isPicked = shot.id == best?.id
        return Image(uiImage: shot.image)
            .resizable()
            .scaledToFill()
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.cameraYellow, lineWidth: isPicked ? 2 : 0)
            )
            .overlay(alignment: .bottomTrailing) {
                if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.cameraYellow)
                        .background(Circle().fill(.black).padding(1))
                        .padding(3)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isPicked)
            .onTapGesture {
                UISelectionFeedbackGenerator().selectionChanged()
                appState.setBurstBest(id: shot.id)
            }
    }

    private func keepOnlyBest() {
        guard let best else { return }
        appState.keepOnlyBurstShot(id: best.id)
        onKeepOnly(best.id)
        dismiss()
    }
}
