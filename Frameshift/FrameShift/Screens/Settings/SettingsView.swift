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
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Storage

/// App-held copies only: imported references. Captures aren't kept in the
/// app (they live in Apple Photos); curated Explore photos stay.
struct StorageView: View {
    @EnvironmentObject var appState: AppState

    @State private var referenceBytes: Int64 = 0
    @State private var confirmClearReferences = false

    var body: some View {
        List {
            Section {
                LabeledContent("References", value: formatted(referenceBytes))
            } header: {
                Text("Stored by FrameShift")
            } footer: {
                Text("Photos you take are saved to Photos only — FrameShift doesn’t keep copies.")
            }

            Section {
                Button("Clear Imported References", role: .destructive) {
                    confirmClearReferences = true
                }
                .disabled(appState.importedReferences.isEmpty)
            } footer: {
                Text("Originals stay in Photos. Curated Explore photos remain available.")
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
    }

    private func loadSizes() async {
        referenceBytes = await Task.detached(priority: .utility) {
            ReferenceStore().totalSizeBytes()
        }.value
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
                                .font(.system(.body, weight: .semibold))
                            Text(step.1)
                                .font(.system(.subheadline))
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
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .padding(.vertical, 4)
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
                .font(.system(.body))
            Text("Version \(appVersionString)")
                .font(.system(.body))
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Capsule()
                .fill(Color.cameraYellow)
                .frame(width: 40, height: 4)
                .padding(.top, 34)

            Text("FrameShift processes everything on-device.")
                .font(.system(.body))
                .padding(.top, 14)
            Text("Nothing is uploaded or collected.")
                .font(.system(.body))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                HStack {
                    Text("Privacy Policy").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.subheadline, weight: .medium))
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
