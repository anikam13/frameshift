import SwiftUI

/// First-launch welcome (D-34). Shown once, over the gallery, while the
/// camera starts underneath. Settings → Replay Tutorial shows it again.
///
/// Background: a "reference wall" — the bundled sample photos in three
/// tilted columns drifting slowly in alternating directions (the scrolling
/// collage photo apps use on their welcome screens), under a faint
/// rule-of-thirds grid so it reads as a viewfinder. It falls off to black
/// behind the title and shutter. Frame-driven by `TimelineView(.animation)`
/// with small pre-scaled thumbnails, so it stays cheap.
///
/// Get started is the real shutter: press → haptic, the wall falls away, and
/// the shutter's disc grows to fill the screen in the gallery's background
/// colour, then dissolves into the gallery. Reduce Motion: the wall holds
/// still and the hand-off is a cross-fade.
enum Welcome {
    static let doneKey = "frameshift.welcome.done"
}

struct WelcomeView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    @State private var showTitle = false
    @State private var showWall = false
    @State private var isPressed = false
    @State private var leaving = false
    @State private var discScale: CGFloat = 0
    @State private var finished = false
    @State private var coverTarget: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shutterCenter = CGPoint(x: size.width / 2, y: size.height - geo.safeAreaInsets.bottom - 76)
            ZStack {
                Color.black

                ReferenceWall(paused: reduceMotion || leaving, start: appeared)
                    .opacity(leaving ? 0 : (showWall ? 1 : 0))
                    .scaleEffect(leaving ? 1.06 : 1)
                    .animation(.easeOut(duration: leaving ? 0.3 : 1.0), value: showWall)
                    .animation(.easeOut(duration: 0.3), value: leaving)

                // Fall-off to black for the title and shutter.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.35), location: 0),
                        .init(color: .black.opacity(0.15), location: 0.25),
                        .init(color: .black.opacity(0.85), location: 0.55),
                        .init(color: .black, location: 0.68),
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                title
                    .position(x: size.width / 2, y: size.height * 0.68)

                shutter
                    .position(shutterCenter)

                // The shutter's disc becomes the gallery's background.
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 66, height: 66)
                    .scaleEffect(discScale)
                    .position(shutterCenter)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .onAppear {
                appeared = Date()
                showWall = true
                withAnimation(.easeOut(duration: 0.6).delay(0.35)) { showTitle = true }
            }
            .onAppear { coverTarget = coverScale(for: size, from: shutterCenter) }
            .onChange(of: size) { _, _ in coverTarget = coverScale(for: size, from: shutterCenter) }
        }
        .statusBarHidden(true)
    }

    // MARK: Title

    private var title: some View {
        VStack(spacing: 10) {
            Text("Welcome to")
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("FrameShift")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
            Text("Press the shutter to get started")
                .font(.system(.subheadline))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .opacity(showTitle && !leaving ? 1 : 0)
        .offset(y: showTitle ? 0 : 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Shutter

    private var shutter: some View {
        ZStack {
            // Soft invitation pulse.
            if !reduceMotion && !leaving {
                PulseRing()
            }
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: 78, height: 78)
            Circle()
                .fill(Color.white)
                .frame(width: 66, height: 66)
                .scaleEffect(isPressed ? 0.88 : 1)
                .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        // The disc takes over from the inner fill on press.
        .opacity(showTitle && !leaving ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: leaving)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed, !leaving else { return }
                    isPressed = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                .onEnded { _ in
                    isPressed = false
                    getStarted()
                }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Get started")
        .accessibilityAction { getStarted() }
    }

    private func coverScale(for size: CGSize, from center: CGPoint) -> CGFloat {
        let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0),
                       CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
        let far = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1000
        return (far + 20) / 33
    }

    private func getStarted() {
        guard !leaving else { return }
        leaving = true
        if reduceMotion {
            finish()
            return
        }
        discScale = 0.88   // where the pressed inner fill was
        withAnimation(.spring(duration: 0.55, bounce: 0)) { discScale = coverTarget }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

private struct PulseRing: View {
    @State private var on = false
    var body: some View {
        Circle()
            .stroke(Color.white.opacity(on ? 0 : 0.35), lineWidth: 1.5)
            .frame(width: 78, height: 78)
            .scaleEffect(on ? 1.45 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(1.2)) {
                    on = true
                }
            }
    }
}

/// Three tilted columns of the sample references, scrolling in alternating
/// directions, with a faint thirds grid on top.
private struct ReferenceWall: View {
    let paused: Bool
    let start: Date

    private static let thumbnails: [UIImage] = SampleReferencePack.assetNames.compactMap {
        UIImage(named: $0)?.preparingThumbnail(of: CGSize(width: 260, height: 364))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let spacing: CGFloat = 10
            let colW = (w * 1.3 - spacing * 2) / 3
            let tileH = colW * 1.4
            let images = Self.thumbnails
            TimelineView(.animation(paused: paused)) { context in
                let t = paused ? 0 : context.date.timeIntervalSince(start)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        column(images: rotated(images, by: col * 3), tileW: colW, tileH: tileH,
                               spacing: spacing, offset: scroll(t: t, col: col, tileH: tileH, spacing: spacing, count: images.count))
                    }
                }
                .frame(width: w * 1.3, height: h * 1.3, alignment: .top)
                .clipped()
                .rotationEffect(.degrees(-8))
                .position(x: w / 2, y: h / 2)
            }
            ThirdsGrid()
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rotated(_ a: [UIImage], by n: Int) -> [UIImage] {
        guard !a.isEmpty else { return a }
        let k = n % a.count
        return Array(a[k...] + a[..<k])
    }

    /// Alternating directions, slightly different speeds (pt/s).
    private func scroll(t: Double, col: Int, tileH: CGFloat, spacing: CGFloat, count: Int) -> CGFloat {
        let loop = CGFloat(max(count, 1)) * (tileH + spacing)
        let speed: CGFloat = [14, 11, 16][col]
        let base = CGFloat(col) * tileH * 0.45
        let raw = (base + speed * CGFloat(t)).truncatingRemainder(dividingBy: loop)
        return col == 1 ? raw - loop : -raw
    }

    private func column(images: [UIImage], tileW: CGFloat, tileH: CGFloat,
                        spacing: CGFloat, offset: CGFloat) -> some View {
        // Two copies stacked so the loop is seamless.
        VStack(spacing: spacing) {
            ForEach(0..<(images.count * 2), id: \.self) { i in
                Image(uiImage: images[i % images.count])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tileW, height: tileH)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .offset(y: offset)
        .frame(width: tileW, alignment: .top)
    }
}

private struct ThirdsGrid: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 1...2 {
            let x = r.width * CGFloat(i) / 3, y = r.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: r.height))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: r.width, y: y))
        }
        return p
    }
}
