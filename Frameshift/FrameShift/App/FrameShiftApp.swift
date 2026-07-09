import SwiftUI

@main
struct FrameShiftApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("frameshift.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(appState)
            .preferredColorScheme(.dark)
            .task { await appState.restoreReferences() }
            .task { await appState.restoreCapturedShots() }
        }
    }
}
