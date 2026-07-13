import SwiftUI
import Combine
import AVFoundation

@MainActor
class CameraViewModel: ObservableObject {

    let camera = CameraService()
    let motion = MotionService()

    // UI state
    @Published var isFocused:     Bool = false
    @Published var isLocked:      Bool = false

    // Tool drawer (⋯) toggles, Apple Camera-style.
    @Published var isDrawerOpen:        Bool = false
    @Published var isGridVisible:       Bool = true
    @Published var isLevelVisible:      Bool = true
    @Published var isHeadCircleVisible: Bool = true
    @Published var tipsEnabled:         Bool = true

    @Published var zoomFactor:    CGFloat = 1
    @Published var isFrontCamera: Bool = false
    @Published var flashMode:     AVCaptureDevice.FlashMode = .off

    /// Viewfinder (and therefore capture-crop) shape. The preview layer
    /// aspect-fills its container and captures crop to the visible region,
    /// so the box's ratio is the single source of truth. Session-only,
    /// like the drawer's guide toggles.
    enum CaptureAspect {
        case fourThree    // full sensor frame — the right shape for feed posts
        case sixteenNine  // 9:16 tall in portrait — the story/reel shape

        /// width : height of the portrait viewfinder box.
        var previewRatio: CGFloat {
            switch self {
            case .fourThree:   return 3.0 / 4.0
            case .sixteenNine: return 9.0 / 16.0
            }
        }
    }
    @Published var captureAspect: CaptureAspect = .fourThree

    @Published var cameraAuthorizationState: CameraService.AuthorizationState = .unknown
    @Published var captureFailureNoticeVisible = false
    @Published private(set) var isBursting = false
    /// Shots landed so far in the current shutter hold; shown in the shutter.
    @Published private(set) var burstCount = 0
    /// Brief viewfinder blackout pulsed once per captured frame, like the
    /// native app's shutter blink.
    @Published private(set) var shutterBlinkVisible = false

    @Published var deviceRoll:  Double = 0
    @Published var devicePitch: Double = 0
    @Published var isLevel:     Bool = false

    @Published var compositionProgress = CompositionProgress()
    @Published var activeTip: String?
    @Published var activeTipKind: CoachTipKind?

    /// Viewfinder-local point of the last focus tap; drives the reticle overlay.
    @Published var focusPoint: CGPoint?

    /// EV compensation set by dragging vertically after a focus tap, like the
    /// native Camera app's sun slider. Reset on re-tap, flip, or scene change.
    @Published var exposureBias: CGFloat = 0

    private var activeSpec: ShotSpec?
    private let coach = CompositionCoach()
    private let liveAnalyzer = LiveVisionAnalyzer()
    private var liveSubjectRaw: CGRect?
    private var liveContentSize: CGSize = .zero
    private var viewfinderSize: CGSize = .zero
    private var lightingScore: Double = 0.5

    private var focusResetTask: Task<Void, Never>?
    private var focusReticleTask: Task<Void, Never>?
    private var captureFailureDismissTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    /// Captures fired but not yet completed during a burst — caps how far the
    /// 0.1s tick can run ahead of the photo pipeline (each in-flight shot
    /// holds full-resolution bytes).
    private var inflightBurstCaptures = 0
    private var foregroundObserver: NSObjectProtocol?
    private var pinchBaseZoom: CGFloat?
    private var lastFocusPoint: CGPoint?
    private var dragBaseBias: CGFloat?
    /// Axis lock decided on the first drag tick: vertical drags adjust
    /// exposure, everything else is ignored for the rest of the gesture.
    private var dragIsExposure: Bool?
    private var levelHapticFired = false
    private var allClearHapticFired = false
    /// False while REFERENCE mode (or any non-camera surface) is showing —
    /// motion keeps updating underneath the mode pill, so level / Ready
    /// haptics must not fire when the user can't see the guides.
    private var cameraModeActive = false
    /// Debounces the single-shot path: a fast double-tap on the shutter
    /// shouldn't queue a second full-quality capture before the first's
    /// completion runs. Burst bypasses this and overlaps captures on purpose.
    private var isCapturing = false
    private var cancellables = Set<AnyCancellable>()

    /// Seeds the drawer toggles from Settings' persisted defaults. The
    /// in-drawer toggle itself stays session-only and never writes back —
    /// Settings is the only place that changes what a fresh session starts with.
    init() {
        isGridVisible = Self.storedDefault(.gridVisible)
        isLevelVisible = Self.storedDefault(.levelVisible)
        isHeadCircleVisible = Self.storedDefault(.headCircleVisible)
        tipsEnabled = Self.storedDefault(.tipsEnabled)
    }

    enum DefaultsKey: String {
        case gridVisible = "frameshift.defaultGridVisible"
        case levelVisible = "frameshift.defaultLevelVisible"
        case headCircleVisible = "frameshift.defaultHeadCircleVisible"
        case tipsEnabled = "frameshift.defaultTipsEnabled"
    }

    private static func storedDefault(_ key: DefaultsKey) -> Bool {
        (UserDefaults.standard.object(forKey: key.rawValue) as? Bool) ?? true
    }

    var zoomLevels: [CGFloat] {
        if isFrontCamera { return CameraService.frontZoomLevels }
        return camera.backZoomLevels
    }

    var minZoom: CGFloat { zoomLevels.first ?? 1 }
    // Leave digital headroom past the longest lens (e.g. 10× on a 5× body).
    var maxZoom: CGFloat { max(6, (zoomLevels.last ?? 1) * 2) }

    /// The pill the current (possibly continuous) zoom falls under.
    var activeZoomLevel: CGFloat {
        zoomLevels.last(where: { $0 <= zoomFactor + 0.001 }) ?? minZoom
    }

    // MARK: Lifecycle

    func onAppear(spec: ShotSpec?) {
        activeSpec = spec
        applySpec(spec)
        camera.configure()
        observeMotion()
        observeCamera()
        observeForeground()
        wireVideoFrames()
    }

    func onDisappear() {
        camera.onVideoFrame = nil
        camera.stop()
        motion.stop()
        cameraModeActive = false
        focusResetTask?.cancel()
        focusReticleTask?.cancel()
        captureFailureDismissTask?.cancel()
        stopBurst()
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        cancellables.removeAll()
    }

    /// REFERENCE · CAMERA pill stays inside CameraView, so onDisappear never
    /// runs on mode switch — pause CoreMotion + coaching haptics instead.
    func setCameraModeActive(_ active: Bool) {
        guard cameraModeActive != active else { return }
        cameraModeActive = active
        if active {
            levelHapticFired = false
            allClearHapticFired = false
            motion.start()
        } else {
            motion.stop()
            activeTip = nil
            activeTipKind = nil
        }
    }

    func updateActiveSpec(_ spec: ShotSpec?) {
        activeSpec = spec
        applySpec(spec)
        compositionProgress = CompositionProgress()
        allClearHapticFired = false
    }

    // MARK: Actions

    func handleViewfinderTap(at location: CGPoint) {
        camera.focusAndExpose(atLayerPoint: location)
        exposureBias = 0   // fresh metering at the new point
        focusPoint = location
        lastFocusPoint = location
        scheduleReticleHide()

        withAnimation(.easeOut(duration: 0.2)) {
            isFocused = true
            isLocked  = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scheduleFocusReset()
    }

    /// Vertical drag during a focus session adjusts EV, ~80pt per stop.
    func handleExposureDragChanged(translation: CGSize) {
        guard isLocked, pinchBaseZoom == nil else { return }
        if dragIsExposure == nil {
            dragIsExposure = abs(translation.height) > abs(translation.width)
        }
        guard dragIsExposure == true else { return }

        if dragBaseBias == nil {
            dragBaseBias = exposureBias
            // Hold the reticle and session open while the user is adjusting.
            focusReticleTask?.cancel()
            focusResetTask?.cancel()
            if focusPoint == nil { focusPoint = lastFocusPoint }
        }
        guard let base = dragBaseBias else { return }
        let target = min(max(base - translation.height / 80, -2), 2)
        guard abs(target - exposureBias) > 0.005 else { return }
        exposureBias = target
        camera.setExposureBias(Float(target))
    }

    func handleExposureDragEnded() {
        dragIsExposure = nil
        guard dragBaseBias != nil else { return }
        dragBaseBias = nil
        scheduleReticleHide()
        scheduleFocusReset()
    }

    func handlePinchChanged(_ scale: CGFloat) {
        if pinchBaseZoom == nil { pinchBaseZoom = zoomFactor }
        guard let base = pinchBaseZoom else { return }
        let target = min(max(base * scale, minZoom), maxZoom)
        guard abs(target - zoomFactor) > 0.01 else { return }
        zoomFactor = target
        camera.setZoom(target)
        evaluateCoaching()
    }

    func handlePinchEnded() {
        pinchBaseZoom = nil
        // Settle onto a pill when the pinch lands close to one, so selection reads cleanly.
        if let nearest = zoomLevels.min(by: { abs($0 - zoomFactor) < abs($1 - zoomFactor) }),
           abs(nearest - zoomFactor) < 0.05 {
            zoomFactor = nearest
            camera.setZoom(nearest)
        }
    }

    /// Pill taps ramp to the target like the native app; pinch stays direct.
    func setZoom(_ factor: CGFloat) {
        zoomFactor = factor
        camera.setZoom(factor, animated: true)
        UISelectionFeedbackGenerator().selectionChanged()
        evaluateCoaching()
    }

    func flipCamera() {
        isFrontCamera.toggle()
        // MotionService compares raw physical roll, so its target flips with
        // the mirrored preview (deviceRoll handles the visual-space side).
        motion.targetRoll = physicalRollTarget(for: activeSpec)
        deviceRoll = -deviceRoll
        devicePitch = -devicePitch   // opposite face — see observeMotion()
        let levels = zoomLevels
        if !levels.contains(zoomFactor) {
            zoomFactor = 1
        }
        exposureBias = 0   // CameraService zeroes the incoming device's bias
        camera.switchCamera()
        camera.setZoom(zoomFactor)
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        camera.capturePhoto(flashMode: flashMode) { [weak self] image in
            DispatchQueue.main.async {
                self?.isCapturing = false
                if image == nil {
                    self?.showCaptureFailureNotice()
                } else {
                    self?.triggerShutterBlink()
                }
                completion(image)
            }
        }
    }

    /// Fires captures on a fixed 0.1s cadence while the shutter is held — the
    /// native app's burst rate — overlapping captures instead of waiting for
    /// each to finish. Flash stays off (it can't recycle at 10 fps) and speed
    /// prioritization skips Deep Fusion, both matching the native burst.
    /// Ticks are skipped while the in-flight cap is reached so a slow photo
    /// pipeline degrades to its real rate instead of queueing unboundedly.
    func startBurst(onPhoto: @escaping (UIImage) -> Void) {
        guard burstTask == nil else { return }
        isBursting = true
        burstCount = 0
        inflightBurstCaptures = 0
        burstTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                // Blink on the tick, not on capture completion — completions
                // arrive at irregular pipeline timing, which made the flicker
                // stutter. The tick gives a steady 10 Hz rhythm.
                self.triggerShutterBlink()
                if self.inflightBurstCaptures < 3 {
                    self.inflightBurstCaptures += 1
                    self.camera.capturePhoto(flashMode: .off, prioritization: .speed) { [weak self] image in
                        guard let self else { return }
                        self.inflightBurstCaptures = max(0, self.inflightBurstCaptures - 1)
                        guard let image else { return }
                        self.burstCount += 1
                        onPhoto(image)
                    }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopBurst() {
        burstTask?.cancel()
        burstTask = nil
        isBursting = false
    }

    /// One quick viewfinder blackout; retriggering mid-fade restarts it, so a
    /// 10 fps burst reads as continuous flicker like the native app.
    private func triggerShutterBlink() {
        blinkTask?.cancel()
        shutterBlinkVisible = true
        blinkTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.08)) { self.shutterBlinkVisible = false }
        }
    }

    private func showCaptureFailureNotice() {
        captureFailureDismissTask?.cancel()
        captureFailureNoticeVisible = true
        captureFailureDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            captureFailureNoticeVisible = false
        }
    }

    func cycleFlash() {
        switch flashMode {
        case .off:  flashMode = .auto
        case .auto: flashMode = .on
        default:    flashMode = .off
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: Overlay opacity

    func overlayOpacity(whenFocused target: Double = 0) -> Double {
        isFocused ? target : 1.0
    }

    func guideOpacity(aspectSatisfied: Bool, whenFocused target: Double = 0) -> Double {
        if isFocused { return target }
        return aspectSatisfied ? 0 : 1
    }

    func showTipBanner(aspectSatisfied: Bool) -> Bool {
        tipsEnabled && !isFocused && !aspectSatisfied && activeTip != nil
    }

    func updateViewfinderSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard viewfinderSize != size else { return }
        viewfinderSize = size
        evaluateCoaching()
    }

    // MARK: Private

    private func scheduleReticleHide() {
        focusReticleTask?.cancel()
        focusReticleTask = Task {
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.focusPoint = nil }
        }
    }

    private func scheduleFocusReset() {
        focusResetTask?.cancel()
        focusResetTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.isFocused = false
                self.isLocked  = false
            }
        }
    }

    /// Physical-space roll target for MotionService's level latch: negated on
    /// the front camera, whose mirrored preview flips apparent rotation.
    private func physicalRollTarget(for spec: ShotSpec?) -> Double {
        let target = spec?.coachRollTarget ?? 0
        return isFrontCamera ? -target : target
    }

    private func applySpec(_ spec: ShotSpec?) {
        motion.targetRoll = physicalRollTarget(for: spec)
        guard let spec else { return }
        if zoomLevels.contains(spec.recommendedZoom) {
            setZoom(spec.recommendedZoom)
        }
    }

    private func wireVideoFrames() {
        liveAnalyzer.onUpdate = { [weak self] subject, lighting, contentSize in
            guard let self else { return }
            self.liveSubjectRaw = subject
            self.liveContentSize = contentSize
            self.lightingScore = lighting
            self.evaluateCoaching()
        }
        camera.onVideoFrame = { [weak self] buffer in
            guard let self else { return }
            self.liveAnalyzer.process(pixelBuffer: buffer, isFrontCamera: self.isFrontCamera)
        }
    }

    private func liveSubjectInViewfinder() -> CGRect? {
        guard let raw = liveSubjectRaw, viewfinderSize.width > 0, liveContentSize.width > 0 else {
            return nil
        }
        return ImageContentMapper.viewfinderNormalized(
            raw,
            contentSize: liveContentSize,
            in: viewfinderSize,
            mode: .fill
        )
    }

    private func referenceSubjectInViewfinder(spec: ShotSpec) -> CGRect {
        guard viewfinderSize.width > 0 else {
            return CGRect(x: spec.subjectLeft, y: spec.subjectTop,
                          width: spec.subjectWidth, height: spec.subjectHeight)
        }
        return spec.subjectRect(inViewfinder: viewfinderSize)
    }

    private func observeCamera() {
        camera.$hasUltraWide
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        camera.$backZoomLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        camera.$authorizationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.cameraAuthorizationState = state }
            .store(in: &cancellables)
    }

    /// Catches "granted camera access in Settings, returned to the app"
    /// without requiring a relaunch.
    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.camera.configure()
        }
    }

    private func observeMotion() {
        motion.$roll
            .sink { [weak self] roll in
                guard let self else { return }
                // Preview-visual space: the front camera mirrors the preview,
                // which flips apparent rotation, so the coach/leveler/tilt
                // guide track what the user sees rather than physical roll.
                self.deviceRoll = self.isFrontCamera ? -roll : roll
                self.evaluateCoaching()
            }
            .store(in: &cancellables)

        motion.$pitch
            .sink { [weak self] pitch in
                guard let self else { return }
                // MotionService's pitch is the rear camera's elevation (the
                // -z axis). The front camera looks out the opposite face, so
                // its elevation is the negation — without the flip, selfie
                // tilt coaching points the wrong way.
                self.devicePitch = self.isFrontCamera ? -pitch : pitch
                self.evaluateCoaching()
            }
            .store(in: &cancellables)

        motion.$isLevel
            .removeDuplicates()
            .sink { [weak self] isLevel in
                guard let self else { return }
                self.isLevel = isLevel
                guard self.cameraModeActive else { return }
                if isLevel && !self.levelHapticFired {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    self.levelHapticFired = true
                } else if !isLevel {
                    self.levelHapticFired = false
                }
            }
            .store(in: &cancellables)
    }

    private func evaluateCoaching() {
        guard cameraModeActive, let spec = activeSpec else {
            activeTip = nil
            activeTipKind = nil
            return
        }

        let output = coach.evaluate(
            CompositionCoach.Input(
                spec: spec,
                liveSubject: liveSubjectInViewfinder(),
                referenceSubject: referenceSubjectInViewfinder(spec: spec),
                roll: deviceRoll,
                pitch: devicePitch,
                zoom: zoomFactor,
                lightingScore: lightingScore
            ),
            previous: compositionProgress
        )

        compositionProgress = output.progress
        activeTip = output.tip
        activeTipKind = output.tipKind

        if output.progress.allSatisfied && !allClearHapticFired {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            allClearHapticFired = true
        } else if !output.progress.allSatisfied {
            allClearHapticFired = false
        }

    }
}
