import SwiftUI

/// In-app copy of the hosted privacy policy (App Review 5.1.1(i) requires
/// both an App Store Connect URL and an easily accessible in-app copy).
/// Keep this text in sync with PRIVACY.md at the workspace root.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    private let lastUpdated = "July 8, 2026"

    private let sections: [Section] = [
        Section(
            title: "Information We Collect",
            body: "FrameShift does not collect, transmit, or store any information outside of your device. There are no accounts, no sign-in, and no network requests of any kind — the app has no backend server to send data to, even if it wanted to."
        ),
        Section(
            title: "Camera Access",
            body: "FrameShift requests camera access to show the live viewfinder and to capture photos when you tap the shutter. Camera frames are analyzed on-device to draw framing guides — this analysis never leaves your device, and frames are not stored unless you deliberately capture a photo."
        ),
        Section(
            title: "Photo Library Access",
            body: "Importing reference photos is handled through Apple's system photo picker, which runs outside of FrameShift's process — FrameShift only ever receives the specific photos you choose to import, never broad library access. Saving your photos uses \"add-only\" access: FrameShift can save captured shots and export cards to your camera roll, but cannot read, browse, or modify the rest of your photo library."
        ),
        Section(
            title: "On-Device Processing",
            body: "When you import a reference photo, FrameShift analyzes it entirely on your device (detecting the subject, pose, and horizon) to build the framing guide shown on the camera screen. No image, video, or analysis result is ever uploaded anywhere."
        ),
        Section(
            title: "Data Storage",
            body: "Reference photos, captured shots, and your app settings are stored locally in FrameShift's private storage on your device. Nothing is synced to iCloud or any external server by FrameShift itself."
        ),
        Section(
            title: "Data Deletion",
            body: "You can delete individual reference photos or captured shots at any time from within the app, or use \"Clear All References\" / \"Clear All Captured Shots\" in Settings to remove everything at once. Deleting the app removes all of its data from your device."
        ),
        Section(
            title: "Third-Party Sharing",
            body: "FrameShift does not share data with any third party. FrameShift contains no third-party analytics, advertising, or tracking SDKs."
        ),
        Section(
            title: "Children's Privacy",
            body: "FrameShift does not knowingly collect personal information from anyone, including children, because it does not collect personal information from anyone."
        ),
        Section(
            title: "Contact",
            body: "Questions about this policy can be sent to anirudhkamath01@gmail.com."
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Last updated: \(lastUpdated)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("FrameShift is designed to work entirely on your device. This policy explains exactly what that means.")
                        .font(.body)

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.headline)
                            Text(section.body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
