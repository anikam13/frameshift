import SwiftUI

/// Paper "Camera denied recovery" (V1). Fills the viewfinder box when camera
/// access is denied or restricted; the rest of the camera chrome stays put
/// (dimmed) so the screen still reads as the camera.
struct CameraPermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("Camera access is off")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Text("Allow camera access in Settings\nto take photos with FrameShift.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#1C1C1E"))
    }
}

/// Paper "Camera access explanation" (V1; D-28). One short explanation right
/// before the system prompt, over the chosen reference. Continue shows the
/// system prompt; Not Now returns to the gallery.
struct CameraAccessExplanationView: View {
    let reference: UIImage?
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            // Color sizes the layer to the screen; the photo fills it without
            // widening the stack.
            Color.black
                .overlay {
                    if let reference {
                        Image(uiImage: reference)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .clipped()
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Enable your camera")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: "#1C1C1E"))
                Text("FrameShift needs camera access to help you frame and take your shot.")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: "#636366"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color(hex: "#1C1C1E")))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)

                Button(action: onNotNow) {
                    Text("Not Now")
                        .font(.system(size: 17))
                        .foregroundStyle(Color(hex: "#1C1C1E"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 8)
            .background(
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                    .fill(Color(hex: "#F2F2F7"))
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .overlay(alignment: .topLeading) {
            Button(action: onNotNow) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 10)
            .accessibilityLabel("Back")
        }
    }
}

/// Paper "Reference unavailable" (V1). The active reference couldn't be
/// analyzed; shooting still works (D-21), aids are unavailable.
struct ReferenceUnavailableCard: View {
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Couldn’t prepare reference")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            Text("You can still take photos.")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 2)
            Button("Try Again", action: onRetry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 14)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.coachPill))
    }
}
