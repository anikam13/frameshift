import SwiftUI
import AVFoundation
import Photos

/// Settings (Paper page "06 · Menus and settings"), opened from the gallery
/// header's `⋯` only — never from the camera (D-3). Permissions, help and
/// app info; storage lives one level down.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var cameraStatusText = "—"
    @State private var photoStatusText = "—"

    var body: some View {
        NavigationStack {
            List {
                Section("Permissions") {
                    LabeledContent("Camera", value: cameraStatusText)
                    LabeledContent("Save to Photos", value: photoStatusText)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        ChevronRow(title: "Open System Settings")
                    }
                }

                Section("Help") {
                    Button {
                        replayTutorial()
                    } label: {
                        ChevronRow(title: "Replay Tutorial")
                    }
                    NavigationLink("How to Use") {
                        HowToUseView(onReplayTutorial: replayTutorial)
                    }
                }

                Section("App") {
                    NavigationLink("Storage") { StorageView() }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("About FrameShift") { AboutView() }
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(.primary)
                }
            }
        }
        .onAppear { refreshPermissionStatuses() }
    }

    private func replayTutorial() {
        FirstUseTour.reset()
        appState.selectedTab = .references
        dismiss()
    }

    private func refreshPermissionStatuses() {
        cameraStatusText = Self.text(for: AVCaptureDevice.authorizationStatus(for: .video))
        photoStatusText = Self.text(for: PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }

    private static func text(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized:            return "Allowed"
        case .denied, .restricted:   return "Off"
        case .notDetermined:         return "Not Asked"
        @unknown default:            return "—"
        }
    }

    private static func text(for status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized, .limited:  return "Allowed"
        case .denied, .restricted:   return "Off"
        case .notDetermined:         return "Not Asked"
        @unknown default:            return "—"
        }
    }
}

/// A plain row with a trailing chevron, for button rows that should read like
/// navigation rows.
private struct ChevronRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Storage

/// App-held copies only: imported references and captured copies. Photos in
/// Apple Photos are never touched; curated Explore photos stay.
struct StorageView: View {
    @EnvironmentObject var appState: AppState

    @State private var referenceBytes: Int64 = 0
    @State private var capturedBytes: Int64 = 0
    @State private var confirmClearReferences = false
    @State private var confirmClearCaptures = false

    var body: some View {
        List {
            Section {
                LabeledContent("References", value: formatted(referenceBytes))
                LabeledContent("Captured Copies", value: formatted(capturedBytes))
            } header: {
                Text("Stored by FrameShift")
            } footer: {
                Text("These copies are stored inside FrameShift, separate from Photos.")
            }

            Section {
                Button("Clear Imported References", role: .destructive) {
                    confirmClearReferences = true
                }
                .disabled(appState.importedReferences.isEmpty)
                Button("Clear Captured Copies", role: .destructive) {
                    confirmClearCaptures = true
                }
                .disabled(appState.capturedShots.isEmpty)
            } footer: {
                Text("Photos already saved in Photos stay there. Curated Explore photos remain available.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSizes() }
        .alert("Clear imported references?", isPresented: $confirmClearReferences) {
            Button("Cancel", role: .cancel) {}
            Button("Clear References", role: .destructive) {
                appState.clearImportedReferences()
                Task { await loadSizes() }
            }
        } message: {
            Text("This removes imported references from FrameShift. Originals stay in Photos.")
        }
        .alert("Clear captured copies?", isPresented: $confirmClearCaptures) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Copies", role: .destructive) {
                appState.clearAllCapturedShots()
                Task { await loadSizes() }
            }
        } message: {
            Text("This empties session review in FrameShift. Photos saved in Photos stay there.")
        }
    }

    private func loadSizes() async {
        let sizes = await Task.detached(priority: .utility) {
            (ReferenceStore().totalSizeBytes(), CapturedStore().totalSizeBytes())
        }.value
        referenceBytes = sizes.0
        capturedBytes = sizes.1
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - How to Use

struct HowToUseView: View {
    var onReplayTutorial: () -> Void

    private let steps: [(String, String)] = [
        ("Choose a reference", "Browse Explore or import a photo with +. Your imports appear in Yours."),
        ("Frame the shot", "Use the person-only overlay or Guides. Follow one coaching tip at a time."),
        ("Take photos", "Tap once or hold for a burst. Successful saves go to Photos automatically."),
        ("Review and compare", "Open the session thumbnail to compare, share or add captures as references."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.0)
                                .font(.system(size: 17, weight: .semibold))
                            Text(step.1)
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        if index < steps.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                Button(action: onReplayTutorial) {
                    Text("Replay Tutorial")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.primary))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("How to Use")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FrameShift")
                .font(.system(size: 17))
            Text("Version \(appVersionString)")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Capsule()
                .fill(Color.cameraYellow)
                .frame(width: 40, height: 4)
                .padding(.top, 34)

            Text("FrameShift processes everything on-device.")
                .font(.system(size: 17))
                .padding(.top, 14)
            Text("Nothing is uploaded or collected.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                HStack {
                    Text("Privacy Policy").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Divider() }
            }
            .padding(.top, 96)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
