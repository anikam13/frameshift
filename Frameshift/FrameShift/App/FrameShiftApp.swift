import SwiftUI

@main
struct FrameShiftApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup {
            RootTabView()
            .environmentObject(appState)
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-uitest-seed-references") {
                    appState.seedReferencesForUITests()
                    return
                }
                #endif
                await appState.restoreReferences()
            }
            .task {
                await appState.restoreCapturedShots()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-preview-seed-session") {
                    while !appState.hasFinishedRestoringReferences {
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                    appState.seedSessionForPreview()
                }
                #endif
            }
            .task { await appState.restoreFilterPresets() }
        }
    }
}
