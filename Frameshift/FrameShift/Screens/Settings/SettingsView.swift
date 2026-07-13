import SwiftUI
import AVFoundation
import Photos

/// Settings, reachable only from the References tab's toolbar — the camera
/// screen itself stays free of any settings chrome (CLAUDE.md hard constraint).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Camera guide defaults (F2) — CameraViewModel reads these at init;
    // the in-drawer toggle itself never writes back to these keys.
    @AppStorage(CameraViewModel.DefaultsKey.gridVisible.rawValue) private var defaultGridVisible = true
    @AppStorage(CameraViewModel.DefaultsKey.levelVisible.rawValue) private var defaultLevelVisible = true
    @AppStorage(CameraViewModel.DefaultsKey.headCircleVisible.rawValue) private var defaultHeadCircleVisible = true
    @AppStorage(CameraViewModel.DefaultsKey.tipsEnabled.rawValue) private var defaultTipsEnabled = true

    @AppStorage("frameshift.hasSeenReferenceHint") private var hasSeenReferenceHint = false

    @State private var referenceBytes: Int64 = 0
    @State private var capturedBytes: Int64 = 0
    @State private var confirmClearReferences = false
    @State private var confirmClearCaptured = false
    @State private var cameraStatusText = "Checking…"
    @State private var photoStatusText = "Checking…"
    @State private var showOnboardingReplay = false
    @State private var showPrivacyPolicy = false

    var body: some View {
        NavigationStack {
            List {
                cameraGuidesSection
                storageSection
                permissionsSection
                onboardingSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadStorageSizes() }
        .onAppear { refreshPermissionStatuses() }
        .fullScreenCover(isPresented: $showOnboardingReplay) {
            OnboardingView(isReplay: true)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }

    // MARK: F2 — Camera guide defaults

    private var cameraGuidesSection: some View {
        Section {
            Toggle("Level", isOn: $defaultLevelVisible)
            Toggle("Grid", isOn: $defaultGridVisible)
            Toggle("Head Circle", isOn: $defaultHeadCircleVisible)
            Toggle("Composition Tips", isOn: $defaultTipsEnabled)
        } header: {
            Text("Camera Guides")
        } footer: {
            Text("Sets what a new camera session starts with. The in-camera drawer still lets you toggle these for the current session only.")
        }
    }

    // MARK: F3 — Storage

    private var storageSection: some View {
        Section {
            LabeledContent("References", value: formatted(referenceBytes))
            LabeledContent("Captured Shots", value: formatted(capturedBytes))

            Button("Clear All References", role: .destructive) {
                confirmClearReferences = true
            }
            .confirmationDialog(
                "Remove all imported references from FrameShift? This can't be undone.",
                isPresented: $confirmClearReferences,
                titleVisibility: .visible
            ) {
                Button("Clear All References", role: .destructive) {
                    appState.clearAllReferences()
                    Task { await loadStorageSizes() }
                }
                Button("Cancel", role: .cancel) {}
            }

            Button("Clear All Captured Shots", role: .destructive) {
                confirmClearCaptured = true
            }
            .confirmationDialog(
                "Remove all captured shots from FrameShift? Photos already saved to your camera roll are not affected.",
                isPresented: $confirmClearCaptured,
                titleVisibility: .visible
            ) {
                Button("Clear All Captured Shots", role: .destructive) {
                    appState.clearAllCapturedShots()
                    Task { await loadStorageSizes() }
                }
                Button("Cancel", role: .cancel) {}
            }
        } header: {
            Text("Storage")
        }
    }

    private func loadStorageSizes() async {
        let sizes = await Task.detached(priority: .utility) {
            (ReferenceStore().totalSizeBytes(), CapturedStore().totalSizeBytes())
        }.value
        referenceBytes = sizes.0
        capturedBytes = sizes.1
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: F4 — Permissions

    private var permissionsSection: some View {
        Section {
            LabeledContent("Camera", value: cameraStatusText)
            LabeledContent("Photos", value: photoStatusText)
            Button("Open System Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } header: {
            Text("Permissions")
        }
    }

    private func refreshPermissionStatuses() {
        cameraStatusText = Self.text(for: AVCaptureDevice.authorizationStatus(for: .video))
        photoStatusText = Self.text(for: PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    private static func text(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:     return "Authorized"
        case .denied:         return "Denied"
        case .restricted:     return "Restricted"
        case .notDetermined:  return "Not Determined"
        @unknown default:     return "Unknown"
        }
    }

    private static func text(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized:     return "Authorized"
        case .limited:        return "Limited"
        case .denied:         return "Denied"
        case .restricted:     return "Restricted"
        case .notDetermined:  return "Not Determined"
        @unknown default:     return "Unknown"
        }
    }

    // MARK: F5 — Onboarding & hints

    private var onboardingSection: some View {
        Section {
            Button("Replay Onboarding") {
                showOnboardingReplay = true
            }
            Button("Show Reference Hint Again") {
                hasSeenReferenceHint = false
            }
        } header: {
            Text("Onboarding")
        }
    }

    // MARK: F6 — About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersionString)
            Text("FrameShift processes everything on-device. Nothing is uploaded or collected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Privacy Policy") { showPrivacyPolicy = true }
        } header: {
            Text("About")
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
