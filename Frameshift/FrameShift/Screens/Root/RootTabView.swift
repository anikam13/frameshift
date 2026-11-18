import SwiftUI

/// App shell. `CameraView` hosts both surfaces: the gallery home
/// (`selectedTab == .references`) layered over an always-mounted camera.
/// Launch routing (D-2) sets `selectedTab` in `AppState.restoreReferences`.
struct RootTabView: View {
    var body: some View {
        CameraView()
    }
}
