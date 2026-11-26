import SwiftUI

@main
struct FrameShiftApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            RootTabView()
            .environmentObject(appState)
            // Lock Screen / Control Center control (OpenCameraIntent). The
            // intent can land before or after the first view, so check both.
            .task { openCameraIfRequested() }
            .onReceive(NotificationCenter.default.publisher(for: CameraLaunchRequest.notification)) { _ in
                openCameraIfRequested()
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uitest-seed-references") {
                    appState.seedReferencesForUITests()
                    return
                }
                #endif
                await appState.restoreReferences()
                await appState.syncRemoteReferences()
            }
            .task {
                await appState.restoreSessionFromPreviousLaunch()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-preview-seed-session") {
                    while !appState.hasFinishedRestoringReferences {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    appState.seedSessionForPreview()
                }
                #endif
            }
        }
    }

    /// Skipped until the welcome screen is done, so first launch stays the same.
    private func openCameraIfRequested() {
        guard CameraLaunchRequest.consume(),
              UserDefaults.standard.bool(forKey: Welcome.doneKey) else { return }
        appState.selectedTab = .camera
    }
}
