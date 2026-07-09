import SwiftUI

/// Quick how-to, opened from the References top bar's ⓘ button. A skimmable
/// cheat sheet — the full paged walkthrough stays available via the replay
/// button at the bottom (same flow Settings offers).
struct HowToSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showWalkthrough = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    step(
                        icon: "photo.badge.plus",
                        title: "Add references",
                        text: "Import photos you want to recreate — saved Pinterest or Instagram shots work great. FrameShift analyzes each one's framing, tilt, and lens on-device."
                    )
                    step(
                        icon: "camera.viewfinder",
                        title: "Match the shot",
                        text: "Tap a reference to make it active, then line up the head circle, level the tilt bars until they turn yellow, and follow the zoom and coaching tips."
                    )
                    step(
                        icon: "circle.inset.filled",
                        title: "Capture",
                        text: "Tap the shutter, or hold it for burst. Photos save to FrameShift and your camera roll."
                    )
                    step(
                        icon: "photo.on.rectangle.angled",
                        title: "Review and share",
                        text: "Open the bottom-left thumbnail to browse shots: favorite with the heart, apply Disposable / Film / Digital looks with the wand, and export a before-and-after card with the sliders."
                    )
                }

                Section {
                    Button {
                        showWalkthrough = true
                    } label: {
                        Label("Replay the full walkthrough", systemImage: "play.circle")
                    }
                }
            }
            .navigationTitle("How to Use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showWalkthrough) {
            OnboardingView(isReplay: true)
        }
    }

    private func step(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.cameraYellow)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
