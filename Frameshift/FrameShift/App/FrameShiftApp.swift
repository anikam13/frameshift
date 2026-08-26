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
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uitest-seed-references") {
                    appState.seedReferencesForUITests()
                    return
                }
                #endif
                await appState.restoreReferences()
            }
            .task { await appState.restoreCapturedShots() }
            .task { await appState.restoreFilterPresets() }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    appState.resumeDeferredAnalysisAfterOnboarding()
                }
            }
        }
    }
}
