import SwiftUI

/// Guides mode's single fixed target: where the reference's head sits and
/// how large it appears, mapped aspect-fit to match the reference overlay.
/// Thin white ring at rest; turns yellow once alignment is confirmed. No
/// second ring for the detected head (approved spec).
struct SubjectPlacementGuide: View {
    let spec: ShotSpec
    var isAligned: Bool = false

    var body: some View {
        GeometryReader { geo in
            let head = spec.headCircle(in: geo.size)
            Circle()
                .strokeBorder(isAligned ? Color.cameraYellow : Color.guideIdle, lineWidth: 1.5)
                .frame(width: head.radius * 2, height: head.radius * 2)
                .position(head.center)
                .animation(.easeOut(duration: 0.25), value: isAligned)
        }
        // Spans the viewfinder; must not swallow tap-to-focus / pinch.
        .allowsHitTesting(false)
    }
}
