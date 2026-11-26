import AppIntents
import Foundation

/// Opens FrameShift straight to the camera. Compiled into both the app and the
/// FrameShiftControls extension: the Lock Screen / Control Center control
/// references it, and because it opens the app, iOS runs `perform()` in the
/// app process. Also shows up in Shortcuts and on the Action button.
struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open FrameShift Camera"
    static let description = IntentDescription("Opens FrameShift straight to the camera.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        CameraLaunchRequest.request()
        return .result()
    }
}

/// Hand-off from `OpenCameraIntent` to the app UI. On a cold launch the intent
/// can run before any view exists, so the request is held until consumed.
@MainActor
enum CameraLaunchRequest {
    static let notification = Notification.Name("FrameShiftOpenCameraRequest")
    private(set) static var isPending = false

    static func request() {
        isPending = true
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// Returns true once per request.
    static func consume() -> Bool {
        defer { isPending = false }
        return isPending
    }
}
