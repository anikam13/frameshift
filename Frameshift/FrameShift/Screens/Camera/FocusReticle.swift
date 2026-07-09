import SwiftUI

/// Native-style tap-to-focus indicator: a yellow square that pops in slightly
/// oversized and settles, with the exposure sun slider alongside. The sun
/// rides up and down the track as the user drags to bias exposure.
/// Removal (fade-out) is driven by CameraViewModel.
struct FocusReticle: View {
    /// EV compensation, -2...2; positions the sun along the track.
    var bias: CGFloat = 0
    /// Slider flips to the leading side when the tap lands near the right edge.
    var sliderOnRight = true

    @State private var settled = false

    private var sunOffset: CGFloat { -(bias / 2) * 44 }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.cameraYellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .overlay(alignment: sliderOnRight ? .trailing : .leading) {
                exposureSlider
                    .offset(x: sliderOnRight ? 30 : -30)
            }
            .scaleEffect(settled ? 1.0 : 1.35)
            .animation(.easeOut(duration: 0.18), value: settled)
            .onAppear { settled = true }
            .allowsHitTesting(false)
    }

    private var exposureSlider: some View {
        ZStack {
            Capsule()
                .fill(Color.cameraYellow.opacity(0.55))
                .frame(width: 1.5, height: 110)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.cameraYellow)
                .shadow(color: .black.opacity(0.4), radius: 1)
                .offset(y: sunOffset)
        }
    }
}
