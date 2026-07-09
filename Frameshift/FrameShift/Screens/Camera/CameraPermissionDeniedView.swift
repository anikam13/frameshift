import SwiftUI

/// Shown in place of the viewfinder when camera access is denied/restricted,
/// either from a prior denial (on launch) or immediately after the user
/// denies the first-run prompt.
struct CameraPermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.slash")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.white.opacity(0.7))

            Text("FrameShift needs camera access")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)

            Text("Turn on Camera access in Settings to take photos.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
