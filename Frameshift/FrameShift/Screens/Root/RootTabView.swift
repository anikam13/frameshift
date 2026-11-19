import SwiftUI

/// App shell. `CameraView` hosts both surfaces: the gallery home
/// (`selectedTab == .references`) layered over an always-mounted camera.
/// Launch always lands on the gallery (D-2); first launch shows the
/// welcome on top while the camera starts underneath (D-34).
struct RootTabView: View {
    @AppStorage(Welcome.doneKey) private var welcomeDone = false

    var body: some View {
        ZStack {
            CameraView()
            if !welcomeDone {
                WelcomeView {
                    withAnimation(.easeOut(duration: 0.25)) { welcomeDone = true }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}
