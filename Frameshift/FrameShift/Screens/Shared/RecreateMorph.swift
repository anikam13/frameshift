import SwiftUI

/// Reference → camera hand-off (D-29), shared by the preview's Recreate and
/// the gallery quick row. The camera is only revealed once it's steady.
///
/// 1. Flight   photo flies from where it was tapped to exactly where the
///             overlay draws it (aspect-fit in the viewfinder); a scrim
///             darkens the rest of the viewfinder. No bounce.
/// 2. Scan     a light band sweeps down the photo; behind it the background
///             is cut away and the person's outline lights up — "reading"
///             the reference. It repeats
///             while the camera warms up / zoom ramps / the cutout loads:
///             at least one pass, at most `maxHold`. The photo + scrim cover
///             the feed the whole time, so a starting camera is never seen.
/// 3. Lift     background and scrim dissolve; the person stays at full
///             strength, glowing, over the now-steady live feed.
/// 4. Settle   glow fades, the person drops to the overlay's 35% and swaps
///             for the real overlay — same pixels, rect and opacity.
/// No cutout (no person / analysis failed): the photo itself settles.
/// Reduce Motion: no flight and no moving band — the photo fades in place,
/// the background fades away and the outline glows, same hold-until-ready.
struct RecreateMorphRequest: Identifiable, Equatable {
    let id = UUID()
    let referenceID: UUID
    let image: UIImage
    /// Global rect the photo is drawn in when the morph starts (`.fill`).
    var from: CGRect = .zero
    /// Switching reference inside the camera (picker sheet): no flight —
    /// the photo fades in where the overlay sits, then scans as usual.
    var inPlace = false
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

enum RecreateMorphTiming {
    static let flight = 0.45
    /// The first scan pass starts as the flight lands (overlap, not queue).
    static let scanStart = 0.30
    static let scanPass = 0.375
    /// Give up waiting and reveal anyway (e.g. an import still analyzing).
    static let maxHold = 2.5
    static let lift = 0.30
    static let settle = 0.30
}

struct RecreateMorphView: View {
    let request: RecreateMorphRequest
    /// Read live: the cutout may finish loading mid-scan.
    let cutout: UIImage?
    /// Camera steady + overlay final.
    let isReady: Bool
    /// Global rect of the viewfinder.
    let viewfinder: CGRect
    let overlayOpacity: Double
    let onFinished: () -> Void

    @State private var frame: CGRect = .zero
    @State private var scrim: Double = 0
    @State private var photoOpacity: Double = 1
    @State private var subjectOpacity: Double = 1
    @State private var glow: Double = 0
    @State private var scan: CGFloat = 0          // band position 0…1
    @State private var bandOpacity: Double = 0
    @State private var revealed: CGFloat = 0     // outline revealed down to here
    @State private var latchedReady = false
    @State private var latchedCutout: UIImage?
    @State private var started = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: CGRect {
        let fit = ImageContentMapper.contentRect(
            contentSize: request.image.size, in: viewfinder.size, mode: .fit
        )
        return fit.offsetBy(dx: viewfinder.minX, dy: viewfinder.minY)
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            ZStack {
                // Hides the feed while the camera settles.
                Rectangle()
                    .fill(Color.black.opacity(scrim))
                    .frame(width: viewfinder.width, height: viewfinder.height)
                    .position(x: viewfinder.midX - origin.x, y: viewfinder.midY - origin.y)

                photo
                    .frame(width: max(frame.width, 1), height: max(frame.height, 1))
                    .clipped()
                    .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            latchedCutout = cutout
            latchedReady = isReady
            run()
        }
        // Removed early (replaced by a newer switch, cover dismissed): still
        // hand back, so the overlay is never left hidden.
        .onDisappear(perform: finish)
        .onChange(of: isReady) { _, ready in latchedReady = ready }
        .onChange(of: cutout) { _, image in latchedCutout = image }
    }

    private var photo: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .top) {
                // The background is cut away behind the scan line, leaving
                // the person over the dimmed feed. Without a cutout there's
                // nothing to leave behind, so the photo stays whole.
                Image(uiImage: request.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: h)
                    .opacity(photoOpacity)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: latchedCutout == nil ? h : h * (1 - revealed))
                    }

                if let cutout = latchedCutout {
                    // Outline glow, revealed top-down behind the scan band.
                    Image(uiImage: cutout)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: h)
                        .opacity(subjectOpacity)
                        .shadow(color: .white.opacity(0.9 * glow), radius: 8)
                        .shadow(color: .white.opacity(0.4 * glow), radius: 22)
                        .mask(alignment: .top) {
                            Rectangle().frame(height: h * revealed)
                        }
                    // The un-glowing remainder below the band.
                    Image(uiImage: cutout)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: h)
                        .opacity(subjectOpacity)
                        .mask(alignment: .bottom) {
                            Rectangle().frame(height: h * (1 - revealed))
                        }
                }

                // Scan band: soft light with a crisp leading edge.
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [.white.opacity(0), .white.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    )
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                        .shadow(color: .white, radius: 6)
                        .shadow(color: .white.opacity(0.6), radius: 14)
                }
                .frame(height: 110)
                .offset(y: h * scan - 110)   // leading line sits at h * scan
                .opacity(bandOpacity)
                .blendMode(.plusLighter)
            }
            .frame(width: geo.size.width, height: h, alignment: .top)
            .clipped()
        }
    }

    private func run() {
        guard !started else { return }
        started = true
        #if DEBUG
        print("[scan] start inPlace=\(request.inPlace) ready=\(isReady) cutout=\(cutout != nil) reduceMotion=\(reduceMotion) target=\(target)")
        #endif
        if request.inPlace || reduceMotion {
            frame = target
            photoOpacity = 0
            withAnimation(.easeOut(duration: 0.25)) {
                photoOpacity = 1
                scrim = 0.6
            }
        } else {
            frame = request.from
            withAnimation(.spring(duration: RecreateMorphTiming.flight, bounce: 0)) {
                frame = target
            }
            withAnimation(.easeOut(duration: RecreateMorphTiming.flight)) {
                scrim = 0.6
            }
        }

        Task { @MainActor in
            let began = Date()
            try? await Task.sleep(for: .seconds(RecreateMorphTiming.scanStart))

            // Scan passes until ready (≥ 1 pass, ≤ maxHold).
            if reduceMotion {
                // Fades only: background out, outline in.
                withAnimation(.easeInOut(duration: 0.4)) {
                    glow = 1
                    if latchedCutout != nil { photoOpacity = 0 }
                }
                repeat {
                    try? await Task.sleep(for: .seconds(RecreateMorphTiming.scanPass))
                } while !latchedReady
                    && Date().timeIntervalSince(began) < RecreateMorphTiming.maxHold
            } else {
            withAnimation(.easeOut(duration: 0.15)) { bandOpacity = 1; glow = 1 }
            repeat {
                scan = 0
                // Line and cut edge share one curve so the background is
                // removed exactly where the line has passed.
                withAnimation(.easeInOut(duration: RecreateMorphTiming.scanPass)) {
                    scan = 1
                    revealed = 1
                }
                try? await Task.sleep(for: .seconds(RecreateMorphTiming.scanPass))
            } while !latchedReady
                && Date().timeIntervalSince(began) < RecreateMorphTiming.maxHold
            }

            // Lift: band, background and scrim go; the person stays, glowing.
            let hasSubject = latchedCutout != nil
            withAnimation(.easeOut(duration: RecreateMorphTiming.lift)) {
                bandOpacity = 0
                scrim = 0
                photoOpacity = hasSubject ? 0 : 0.6
            }
            try? await Task.sleep(for: .seconds(RecreateMorphTiming.lift))

            // Settle into the overlay.
            withAnimation(.easeInOut(duration: RecreateMorphTiming.settle)) {
                glow = 0
                subjectOpacity = overlayOpacity
                if !hasSubject { photoOpacity = overlayOpacity }
            }
            try? await Task.sleep(for: .seconds(RecreateMorphTiming.settle))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        #if DEBUG
        print("[scan] finish")
        #endif
        onFinished()
    }
}
