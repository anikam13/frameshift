import SwiftUI
import AVFoundation
import PhotosUI

/// Root screen, styled after the native Camera app: black chrome, top-right
/// control pill, zoom circles over the viewfinder, and a REFERENCE · CAMERA
/// mode pill in place of Apple's VIDEO · PHOTO switcher.
struct CameraView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var vm = CameraViewModel()
    @StateObject private var referencesVM = ReferencesViewModel()

    @State private var showReferenceGhost = false
    // Hold on the top-left reference thumb: full reference, opaque, in the
    // ghost's placement until the finger lifts. The task is the pending
    // hold-threshold timer; cancelled when the finger lifts early (= tap).
    @State private var showReferencePeek = false
    @State private var peekArmTask: Task<Void, Never>?
    @State private var galleryStart: CapturedPhoto?
    @State private var referencePicks: [PhotosPickerItem] = []
    @Namespace private var modePillNamespace

    @AppStorage("frameshift.hasSeenReferenceHint") private var hasSeenReferenceHint = false

    private var activeSpec: ShotSpec? { appState.activeReference?.spec }
    private var isCameraMode: Bool { appState.selectedTab == .camera }

    var body: some View {
        cameraContent
            .background(Color.black)
            .onAppear {
                vm.onAppear(spec: activeSpec)
                vm.setCameraModeActive(isCameraMode)
                vm.setLiveVisionSuspended(appState.isBackgroundVisionBusy)
            }
            .onDisappear { vm.onDisappear() }
            .onChange(of: appState.selectedTab) { _, _ in
                vm.setCameraModeActive(isCameraMode)
            }
            .onChange(of: appState.isBackgroundVisionBusy) { _, busy in
                vm.setLiveVisionSuspended(busy)
            }
            .onChange(of: appState.activeReferenceIndex) { _, _ in
                vm.updateActiveSpec(activeSpec)
                if let id = appState.activeReference?.id {
                    appState.ensureCutoutLoaded(for: id)
                }
            }
            .onChange(of: appState.activeReference?.spec) { _, _ in
                vm.updateActiveSpec(activeSpec)
            }
            .onChange(of: referencePicks) { _, items in
                guard !items.isEmpty else { return }
                referencesVM.importPhotos(items: items, into: appState)
                referencePicks = []
            }
            .fullScreenCover(item: $galleryStart) { shot in
                GalleryPreviewView(selectedID: shot.id)
                    .environmentObject(appState)
            }
            .onChange(of: appState.hasReferences) { _, has in
                if has { hasSeenReferenceHint = true }
            }
    }

    private var cameraContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if isCameraMode {
                    topBar
                        .animation(.easeOut(duration: 0.2), value: vm.isFocused)

                    if let notice = activeNotice {
                        HStack {
                            Spacer()
                            NoticeToast(
                                message: notice.message,
                                actionTitle: notice.actionTitle,
                                action: notice.action,
                                onDismiss: notice.onDismiss
                            )
                            Spacer()
                        }
                        .padding(.top, 6)
                        .transition(.opacity)
                    }

                    Spacer(minLength: 0)

                    // Letterboxed viewfinder, like the native Camera app. At 4:3 the
                    // full sensor frame is visible; 16:9 shows (and captures) the
                    // story-shaped center crop. Either way the saved photo matches
                    // the preview, since captures crop to the visible region.
                    viewfinderBox
                        .aspectRatio(vm.captureAspect.previewRatio, contentMode: .fit)
                        .animation(.easeInOut(duration: 0.25), value: vm.captureAspect)

                    Spacer(minLength: 0)
                } else {
                    // The grid scrolls under the translucent bottom chrome —
                    // photos blurring through the bar are the cue that more
                    // content continues below the fold. The chrome inset
                    // doesn't propagate into the grid's ScrollView, so the
                    // grid pads its scroll content by `bottomChromeHeight`
                    // to keep the last row reachable.
                    ReferencesView()
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            bottomControls
                                .background {
                                    // Blur dissolves in from nothing at the
                                    // top edge — no hard line across the grid.
                                    ZStack {
                                        Rectangle().fill(.ultraThinMaterial)
                                        LinearGradient(
                                            colors: [.black.opacity(0.25), .black.opacity(0.9)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    }
                                    .mask(
                                        LinearGradient(
                                            stops: [
                                                .init(color: .clear, location: 0),
                                                .init(color: .black.opacity(0.85), location: 0.4),
                                                .init(color: .black, location: 0.75)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .ignoresSafeArea()
                                }
                        }
                }

                if isCameraMode {
                    bottomControls
                }
            }
            .safeAreaPadding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            if vm.isDrawerOpen && isCameraMode {
                CameraToolDrawer(vm: vm)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showReferenceHint {
                referenceHint
            }
        }
        .animation(.easeOut(duration: 0.2), value: activeNotice?.message)
    }

    // MARK: Notices

    private struct Notice {
        let message: String
        var actionTitle: String? = nil
        var action: (() -> Void)? = nil
        let onDismiss: () -> Void
    }

    /// Capture-failure and save-failure are both ephemeral and take priority;
    /// the Photos-denied notice is comparatively persistent (stays until
    /// dismissed or the app relaunches), so it only shows when nothing more
    /// urgent is active.
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

    // MARK: First-launch hint

    private var showReferenceHint: Bool {
        // Wait for restore — before it finishes `hasReferences` is falsely
        // empty, and a full-width hint overlay was swallowing REFERENCE taps
        // for the whole cold-start decode window.
        isCameraMode
            && appState.hasFinishedRestoringReferences
            && !appState.hasReferences
            && !hasSeenReferenceHint
    }

    private var referenceHint: some View {
        // Intrinsic size only (bottomLeading overlay). A maxWidth frame here
        // used to cover the mode pill and swallow REFERENCE taps on cold start.
        VStack(spacing: 4) {
            Text("Add a reference photo to get framing guides")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(.white)
        }
        .fixedSize()
        .onTapGesture { hasSeenReferenceHint = true }
        .padding(.bottom, 92)
        .padding(.leading, 40)
        .transition(.opacity)
    }

    private var viewfinderBox: some View {
        GeometryReader { geo in
            Group {
                if vm.cameraAuthorizationState == .denied {
                    CameraPermissionDeniedView()
                } else {
                    viewfinderContent(geo: geo)
                }
            }
            .clipped()
            .overlay(alignment: .top) {
                if vm.cameraAuthorizationState != .denied,
                   let tip = vm.activeTip, vm.showTipBanner(aspectSatisfied: tipIsSatisfied) {
                    TipBanner(message: tip) { vm.activeTip = nil }
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if vm.cameraAuthorizationState != .denied {
                    zoomControls
                        .padding(.bottom, 16)
                        .opacity(vm.overlayOpacity(whenFocused: 0.6))
                        .animation(.easeOut(duration: 0.2), value: vm.isFocused)
                }
            }
            .onAppear { vm.updateViewfinderSize(geo.size) }
            .onChange(of: geo.size) { _, size in vm.updateViewfinderSize(size) }
        }
    }

    private func viewfinderContent(geo: GeometryProxy) -> some View {
        ZStack {
                ViewfinderView(camera: vm.camera)
                    .onTapGesture(coordinateSpace: .local) { location in
                        if vm.isDrawerOpen {
                            closeDrawer()
                            return
                        }
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

                // Shutter blink: the feed blacks out for an instant per
                // captured frame (guides above stay steady), like the native app.
                Color.black
                    .opacity(vm.shutterBlinkVisible ? 1 : 0)
                    .allowsHitTesting(false)

                if let ref = appState.activeReference {
                    let contentSize = activeSpec?.referenceSize ?? ref.image.size
                    let fitRect = ImageContentMapper.contentRect(
                        contentSize: contentSize,
                        in: geo.size,
                        mode: .fit
                    )

                    if showReferenceGhost {
                        // Person-only cutout when segmentation succeeded; the
                        // transparent background lets it run brighter than the
                        // full-frame fallback without hiding the live scene.
                        Image(uiImage: ref.personCutout ?? ref.image)
                            .resizable()
                            .frame(width: fitRect.width, height: fitRect.height)
                            .position(x: fitRect.midX, y: fitRect.midY)
                            .opacity(ref.personCutout != nil ? 0.5 : 0.35)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    // Hold-to-peek: the whole reference, opaque, in exactly
                    // the ghost's placement — same fitRect, so the cutout
                    // fades into the photo without shifting, and framing
                    // against either means the same thing.
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
                        .opacity(vm.guideOpacity(aspectSatisfied: false, whenFocused: vm.overlayOpacity()))
                        .animation(.easeOut(duration: 0.2), value: vm.isFocused)
                }

                if let spec = activeSpec, vm.isLevelVisible,
                   spec.hasTrustedPitch || spec.hasTrustedRoll {
                    TiltPitchGuide(
                        roll: vm.deviceRoll,
                        pitch: vm.devicePitch,
                        targetRoll: spec.coachRollTarget,
                        targetPitch: spec.targetPitch ?? 0,
                        isLevel: vm.isLevel,
                        showPitch: spec.hasTrustedPitch,
                        showRoll: spec.hasTrustedRoll
                    )
                    .opacity(combinedGuideOpacity)
                    .animation(.easeOut(duration: 0.2), value: vm.isFocused)
                    .animation(.easeOut(duration: 0.25), value: vm.compositionProgress.levelOK)
                }

                if let spec = activeSpec, vm.isHeadCircleVisible {
                    SubjectPlacementGuide(
                        spec: spec,
                        isLocked: vm.isLocked,
                        isSatisfied: vm.compositionProgress.framingOK
                    )
                    .opacity(vm.guideOpacity(
                        aspectSatisfied: vm.compositionProgress.framingOK,
                        whenFocused: 0.25
                    ))
                    .animation(.easeOut(duration: 0.2), value: vm.isFocused)
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

    private var combinedGuideOpacity: Double {
        let rollDone = vm.compositionProgress.levelOK
        let tiltDone = vm.compositionProgress.tiltOK
        if vm.isFocused { return vm.overlayOpacity() }
        if rollDone && tiltDone { return 0 }
        return 1
    }

    private var flashIconName: String {
        switch vm.flashMode {
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        default:    return "bolt.slash.fill"
        }
    }

    private var tipIsSatisfied: Bool {
        guard let kind = vm.activeTipKind else { return true }
        let p = vm.compositionProgress
        switch kind {
        case .lighting:    return p.lightingOK
        case .tilt:        return p.tiltOK
        case .distance:    return p.framingOK
        case .horizontal:  return p.framingOK
        case .vertical:    return p.framingOK
        case .level:       return p.levelOK
        }
    }

    /// Live match readout in 5% steps (steadier than raw), capped below 100
    /// so the latched "Ready" is the only thing that ever reads as complete.
    private var matchPercent: Int? {
        guard activeSpec != nil else { return nil }
        let score = vm.compositionProgress.matchScore
        guard score > 0 else { return nil }
        return min(Int((score * 20).rounded()) * 5, 95)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            if vm.cameraAuthorizationState != .denied {
                referencePeekButton
                    .opacity(appState.activeReference != nil ? 1 : 0)
            }

            Spacer()

            if vm.cameraAuthorizationState != .denied {
                Group {
                    if vm.compositionProgress.allSatisfied {
                        Text("Ready")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.cameraYellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                    } else if let percent = matchPercent {
                        // Progressive readout while composing — same slot the
                        // Ready pill takes over once everything latches.
                        Text("\(percent)%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .contentTransition(.numericText())
                            .animation(.easeOut(duration: 0.2), value: percent)
                    }

                    controlPill
                }
                .opacity(vm.overlayOpacity())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Dark rounded pill top-right, like the native app's night/flash/live/⋯ cluster.
    private var controlPill: some View {
        HStack(spacing: 0) {
            Button { vm.cycleFlash() } label: {
                Image(systemName: flashIconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(vm.flashMode == .off ? .white : Color.cameraYellow)
                    .frame(width: 44, height: 44)
            }

            Button { toggleDrawer() } label: {
                MoreDotsGlyph()
                    .foregroundStyle(vm.isDrawerOpen ? Color.cameraYellow : .white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .background(Color(white: 0.14), in: Capsule())
    }

    /// Reference thumbnail + eye — always visible when a reference is active.
    /// Tap toggles the persistent ghost cutout; press and hold peeks the full
    /// reference (opaque, ghost placement) until the finger lifts. One manual
    /// press gesture instead of Button/TapGesture + LongPressGesture: composed
    /// recognizers made the tap unreliable — the exclusive long-press keeps
    /// the tap suppressed while it's still "possible".
    private var referencePeekButton: some View {
        Group {
            if let ref = appState.activeReference {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: ref.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))

                    Image(systemName: showReferenceGhost ? "eye.fill" : "eye")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.55), in: Circle())
                        .offset(x: 4, y: 4)
                }
                .contentShape(Circle())
                .gesture(referenceThumbPressGesture)
            }
        }
    }

    /// Press decides on release: lift before the arm delay → tap (toggle the
    /// ghost); held past it → the armed peek was showing, so just drop it.
    private var referenceThumbPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard peekArmTask == nil, !showReferencePeek else { return }
                peekArmTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeIn(duration: 0.12)) { showReferencePeek = true }
                }
            }
            .onEnded { _ in
                peekArmTask?.cancel()
                peekArmTask = nil
                if showReferencePeek {
                    withAnimation(.easeOut(duration: 0.15)) { showReferencePeek = false }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { showReferenceGhost.toggle() }
                }
            }
    }

    // MARK: Zoom controls (overlaid on the viewfinder, Apple-style)

    private var zoomControls: some View {
        VStack(spacing: 10) {
            if let spec = activeSpec, !vm.compositionProgress.zoomOK {
                Text("\(zoomLabel(spec.recommendedZoom)) recommended · \(spec.framing.rawValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
            }

            HStack(spacing: 6) {
                ForEach(vm.zoomLevels, id: \.self) { level in
                    zoomCircle(level)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            // Absorb taps across the whole cluster (including the gaps between
            // buttons) so a near-miss never falls through to tap-to-focus.
            .contentShape(Capsule())
            .onTapGesture {}
        }
    }

    private func zoomCircle(_ level: CGFloat) -> some View {
        let isSelected = vm.activeZoomLevel == level
        let isRecommended = activeSpec?.recommendedZoom == level && !vm.compositionProgress.zoomOK
        return Button { vm.setZoom(level) } label: {
            Group {
                if isSelected {
                    // Selected shows the live value while pinched between levels (e.g. "1.7×").
                    Text(zoomLabel(vm.zoomFactor))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.cameraYellow)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())
                } else {
                    Text(zoomLabelBare(level))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(Color.cameraYellow, lineWidth: isRecommended ? 1.5 : 0)
                        )
                }
            }
            // 44pt minimum hit target regardless of the visual size.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Bottom controls

    /// `bottomControls`' height: top padding 14 + shutter row 74 + spacing 16
    /// + thumbnail row 46 + bottom padding 6. The references grid pads its
    /// scroll content by this so the last row can scroll clear of the chrome.
    static let bottomChromeHeight: CGFloat = 156

    private var bottomControls: some View {
        VStack(spacing: 16) {
            ZStack {
                if isCameraMode && vm.cameraAuthorizationState != .denied {
                    ShutterButton(
                        isBursting: vm.isBursting,
                        burstCount: vm.burstCount,
                        onTap: { capture() },
                        onHoldStart: { startBurst() },
                        onHoldEnd: { vm.stopBurst() }
                    )
                } else if !isCameraMode {
                    addReferenceButton
                }
            }
            .frame(height: 74)

            ZStack {
                HStack {
                    libraryThumbnail
                    Spacer()
                    flipButton
                        .opacity(isCameraMode && vm.cameraAuthorizationState != .denied ? 1 : 0)
                        .disabled(!isCameraMode || vm.cameraAuthorizationState == .denied)
                        .allowsHitTesting(isCameraMode && vm.cameraAuthorizationState != .denied)
                }
                modePill
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .opacity(vm.isDrawerOpen && isCameraMode ? 0 : 1)
        .allowsHitTesting(!(vm.isDrawerOpen && isCameraMode))
    }

    /// Shutter-shaped photo picker in reference mode: ring + plus. Dark fill
    /// keeps the circle legible over photos scrolling beneath the gradient.
    private var addReferenceButton: some View {
        PhotosPicker(selection: $referencePicks, maxSelectionCount: 10, matching: .images) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 74, height: 74)
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .frame(width: 74, height: 74)
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    /// REFERENCE · CAMERA switcher, mimicking Apple's VIDEO · PHOTO pill.
    private var modePill: some View {
        HStack(spacing: 2) {
            modeSegment("REFERENCE", tab: .references)
            modeSegment("CAMERA", tab: .camera)
        }
        .padding(3)
        .background(Color(white: 0.14), in: Capsule())
    }

    private func modeSegment(_ title: String, tab: AppState.Tab) -> some View {
        let isSelected = appState.selectedTab == tab
        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                appState.selectedTab = tab
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(isSelected ? Color.cameraYellow : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(white: 0.26))
                            .matchedGeometryEffect(id: "modeSelection", in: modePillNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// Bottom-left last-shot thumbnail; opens the gallery preview. The empty
    /// placeholder is not a button at all, so it never shows press feedback.
    private var libraryThumbnail: some View {
        Group {
            if let last = appState.capturedShots.first {
                Button {
                    galleryStart = last
                } label: {
                    Image(uiImage: last.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(.white.opacity(0.10))
                    .frame(width: 46, height: 46)
                    .allowsHitTesting(false)
            }
        }
    }

    private var flipButton: some View {
        Button { vm.flipCamera() } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(white: 0.14), in: Circle())
        }
    }

    // MARK: Actions

    private func toggleDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            vm.isDrawerOpen.toggle()
        }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            vm.isDrawerOpen = false
        }
    }

    private func capture() {
        let referenceAtCapture = appState.activeReference
        vm.capturePhoto { image in
            guard let image else { return }
            appState.addCapturedShot(image, referenceID: referenceAtCapture?.id)
        }
    }

    /// Holding the shutter fires continuous captures (like the native Camera
    /// app's burst) until the finger lifts. The reference is frozen at the
    /// start of the hold so a mid-burst reference switch can't split results.
    /// Every shot in the hold shares one burstID, so the gallery shows the
    /// whole burst as a single stack.
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

    /// Unselected pills drop the "×", like the native app ("1  2  5").
    private func zoomLabelBare(_ z: CGFloat) -> String {
        if z == 0.5 { return "0.5" }
        if abs(z - z.rounded()) < 0.05 { return "\(Int(z.rounded()))" }
        return String(format: "%.1f", z)
    }
}

/// 2×3 dot grid matching the native camera's ⋯ "more" button.
private struct MoreDotsGlyph: View {
    var body: some View {
        VStack(spacing: 3.5) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 3.5) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().frame(width: 3.5, height: 3.5)
                    }
                }
            }
        }
    }
}
