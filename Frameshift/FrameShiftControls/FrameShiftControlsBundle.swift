import SwiftUI
import WidgetKit

@main
struct FrameShiftControlsBundle: WidgetBundle {
    var body: some Widget {
        OpenCameraControl()
    }
}

/// Lock Screen corner / Control Center / Action button control that opens
/// FrameShift on the camera (iOS 18+).
struct OpenCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.anirudhkamath.frameshift.open-camera") {
            ControlWidgetButton(action: OpenCameraIntent()) {
                Label("FrameShift", systemImage: "camera.viewfinder")
            }
        }
        .displayName("FrameShift Camera")
        .description("Open FrameShift straight to the camera.")
    }
}
