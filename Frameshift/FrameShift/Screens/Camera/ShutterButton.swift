import SwiftUI

/// Native iOS Camera shutter button geometry.
/// Outer ring: 74pt diameter, translucent gray stroke like the current
/// Camera app (reads as a soft halo on black, not a hard white line).
/// Inner fill: 62pt diameter, solid white.
///
/// A quick tap fires a single capture. Holding past a short threshold starts
/// a burst — continuous captures until the finger lifts — matching the
/// native Camera app's press-and-hold behavior.
struct ShutterButton: View {
    var isBursting: Bool = false
    /// Shots landed so far in the current burst, shown inside the button.
    var burstCount: Int = 0
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    @State private var isPressed = false
    @State private var isHolding = false
    @State private var holdTask: Task<Void, Never>?

    private let holdThreshold = 0.35

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(isBursting ? Color.cameraYellow : Color.white.opacity(0.3), lineWidth: 4)
                .frame(width: 74, height: 74)

            // Inner fill
            Circle()
                .fill(Color.white)
                .frame(width: 62, height: 62)
                .scaleEffect(isPressed ? 0.88 : 1.0)
                .animation(.spring(response: 0.12, dampingFraction: 0.7), value: isPressed)

            if isBursting && burstCount > 0 {
                Text("\(burstCount)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.12), value: burstCount)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isBursting)
        .contentShape(Circle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Shutter")
        .accessibilityAction { onTap() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    isHolding = false
                    holdTask = Task {
                        try? await Task.sleep(for: .seconds(holdThreshold))
                        guard !Task.isCancelled else { return }
                        isHolding = true
                        onHoldStart()
                    }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    isPressed = false
                    if isHolding {
                        isHolding = false
                        onHoldEnd()
                    } else {
                        onTap()
                    }
                }
        )
    }
}
