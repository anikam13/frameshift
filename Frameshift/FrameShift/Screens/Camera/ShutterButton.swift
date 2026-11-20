import SwiftUI

/// Shutter geometry from the redesign (Paper "Capture controls"):
/// outer ring 78pt / 3pt white stroke; inner fill 66pt solid white.
///
/// A quick tap fires a single capture. Holding past a short threshold starts
/// a burst — continuous captures until the finger lifts — matching the
/// native Camera app's press-and-hold behavior.
struct ShutterButton: View {
    var isBursting: Bool = false
    /// Shots landed so far in the current burst, shown inside the button.
    var burstCount: Int = 0
    var onPressDown: () -> Void = {}
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
                .strokeBorder(isBursting ? Color.cameraYellow : Color.white, lineWidth: 3)
                .frame(width: 78, height: 78)

            // Inner fill
            Circle()
                .fill(Color.white)
                .frame(width: 66, height: 66)
                .scaleEffect(isPressed ? 0.88 : 1.0)
                .animation(.easeOut(duration: 0.08), value: isPressed)

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
                    onPressDown()
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
