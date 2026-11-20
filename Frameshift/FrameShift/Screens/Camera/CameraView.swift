import SwiftUI
import AVFoundation
import PhotosUI

/// The camera (Paper page "01 · Camera foundation"). Dark Apple-native chrome:
/// a top row with back, reference thumbnail + picker chevron, Overlay and
/// Guides mode buttons, one-tap flash and ⋯; the 3:4 viewfinder with the
/// active visual aid and the coaching pill; a zoom row; and capture controls
/// (session thumbnail + count, shutter, flip).
///
/// The gallery home renders over this view when `selectedTab == .references`;
/// the camera stays mounted underneath (see `content`).
struct CameraView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CameraViewModel()

    // Hold on the reference thumbnail: full reference, opaque, in the
    // overlay's placement until the finger lifts. The task is the pending
    // hold-threshold timer; cancelled when the finger lifts early (= tap).
    @State private var showReferencePeek = false
    @State private var peekArmTask: Task<Void, Never>?
    @State private var isSessionPresented = false
    @AppStorage(FirstUseTour.cameraDoneKey) private var cameraTourDone = false
    @State private var cameraTourStep: Int?
    @State private var showSavedCaption = false
    @State private var savedCaptionTask: Task<Void, Never>?
    /// References whose "Couldn't prepare reference" card was dismissed.
    @State private var dismissedUnavailableIDs: Set<UUID> = []
    @State private var isPickerPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The launch restore sets the reference before the feed first settles;
    /// that one shouldn't animate — only switches the user makes later.
    @State private var feedHasSettledOnce = false
    @State private var pickerDetent: PresentationDetent = ReferencePickerSheet.compactDetent
    @Namespace private var modePillNamespace

    private var activeSpec: ShotSpec? { appState.activeReference?.spec }
    private var isCameraMode: Bool { appState.selectedTab == .camera }
    private var cameraUsable: Bool { vm.cameraAuthorizationState != .denied }

    /// Black for the camera, the gallery's color under the gallery. A fading
    /// view is drawn only within its bounds, so mid-fade the gallery's
    /// safe-area background (status bar, home indicator) isn't drawn — these
    /// strips showed the camera's black for a beat. Matching the backdrop
    /// to the destination (animated with the tab switch) removes the bar.
    private var rootBackground: Color {
        isCameraMode ? .black : Color(.systemBackground)
    }

    var body: some View {
        content
            // Camera chrome is fixed-size like the system Camera; text that
            // does scale (coaching, cards, tours) stops at xxxLarge (D-32).
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .background(rootBackground)
            // Gallery follows the system appearance; the camera is always
            // dark (D-30).
            .preferredColorScheme(isCameraMode ? .dark : nil)
            .onAppear {
                vm.onAppear(spec: activeSpec)
                vm.setCameraModeActive(isCameraMode)
                vm.setLiveVisionSuspended(appState.isBackgroundVisionBusy)
            }
            .onDisappear { vm.onDisappear() }
            .onChange(of: appState.selectedTab) { _, _ in
                vm.setCameraModeActive(isCameraMode)
            }
            .onChange(of: vm.isFeedSettled, initial: true) { _, settled in
                appState.isCameraFeedSettled = settled
                if settled { feedHasSettledOnce = true }
            }
            .onChange(of: appState.isBackgroundVisionBusy) { _, busy in
                vm.setLiveVisionSuspended(busy)
            }
            .onChange(of: appState.activeReference?.id) { _, id in
                // A new reference restarts adaptation; the session carries on.
                vm.updateActiveSpec(activeSpec)
                if let id { appState.ensureCutoutLoaded(for: id) }
                if let id { scanInPlace(referenceID: id) }
            }
            .onChange(of: appState.recreateMorph?.id, initial: true) { _, id in
                guard id != nil, vm.cameraAuthorizationState != .authorized else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    appState.morphReferenceID = nil
                    appState.recreateMorph = nil
                }
            }
            // First Recreate goes through the camera-access screen, which
            // drops the morph. Once access is granted, play the in-place
            // scan for that reference so the first one isn't a plain pop-in.
            .onChange(of: vm.cameraAuthorizationState) { old, new in
                guard old == .notDetermined, new == .authorized, isCameraMode,
                      !reduceMotion,
                      let ref = appState.activeReference else { return }
                appState.morphReferenceID = ref.id
                appState.recreateMorph = RecreateMorphRequest(
                    referenceID: ref.id, image: ref.image, inPlace: true
                )
            }
            .onChange(of: appState.activeReference?.spec) { _, _ in
                vm.updateActiveSpec(activeSpec)
            }
            .fullScreenCover(isPresented: $isSessionPresented) {
                SessionGalleryView()
                    .environmentObject(appState)
            }
            .onChange(of: appState.sessionSavedCount) { old, new in
                guard new > old else { return }
                flashSavedCaption()
            }
            .task(id: cameraTourTrigger) { await startCameraTourIfNeeded() }
            .alert(
                "Photo couldn’t be saved",
                isPresented: Binding(
                    get: { appState.failedSaveShotID != nil && isCameraMode },
                    set: { _ in }
                )
            ) {
                Button("Try Again") { appState.retryFailedSave() }
                Button("Discard Photo", role: .destructive) { appState.discardFailedSave() }
            } message: {
                Text("This photo hasn’t been saved to Photos.")
            }
            .sheet(isPresented: $isPickerPresented) {
                ReferencePickerSheet(detent: $pickerDetent)
                    .environmentObject(appState)
                    .presentationDetents(
                        [ReferencePickerSheet.compactDetent, .large],
                        selection: $pickerDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
                    .presentationBackgroundInteraction(.disabled)
            }
    }

    /// The camera stays mounted underneath the references screen. Rebuilding
    /// it would recreate `ViewfinderView`, and attaching a preview layer to
    /// the running session blocks the main thread inside a SwiftUI layout
    /// pass — which re-enters layout and hangs the app.
    private var content: some View {
        ZStack {
            cameraScreen
                // Before access is decided there's no feed: keep the chrome
                // (mounted, but invisible) from flashing under the
                // explanation as it fades in or out.
                .opacity(vm.cameraAuthorizationState == .notDetermined
                         || vm.cameraAuthorizationState == .unknown ? 0 : 1)
                .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                    TourOverlay(steps: FirstUseTour.camera, index: $cameraTourStep, anchors: anchors) {
                        cameraTourDone = true
                    }
                }
                .overlay {
                    if isCameraMode && vm.cameraAuthorizationState == .notDetermined {
                        CameraAccessExplanationView(
                            reference: appState.activeReference?.image,
                            onContinue: { vm.requestCameraAccess() },
                            onNotNow: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    appState.selectedTab = .references
                                }
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .allowsHitTesting(isCameraMode)
                .accessibilityHidden(!isCameraMode)

            if !isCameraMode {
                // Cross-fade; the backdrop color animates with it.
                referencesScreen
                    .transition(.opacity)
            }

            // No live camera to land on (access not granted yet / denied):
            // the permission screen shows instead, so skip the hand-off.
            if let morph = appState.recreateMorph, vm.cameraAuthorizationState == .authorized {
                RecreateMorphView(
                    request: morph,
                    cutout: appState.references.first { $0.id == morph.referenceID }?.personCutout,
                    isReady: appState.isCameraFeedSettled && appState.isOverlayReady(for: morph.referenceID),
                    viewfinder: appState.viewfinderFrame,
                    overlayOpacity: referenceOverlayOpacity
                ) {
                    // A newer switch may have replaced this morph already.
                    guard appState.recreateMorph?.id == morph.id else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        appState.morphReferenceID = nil
                        appState.recreateMorph = nil
                    }
                }
                .id(morph.id)
            }
        }
    }

    // MARK: Camera screen

    private var cameraScreen: some View {
        VStack(spacing: 0) {
            topBar

            if let notice = activeNotice {
                NoticeToast(
                    message: notice.message,
                    actionTitle: notice.actionTitle,
                    action: notice.action,
                    onDismiss: notice.onDismiss
                )
                .padding(.vertical, 6)
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            // Captures crop to this box, so its ratio is the output shape.
            viewfinderBox
                .aspectRatio(vm.captureAspect.previewRatio, contentMode: .fit)
                .animation(.easeInOut(duration: 0.25), value: vm.captureAspect)

            Spacer(minLength: 0)

            if cameraUsable {
                zoomRow
            }
            captureControls
        }
        .background(rootBackground.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: activeNotice?.message)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            iconButton(systemName: "chevron.left", label: "References") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    appState.selectedTab = .references
                }
            }

            Spacer(minLength: 4)

            referenceControl

            Spacer(minLength: 4)

            modeButton(
                systemName: "square.on.square",
                label: "Overlay",
                isSelected: vm.aidMode.isManualOverlay
            ) { vm.toggleOverlayMode() }
            .disabled(appState.activeReference == nil || !cameraUsable)
            .tourAnchor(.cameraOverlay)

            Spacer(minLength: 4)

            modeButton(
                systemName: "dot.viewfinder",
                label: "Guides",
                isSelected: vm.aidMode.isManualGuides
            ) { vm.toggleGuidesMode() }
            .disabled(activeSpec == nil || !cameraUsable)
            .tourAnchor(.cameraGuides)

            Spacer(minLength: 4)

            modeButton(
                systemName: vm.flashMode == .on ? "bolt.fill" : "bolt.slash",
                label: vm.flashMode == .on ? "Flash on" : "Flash off",
                isSelected: vm.flashMode == .on
            ) { vm.toggleFlash() }
            .disabled(!cameraUsable)

            Spacer(minLength: 4)

            moreMenu
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .opacity(vm.overlayOpacity(whenFocused: 0.6))
        .animation(.easeOut(duration: 0.2), value: vm.isFocused)
    }

    /// Thumbnail + chevron, one control: tap = reference picker (quick
    /// switch); hold = peek the full reference. Overlay on/off lives on the
    /// Overlay button only.
    private var referenceControl: some View {
        HStack(spacing: 2) {
            Group {
                if let ref = appState.activeReference {
                    Image(uiImage: ref.image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.12)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.7))
                        )
                }
            }
            .frame(width: 36, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 44)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .gesture(referenceThumbPressGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Choose reference")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openPicker() }
    }

    /// Isolated so the camera's frequent view-model updates don't rebuild
    /// the menu while it's opening (which made it flaky). Aspect ratio is
    /// listed inline — no submenu to open.
    private var moreMenu: some View {
        #if DEBUG
        let isEvalVisible = vm.isEvalHUDVisible
        let setEval: (Bool) -> Void = { vm.isEvalHUDVisible = $0 }
        #else
        let isEvalVisible = false
        let setEval: (Bool) -> Void = { _ in }
        #endif
        return CameraMoreMenu(
            isGridVisible: vm.isGridVisible,
            captureAspect: vm.captureAspect,
            isEvalHUDVisible: isEvalVisible,
            setGrid: { vm.isGridVisible = $0 },
            setAspect: { vm.captureAspect = $0 },
            setEval: setEval
        )
        .equatable()
        .disabled(!cameraUsable)
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 44pt round button; a manually selected state gets the yellow glyph on
    /// the dark yellow tint. Only manual selections are highlighted —
    /// adaptive transitions never light these up.
    private func modeButton(
        systemName: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? Color.cameraYellow : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isSelected ? Color.cameraAccentTint : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    /// Press decides on release: lift before the arm delay → tap (open the
    /// picker); held past it → the armed peek was showing, so drop it.
    private var referenceThumbPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard appState.activeReference != nil,
                      peekArmTask == nil, !showReferencePeek else { return }
                peekArmTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.12)) { showReferencePeek = true }
                }
            }
            .onEnded { _ in
                peekArmTask?.cancel()
                peekArmTask = nil
                if showReferencePeek {
                    withAnimation(.easeOut(duration: 0.15)) { showReferencePeek = false }
                } else {
                    openPicker()
                }
            }
    }

    // MARK: Viewfinder

    private var viewfinderBox: some View {
        GeometryReader { geo in
            Group {
                if cameraUsable {
                    viewfinderContent(geo: geo)
                } else {
                    CameraPermissionDeniedView()
                }
            }
            .clipped()
            .overlay(alignment: .top) {
                if cameraUsable, let unavailable = unavailableReference {
                    ReferenceUnavailableCard(
                        onRetry: { appState.retryAnalysis(id: unavailable.id) },
                        onDismiss: { dismissedUnavailableIDs.insert(unavailable.id) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .transition(.opacity)
                } else if cameraUsable, let pill = coachingContent {
                    CoachingPill(content: pill) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            vm.isCoachingCollapsed.toggle()
                        }
                    }
                    .tourAnchor(.cameraCoaching)
                    .padding(.top, 20)
                    .opacity(vm.overlayOpacity(whenFocused: 0.4))
                    .transition(.opacity)
                }
            }
            #if DEBUG
            .overlay(alignment: .bottomLeading) {
                if cameraUsable && vm.isEvalHUDVisible {
                    CoachEvalHUD(eval: vm.eval) { vm.isEvalHUDVisible = false }
                        .padding(10)
                }
            }
            #endif
            .onAppear {
                vm.updateViewfinderSize(geo.size)
                appState.viewfinderFrame = geo.frame(in: .global)
            }
            .onChange(of: geo.size) { _, size in vm.updateViewfinderSize(size) }
            .onChange(of: geo.frame(in: .global)) { _, frame in appState.viewfinderFrame = frame }
        }
    }

    private func viewfinderContent(geo: GeometryProxy) -> some View {
        ZStack {
            ViewfinderView(camera: vm.camera)
                .onTapGesture(coordinateSpace: .local) { location in
                    vm.handleViewfinderTap(at: location)
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { vm.handlePinchChanged($0) }
                        .onEnded { _ in vm.handlePinchEnded() }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { vm.handleExposureDragChanged(translation: $0.translation) }
                        .onEnded { _ in vm.handleExposureDragEnded() }
                )

            // Shutter blink: the feed blacks out for an instant per frame.
            Color.black
                .opacity(vm.shutterBlinkVisible ? 1 : 0)
                .allowsHitTesting(false)

            if let ref = appState.activeReference {
                let contentSize = activeSpec?.referenceSize ?? ref.image.size
                let fitRect = ImageContentMapper.contentRect(
                    contentSize: contentSize, in: geo.size, mode: .fit
                )

                // Overlay mode: person-only cutout at the fixed 35%; the full
                // frame is the fallback when segmentation found no person.
                if vm.aidMode.showsOverlay {
                    Image(uiImage: ref.personCutout ?? ref.image)
                        .resizable()
                        .frame(width: fitRect.width, height: fitRect.height)
                        .position(x: fitRect.midX, y: fitRect.midY)
                        .opacity(appState.isRecreateMorphInFlight ? 0 : referenceOverlayOpacity)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if showReferencePeek {
                    Image(uiImage: ref.image)
                        .resizable()
                        .frame(width: fitRect.width, height: fitRect.height)
                        .position(x: fitRect.midX, y: fitRect.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }

            if vm.isGridVisible {
                GridOverlay()
                    .opacity(vm.overlayOpacity(whenFocused: 0.6))
                    .allowsHitTesting(false)
            }

            // Guides mode: one fixed head-target circle plus a contextual
            // level that appears only while noticeably tilted.
            if vm.aidMode.showsGuides, let spec = activeSpec {
                if spec.hasTrustedPitch || spec.hasTrustedRoll {
                    TiltPitchGuide(
                        roll: vm.deviceRoll,
                        pitch: vm.devicePitch,
                        targetRoll: spec.coachRollTarget,
                        targetPitch: spec.targetPitch ?? 0,
                        isLevel: vm.isLevel,
                        showPitch: spec.hasTrustedPitch,
                        showRoll: spec.hasTrustedRoll
                    )
                    .opacity(levelOpacity)
                    .animation(.easeOut(duration: 0.25), value: vm.compositionProgress.levelOK)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                SubjectPlacementGuide(
                    spec: spec,
                    isAligned: vm.compositionProgress.allSatisfied
                )
                .opacity(vm.overlayOpacity(whenFocused: 0.4))
                .transition(.opacity)
            }

            if let point = vm.focusPoint {
                FocusReticle(
                    bias: vm.exposureBias,
                    sliderOnRight: point.x < geo.size.width - 72
                )
                .position(point)
                .id("\(point.x),\(point.y)")
                .transition(.opacity)
            }
        }
    }

    /// Level fades once roll and tilt are both aligned.
    private var levelOpacity: Double {
        if vm.isFocused { return 0.4 }
        let p = vm.compositionProgress
        return (p.levelOK && p.tiltOK) ? 0 : 1
    }

    /// One state for the pill. Needs an analyzed reference; the user's
    /// collapse wins over everything except the ready check, which already
    /// is the reduced form.
    private var coachingContent: CoachingPill.Message? {
        guard activeSpec != nil else { return nil }
        let aligned = vm.compositionProgress.allSatisfied
        if vm.isCoachingCollapsed { return aligned ? .readyCheck : .collapsed }
        if aligned { return vm.showsAlignedConfirmation ? .lookingGood : .readyCheck }
        if !vm.isSubjectDetected { return .lookingForSubject }
        if let tip = vm.activeTip { return .instruction(tip) }
        return nil
    }

    // MARK: Zoom row

    private var zoomRow: some View {
        HStack(spacing: 12) {
            ForEach(vm.zoomLevels, id: \.self) { level in
                zoomButton(level)
            }
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // Drag sideways to fine-adjust between lenses (D-22); taps still
        // select presets.
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { vm.handleZoomScrubChanged(translation: $0.translation.width) }
                .onEnded { _ in vm.handleZoomScrubEnded() }
        )
        .overlay(alignment: .top) {
            if vm.isZoomScrubbing {
                Text(zoomLabel(vm.zoomFactor))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.cameraYellow)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.coachPill))
                    .offset(y: -22)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: vm.isZoomScrubbing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zoom")
        .accessibilityValue(zoomLabel(vm.zoomFactor))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: vm.stepZoom(up: true)
            case .decrement: vm.stepZoom(up: false)
            @unknown default: break
            }
        }
    }

    private func zoomButton(_ level: CGFloat) -> some View {
        let isSelected = vm.activeZoomLevel == level
        let isRecommended = activeSpec?.recommendedZoom == level && !vm.compositionProgress.zoomOK
        return Button { vm.setZoom(level) } label: {
            Group {
                if isSelected {
                    // Live value while pinched between presets (e.g. "1.7×").
                    Text(zoomLabel(vm.zoomFactor))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.cameraYellow)
                        .frame(width: 44, height: 44)
                        .background(Color.cameraControl, in: Circle())
                } else {
                    Text(zoomLabelBare(level))
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.cameraYellow.opacity(0.8), lineWidth: 1)
                                .frame(width: 32, height: 32)
                                .opacity(isRecommended ? 1 : 0)
                        )
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(zoomLabel(level))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Capture controls

    private var captureControls: some View {
        HStack {
            sessionThumbnail
            Spacer()
            ShutterButton(
                isBursting: vm.isBursting,
                burstCount: vm.burstCount,
                onPressDown: { vm.prepareShutter() },
                onTap: { capture() },
                onHoldStart: { startBurst() },
                onHoldEnd: { vm.stopBurst() }
            )
            .opacity(cameraUsable ? 1 : 0.3)
            .disabled(!cameraUsable)
            .allowsHitTesting(cameraUsable)
            .tourAnchor(.cameraShutter)
            Spacer()
            Button { vm.flipCamera() } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.cameraControl, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch camera")
            .opacity(cameraUsable ? 1 : 0)
            .disabled(!cameraUsable)
        }
        .padding(.horizontal, 30)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(height: 108)
    }

    /// Most recent capture with the session's saved-photo count badge.
    private var sessionThumbnail: some View {
        Group {
            if let last = appState.sessionShots.first {
                Button { isSessionPresented = true } label: {
                    Image(uiImage: last.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            let count = appState.sessionSavedCount
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.black)
                                    .monospacedDigit()
                                    .padding(.horizontal, count > 9 ? 5 : 0)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .background(Color.white, in: Capsule())
                                    .offset(x: 7, y: -7)
                                    .contentTransition(.numericText())
                                    .animation(.snappy(duration: 0.15), value: count)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photos from this session: \(appState.sessionSavedCount)")
                // Paper "Capture saved feedback": a quiet caption, no toast.
                .overlay(alignment: .bottomLeading) {
                    if showSavedCaption {
                        Text("Saved to Photos")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .fixedSize()
                            .offset(y: 26)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 48, height: 48)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: First use and recovery

    /// Active reference whose analysis failed and whose card wasn't dismissed.
    private var unavailableReference: ReferencePhoto? {
        guard let ref = appState.activeReference, ref.analysisFailed,
              !dismissedUnavailableIDs.contains(ref.id) else { return nil }
        return ref
    }

    private var cameraTourTrigger: String {
        "\(cameraTourDone)-\(isCameraMode)-\(vm.cameraAuthorizationState == .authorized)"
    }

    /// Camera tour: first time the camera is live (or after Replay Tutorial).
    private func startCameraTourIfNeeded() async {
        guard !cameraTourDone, cameraTourStep == nil, isCameraMode,
              vm.cameraAuthorizationState == .authorized else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled, !cameraTourDone, isCameraMode else { return }
        cameraTourStep = 0
    }

    private func flashSavedCaption() {
        savedCaptionTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showSavedCaption = true }
        savedCaptionTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showSavedCaption = false }
        }
    }

    // MARK: Reference switch scan

    /// Switching reference while in the camera (picker sheet) plays the same
    /// scan → lift → settle as Recreate, in place over the viewfinder, so the
    /// new overlay never pops in half-loaded. Recreate / quick-row switches
    /// already run their own morph (flag set), and Reduce Motion keeps the
    /// plain swap.
    private func scanInPlace(referenceID id: UUID) {
        #if DEBUG
        print("[scan] switch ref=\(id.uuidString.prefix(6)) cameraMode=\(isCameraMode) morphing=\(appState.morphReferenceID?.uuidString.prefix(6) ?? "nil") viewfinder=\(appState.viewfinderFrame) reduceMotion=\(reduceMotion)")
        #endif
        // Skip only when this exact reference is already morphing (Recreate /
        // quick row set it before switching). A different in-flight morph is
        // replaced — rapid switches always show the latest reference.
        guard isCameraMode,
              feedHasSettledOnce,
              appState.morphReferenceID != id,
              !appState.viewfinderFrame.isEmpty,
              let ref = appState.references.first(where: { $0.id == id })
        else { return }
        appState.morphReferenceID = id
        appState.recreateMorph = RecreateMorphRequest(
            referenceID: id, image: ref.image, inPlace: true
        )
    }

    // MARK: Gallery home

    private var referencesScreen: some View {
        GalleryHomeView()
    }

    // MARK: Notices

    private struct Notice {
        let message: String
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil
        let onDismiss: () -> Void
    }

    private var activeNotice: Notice? {
        if vm.captureFailureNoticeVisible {
            return Notice(message: "Couldn't capture photo") { vm.captureFailureNoticeVisible = false }
        }
        if let message = appState.transientNotice {
            return Notice(message: message) { appState.transientNotice = nil }
        }
        if appState.photoLibraryDeniedNoticeVisible {
            return Notice(
                message: "Photos aren't being saved to your camera roll",
                actionTitle: "Settings",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                onDismiss: { appState.dismissPhotoLibraryDeniedNotice() }
            )
        }
        return nil
    }

    // MARK: Actions

    private func openPicker() {
        pickerDetent = ReferencePickerSheet.compactDetent
        isPickerPresented = true
    }

    private func capture() {
        let referenceAtCapture = appState.activeReference
        vm.capturePhoto { image in
            guard let image else { return }
            appState.addCapturedShot(image, referenceID: referenceAtCapture?.id)
        }
    }

    /// Holding the shutter fires continuous captures until the finger lifts.
    /// The reference is frozen at the start of the hold, and every shot in
    /// the hold shares one burstID.
    private func startBurst() {
        let referenceAtCapture = appState.activeReference
        let burstID = UUID()
        vm.startBurst { image in
            // Downsample off the main actor — at burst rate the display-size
            // render of each full capture would otherwise stall the viewfinder.
            let maxSize = UIImage.displayMaxPixelSize
            Task.detached(priority: .userInitiated) {
                let display = image.downsampled(maxPixelSize: maxSize)
                await MainActor.run {
                    _ = appState.insertCapturedShot(
                        display: display, full: image,
                        referenceID: referenceAtCapture?.id, burstID: burstID
                    )
                }
            }
        }
    }

    private func zoomLabel(_ z: CGFloat) -> String {
        if z == 0.5 { return "0.5×" }
        if abs(z - z.rounded()) < 0.05 { return "\(Int(z.rounded()))×" }
        return String(format: "%.1f×", z)
    }

    /// Unselected presets drop the "×", like the native app ("0.5  1  2").
    private func zoomLabelBare(_ z: CGFloat) -> String {
        if z == 0.5 { return "0.5" }
        if abs(z - z.rounded()) < 0.05 { return "\(Int(z.rounded()))" }
        return String(format: "%.1f", z)
    }
}

// MARK: - More menu

private struct CameraMoreMenu: View, Equatable {
    let isGridVisible: Bool
    let captureAspect: CameraViewModel.CaptureAspect
    let isEvalHUDVisible: Bool
    let setGrid: (Bool) -> Void
    let setAspect: (CameraViewModel.CaptureAspect) -> Void
    let setEval: (Bool) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.isGridVisible == b.isGridVisible
            && a.captureAspect == b.captureAspect
            && a.isEvalHUDVisible == b.isEvalHUDVisible
    }

    var body: some View {
        Menu {
            Button { setGrid(!isGridVisible) } label: {
                Label(isGridVisible ? "Hide Grid" : "Show Grid", systemImage: "grid")
            }
            Section("Aspect Ratio") {
                aspectButton("4:3 · Posts", .fourThree)
                aspectButton("16:9 · Stories", .sixteenNine)
            }
            #if DEBUG
            Section {
                Button { setEval(!isEvalHUDVisible) } label: {
                    Label(isEvalHUDVisible ? "Hide Coaching Eval" : "Coaching Eval",
                          systemImage: "gauge.with.dots.needle.33percent")
                }
            }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More camera options")
    }

    private func aspectButton(_ title: String, _ value: CameraViewModel.CaptureAspect) -> some View {
        Button { setAspect(value) } label: {
            if captureAspect == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
