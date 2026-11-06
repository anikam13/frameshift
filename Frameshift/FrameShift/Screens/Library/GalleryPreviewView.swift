import SwiftUI
import UIKit

/// Apple Camera-style photo preview, opened from the bottom-left thumbnail.
/// Back chevron + date pill up top, swipeable photo, filmstrip, and the
/// share · heart · info · filters toolbar. A burst appears as one item —
/// its best pick is the cover, and the burst badge opens a picker to choose.
/// Tap toggles chrome (Photos-style); pinch / double-tap zoom the image.
struct GalleryPreviewView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var selectedID: UUID
    @State private var confirmDelete = false
    @State private var showInfoSheet = false
    @State private var showBurstPicker = false
    @State private var showLibrary = false
    @State private var filterTarget: CapturedPhoto?
    @State private var chromeVisible = true
    /// 0…1 while the photo is being dragged down to close.
    @State private var dismissDrag: CGFloat = 0

    private var shots: [CapturedPhoto] { appState.capturedShots }

    private var items: [GalleryItem] { GalleryItem.group(shots) }

    private var currentItem: GalleryItem? { items.first { $0.id == selectedID } }
    private var current: CapturedPhoto? { currentItem?.cover }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - dismissDrag * 0.88)
                .ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    ZoomableGalleryPage(
                        image: item.cover.image,
                        onSingleTap: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                chromeVisible.toggle()
                            }
                        },
                        onDismissProgress: { dismissDrag = $0 },
                        onDismissCommit: { dismiss() }
                    )
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            chromeOverlay
                .opacity(chromeVisible ? 1 - dismissDrag : 0)
                .allowsHitTesting(chromeVisible && dismissDrag < 0.02)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!chromeVisible)
        .onAppear {
            // Callers pass a shot id; if that shot is inside a burst, the
            // pager's pages are keyed by the burst's id instead.
            if let owner = items.first(where: { item in item.shots.contains { $0.id == selectedID } }) {
                selectedID = owner.id
            }
        }
        .confirmationDialog("", isPresented: $confirmDelete, titleVisibility: .hidden) {
            Button(deleteButtonTitle, role: .destructive) { deleteCurrent() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showInfoSheet) {
            CaptureInfoSheet(shot: current, reference: appState.reference(for: current?.referenceID))
        }
        .fullScreenCover(isPresented: $showLibrary) {
            GalleryLibraryView(selectedID: $selectedID)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showBurstPicker) {
            if let item = currentItem, let burstID = item.shots[0].burstID {
                BurstPickerSheet(burstID: burstID) { keptID in
                    // The burst collapsed to one photo; its page is now keyed
                    // by the surviving shot's id.
                    selectedID = keptID
                }
                .environmentObject(appState)
            }
        }
        .fullScreenCover(item: $filterTarget) { shot in
            FilterPresetSheet(shot: shot) { newID in
                withAnimation(.easeOut(duration: 0.2)) { selectedID = newID }
            }
            .environmentObject(appState)
        }
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 14)
                .padding(.top, 6)
            if let item = currentItem, item.isBurst {
                burstBadge(item)
                    .padding(.top, 10)
            }
            Spacer()
            filmstrip
                .padding(.bottom, 14)
            bottomBar
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Button { showLibrary = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .overlay {
            datePill
        }
    }

    private var datePill: some View {
        VStack(spacing: 0) {
            Text(dayString)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(timeString)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var dayString: String {
        guard let date = current?.capturedAt else { return "" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var timeString: String {
        guard let date = current?.capturedAt else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Burst badge

    private func burstBadge(_ item: GalleryItem) -> some View {
        Button { showBurstPicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 12, weight: .semibold))
                Text("Burst · \(item.shots.count) photos")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        filmstripThumb(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 42)
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, id in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func filmstripThumb(_ item: GalleryItem) -> some View {
        let isSelected = item.id == selectedID
        return Image(uiImage: item.cover.image)
            .resizable()
            .scaledToFill()
            .frame(width: isSelected ? 40 : 26, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: isSelected ? 5 : 2))
            .overlay(
                RoundedRectangle(cornerRadius: isSelected ? 5 : 2)
                    .stroke(.white, lineWidth: isSelected ? 1.5 : 0)
            )
            // Surface favorites where you scan for them — the filmstrip.
            .overlay(alignment: .bottomTrailing) {
                if item.cover.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: isSelected ? 9 : 7))
                        .foregroundStyle(.red)
                        .padding(2)
                }
            }
            .overlay(alignment: .topLeading) {
                if item.isBurst {
                    Text("\(item.shots.count)")
                        .font(.system(size: isSelected ? 8 : 7, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(2)
                }
            }
            .padding(.horizontal, isSelected ? 4 : 0)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) { selectedID = item.id }
            }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            if let current {
                ShareLink(
                    item: Image(uiImage: current.image),
                    preview: SharePreview("FrameShift Photo", image: Image(uiImage: current.image))
                ) {
                    circleIcon("square.and.arrow.up")
                }
            }

            Spacer()

            HStack(spacing: 32) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isFavorite ? .red : .white)
                }
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                Button {
                    filterTarget = current
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 30)
            .frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button { confirmDelete = true } label: {
                circleIcon("trash")
            }
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var isFavorite: Bool { current?.isFavorite ?? false }

    private func toggleFavorite() {
        guard let current else { return }
        appState.setFavorite(id: current.id, isFavorite: !current.isFavorite)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var deleteButtonTitle: String {
        guard let item = currentItem, item.isBurst else { return "Delete Photo" }
        return "Delete Burst (\(item.shots.count) Photos)"
    }

    /// Deleting a burst page removes every shot in the burst.
    private func deleteCurrent() {
        let itemsBefore = items
        guard
            let item = currentItem,
            let index = itemsBefore.firstIndex(where: { $0.id == item.id })
        else { return }

        if itemsBefore.count > 1 {
            let nextIndex = index == itemsBefore.count - 1 ? index - 1 : index + 1
            selectedID = itemsBefore[nextIndex].id
        }
        if item.isBurst, let burstID = item.shots[0].burstID {
            appState.removeBurst(burstID: burstID)
        } else {
            appState.removeCapturedShot(id: item.shots[0].id)
        }
        if itemsBefore.count <= 1 { dismiss() }
    }
}

// MARK: - Zoomable page

/// Photos-style pinch / pan / double-tap via UIScrollView. Zoom state lives
/// entirely in UIKit so pan ticks never re-render gallery chrome. At 1×,
/// scrolling is disabled so TabView can page horizontally; a downward pan
/// drags a host view off (not the zoomed image) and dismisses.
private struct ZoomableGalleryPage: View {
    let image: UIImage
    var onSingleTap: () -> Void
    var onDismissProgress: (CGFloat) -> Void
    var onDismissCommit: () -> Void
    @State private var bridge = ZoomableScrollBridge()

    var body: some View {
        ZoomableScrollView(
            image: image,
            onSingleTap: onSingleTap,
            onDismissProgress: onDismissProgress,
            onDismissCommit: onDismissCommit,
            bridge: bridge
        )
        .onDisappear {
            bridge.view?.resetZoom(animated: false)
        }
    }
}

private final class ZoomableScrollBridge {
    weak var view: ZoomableScrollUIView?
}

private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    var onSingleTap: () -> Void
    var onDismissProgress: (CGFloat) -> Void
    var onDismissCommit: () -> Void
    let bridge: ZoomableScrollBridge

    func makeUIView(context: Context) -> ZoomableScrollUIView {
        let view = ZoomableScrollUIView()
        view.onSingleTap = onSingleTap
        view.onDismissProgress = onDismissProgress
        view.onDismissCommit = onDismissCommit
        view.setImage(image)
        bridge.view = view
        return view
    }

    func updateUIView(_ uiView: ZoomableScrollUIView, context: Context) {
        uiView.onSingleTap = onSingleTap
        uiView.onDismissProgress = onDismissProgress
        uiView.onDismissCommit = onDismissCommit
        uiView.setImage(image)
        bridge.view = uiView
    }
}

/// UIScrollView zoom host — same interaction model as the system Photos viewer.
/// Dismiss drag lives on `dismissHost`, not the zoomed image: UIScrollView
/// owns `imageView.transform` for pinch-zoom, and SwiftUI relayouts this
/// representable on every progress tick. Transforming either of those
/// resets the photo to the top of the page mid-drag.
private final class ZoomableScrollUIView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var onSingleTap: (() -> Void)?
    var onDismissProgress: ((CGFloat) -> Void)?
    var onDismissCommit: (() -> Void)?

    private let dismissHost = UIView()
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var currentImage: UIImage?
    private var lastLayoutSize: CGSize = .zero
    private var linkedPagerPan = false
    private var dismissInFlight = false

    private let maxZoom: CGFloat = 4
    private let doubleTapZoom: CGFloat = 2.5
    private let dismissPan = UIPanGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        dismissHost.backgroundColor = .clear
        dismissHost.clipsToBounds = false
        addSubview(dismissHost)

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = false
        // At 1×, leave horizontal swipes to the parent TabView page gesture.
        scrollView.isScrollEnabled = false
        dismissHost.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        dismissPan.addTarget(self, action: #selector(handleDismissPan(_:)))
        dismissPan.delegate = self
        dismissPan.maximumNumberOfTouches = 1
        addGestureRecognizer(dismissPan)
        scrollView.panGestureRecognizer.require(toFail: dismissPan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage) {
        guard currentImage !== image else { return }
        currentImage = image
        imageView.image = image
        lastLayoutSize = .zero
        setNeedsLayout()
    }

    func resetZoom(animated: Bool) {
        dismissInFlight = false
        dismissHost.transform = .identity
        dismissHost.alpha = 1
        onDismissProgress?(0)
        guard scrollView.zoomScale != scrollView.minimumZoomScale
                || scrollView.contentOffset != .zero else {
            scrollView.isScrollEnabled = false
            return
        }
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        scrollView.isScrollEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !linkedPagerPan else { return }
        var ancestor: UIView? = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll !== scrollView {
                scroll.panGestureRecognizer.require(toFail: dismissPan)
                linkedPagerPan = true
                break
            }
            ancestor = view.superview
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size.width > 0, bounds.size.height > 0 else { return }
        // Setting `frame` while a dismiss transform is on the host jumps the
        // photo back to its laid-out origin (the top / centered slot).
        if dismissInFlight { return }
        dismissHost.frame = bounds
        scrollView.frame = dismissHost.bounds
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            configureForCurrentImage()
        }
        centerImage()
    }

    private func configureForCurrentImage() {
        guard let image = imageView.image else { return }
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let boundsSize = scrollView.bounds.size
        let fit = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)

        scrollView.zoomScale = 1
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxZoom
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        scrollView.contentOffset = .zero
        scrollView.isScrollEnabled = false
        centerImage()
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        let imageSize = imageView.frame.size
        var inset = UIEdgeInsets.zero
        if imageSize.width < boundsSize.width {
            let pad = (boundsSize.width - imageSize.width) / 2
            inset.left = pad
            inset.right = pad
        }
        if imageSize.height < boundsSize.height {
            let pad = (boundsSize.height - imageSize.height) / 2
            inset.top = pad
            inset.bottom = pad
        }
        scrollView.contentInset = inset
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        scrollView.isScrollEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        if scale <= scrollView.minimumZoomScale + 0.05 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            scrollView.isScrollEnabled = false
        }
    }

    // MARK: Taps

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began, .changed:
            dismissInFlight = true
            let y = max(0, translation.y)
            let x = translation.x * 0.35
            let scale = max(0.88, 1 - y / 1600)
            dismissHost.transform = CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
            onDismissProgress?(min(1, y / 260))
        case .ended, .cancelled:
            let y = max(0, translation.y)
            let velocity = gesture.velocity(in: self).y
            if y > 140 || velocity > 1100 {
                let x = translation.x * 0.35
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                    self.dismissHost.transform = CGAffineTransform(translationX: x, y: y + 420)
                    self.dismissHost.alpha = 0
                } completion: { _ in
                    self.onDismissProgress?(1)
                    self.onDismissCommit?()
                }
            } else {
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    usingSpringWithDamping: 0.84,
                    initialSpringVelocity: 0.4,
                    options: .allowUserInteraction
                ) {
                    self.dismissHost.transform = .identity
                } completion: { _ in
                    self.dismissInFlight = false
                    self.setNeedsLayout()
                }
                onDismissProgress?(0)
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan else { return true }
        guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return false }
        let velocity = dismissPan.velocity(in: self)
        let translation = dismissPan.translation(in: self)
        let dy = abs(velocity.y) > 40 ? velocity.y : translation.y
        let dx = abs(velocity.y) > 40 ? velocity.x : translation.x
        return dy > 0 && abs(dy) > abs(dx)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            scrollView.isScrollEnabled = false
            return
        }

        let point = gesture.location(in: imageView)
        let size = scrollView.bounds.size
        let width = size.width / doubleTapZoom
        let height = size.height / doubleTapZoom
        let rect = CGRect(
            x: point.x - width / 2,
            y: point.y - height / 2,
            width: width,
            height: height
        )
        scrollView.zoom(to: rect, animated: true)
        scrollView.isScrollEnabled = true
    }
}
