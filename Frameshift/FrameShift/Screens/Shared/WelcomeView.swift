import SwiftUI
import UIKit

/// First-launch welcome (D-34). Shown once, over the gallery, while the
/// camera starts underneath. Settings → Replay Tutorial shows it again.
///
/// Background: a "reference wall" — the bundled sample photos in three
/// tilted columns drifting slowly in alternating directions (the scrolling
/// collage photo apps use on their welcome screens), under a faint
/// rule-of-thirds grid so it reads as a viewfinder. It falls off to black
/// behind the title and shutter.
///
/// Get started is the real shutter: press → haptic, and the shutter's disc
/// grows to fill the screen in the gallery's background colour, then
/// dissolves into the gallery. Reduce Motion: the wall holds still and the
/// hand-off is a cross-fade.
///
/// The wall drift and the disc are Core Animation, run by the render
/// server: first launch keeps the main thread busy (sample import, camera
/// start, the gallery underneath), and frame-driven SwiftUI versions of
/// both stuttered whenever it was.
enum Welcome {
    static let doneKey = "frameshift.welcome.done"
}

struct WelcomeView: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTitle = false
    /// Decoded off the main thread so the first frames never wait on them.
    @State private var thumbnails: [UIImage] = []
    @State private var isPressed = false
    @State private var leaving = false
    /// The disc fills the screen: everything under it is dropped and the
    /// disc fades into the gallery.
    @State private var covered = false
    @State private var finished = false
    /// Warmed on appear: a cold generator stalls the frame it first fires in.
    @State private var haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let shutterCenter = CGPoint(x: size.width / 2, y: size.height - geo.safeAreaInsets.bottom - 76)
            ZStack {
                if !covered {
                    Color.black

                    ReferenceWallView(images: thumbnails, animated: !reduceMotion)

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
                }

                // The shutter's disc becomes the gallery's background.
                CoverDiscView(center: shutterCenter, startRadius: 33 * 0.88, play: leaving && !reduceMotion) {
                    // Fully covered: drop the rest (invisible under the
                    // disc) while the disc fades into the gallery.
                    covered = true
                } onFaded: {
                    finish()
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .allowsHitTesting(!covered)
            .onAppear {
                haptic.prepare()
                withAnimation(.easeOut(duration: 0.6).delay(0.15)) { showTitle = true }
            }
            .task {
                thumbnails = await ReferenceWallView.loadThumbnails()
            }
        }
        .statusBarHidden(true)
    }

    // MARK: Title

    private var title: some View {
        VStack(spacing: 0) {
            Text("Welcome to")
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text("FrameShift")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .opacity(showTitle && !leaving ? 1 : 0)
        .offset(y: showTitle ? 0 : 12)
        .animation(.easeOut(duration: 0.12), value: leaving)
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
                // Fires on touch-down, like the camera's shutter.
                .onChanged { _ in
                    guard !isPressed, !leaving else { return }
                    isPressed = true
                    haptic.impactOccurred()
                    getStarted()
                }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Get started")
        .accessibilityAction { getStarted() }
    }

    private func getStarted() {
        guard !leaving else { return }
        leaving = true
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.25)) { covered = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.25))
                finish()
            }
        }
    }

    /// The parent removes this view only once it's invisible, so the
    /// gallery's update for "welcome done" never lands mid-animation.
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

// MARK: - Cover disc

/// The shutter's fill growing to cover the screen, then fading out. Both
/// steps are Core Animation so they stay smooth however busy the app is.
private struct CoverDiscView: UIViewRepresentable {
    let center: CGPoint
    let startRadius: CGFloat
    let play: Bool
    let onCovered: () -> Void
    let onFaded: () -> Void

    func makeUIView(context: Context) -> DiscView { DiscView() }

    func updateUIView(_ view: DiscView, context: Context) {
        guard play else { return }
        view.play(center: center, startRadius: startRadius, onCovered: onCovered, onFaded: onFaded)
    }

    final class DiscView: UIView {
        private let disc = CAShapeLayer()
        private var played = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            disc.isHidden = true
            layer.addSublayer(disc)
        }

        required init?(coder: NSCoder) { fatalError() }

        func play(center: CGPoint, startRadius: CGFloat,
                  onCovered: @escaping () -> Void, onFaded: @escaping () -> Void) {
            guard !played, bounds.width > 0 else { return }
            played = true

            // Radius that reaches the farthest corner.
            let corners = [CGPoint.zero, CGPoint(x: bounds.width, y: 0),
                           CGPoint(x: 0, y: bounds.height), CGPoint(x: bounds.width, y: bounds.height)]
            let radius = (corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1000) + 4

            // Full-size circle scaled down, so it's crisp when it lands.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            disc.frame = CGRect(x: center.x - radius, y: center.y - radius,
                                width: radius * 2, height: radius * 2)
            disc.path = UIBezierPath(ovalIn: disc.bounds).cgPath
            disc.fillColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
            disc.isHidden = false
            CATransaction.commit()

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = startRadius / radius
            grow.toValue = 1
            grow.duration = 0.42
            // Quick start, soft landing: responsive under the finger.
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1)

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                onCovered()
                self?.fadeOut(onFaded)
            }
            disc.add(grow, forKey: "grow")
            CATransaction.commit()
        }

        private func fadeOut(_ done: @escaping () -> Void) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.24
            // Let SwiftUI drop what's under the disc before it thins out.
            fade.beginTime = CACurrentMediaTime() + 0.03
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setCompletionBlock(done)
            disc.opacity = 0
            disc.add(fade, forKey: "fade")
            CATransaction.commit()
        }
    }
}

// MARK: - Reference wall

/// Three tilted columns of the sample references, scrolling in alternating
/// directions, with a faint thirds grid on top.
private struct ReferenceWallView: UIViewRepresentable {
    let images: [UIImage]
    let animated: Bool

    static func loadThumbnails() async -> [UIImage] {
        await Task.detached(priority: .userInitiated) {
            SampleReferencePack.assetNames.compactMap { name -> UIImage? in
                // Force the decode here, not on the main thread at first draw.
                UIImage(named: name)?
                    .preparingThumbnail(of: CGSize(width: 260, height: 364))?
                    .preparingForDisplay()
            }
        }.value
    }

    func makeUIView(context: Context) -> WallView { WallView() }

    func updateUIView(_ view: WallView, context: Context) {
        view.configure(images: images, animated: animated)
    }

    final class WallView: UIView {
        private let wall = CALayer()
        private let grid = CAShapeLayer()
        private var images: [UIImage] = []
        private var animated = true
        private var builtSize: CGSize = .zero
        private var hasFadedIn = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            clipsToBounds = true
            wall.masksToBounds = true
            layer.addSublayer(wall)
            grid.strokeColor = UIColor.white.withAlphaComponent(0.14).cgColor
            grid.fillColor = nil
            grid.lineWidth = 0.5
            layer.addSublayer(grid)
            alpha = 0
        }

        required init?(coder: NSCoder) { fatalError() }

        func configure(images: [UIImage], animated: Bool) {
            guard !images.isEmpty, images.count != self.images.count || animated != self.animated else { return }
            self.images = images
            self.animated = animated
            builtSize = .zero
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !images.isEmpty, bounds.size != builtSize, bounds.width > 0 else { return }
            builtSize = bounds.size
            build()
            if !hasFadedIn {
                hasFadedIn = true
                transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
                UIView.animate(withDuration: 1.2, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                    self.alpha = 1
                    self.transform = .identity
                }
            }
        }

        private func build() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            defer { CATransaction.commit() }

            wall.sublayers?.forEach { $0.removeFromSuperlayer() }
            let w = bounds.width, h = bounds.height
            let spacing: CGFloat = 10
            let wallSize = CGSize(width: w * 1.3, height: h * 1.3)
            let colW = (wallSize.width - spacing * 2) / 3
            let tileH = colW * 1.4
            let loop = CGFloat(images.count) * (tileH + spacing)

            wall.bounds = CGRect(origin: .zero, size: wallSize)
            wall.position = CGPoint(x: w / 2, y: h / 2)
            wall.setAffineTransform(CGAffineTransform(rotationAngle: -8 * .pi / 180))

            let speeds: [CGFloat] = [14, 11, 16]   // pt/s
            for col in 0..<3 {
                let column = CALayer()
                column.frame = CGRect(x: CGFloat(col) * (colW + spacing), y: 0,
                                      width: colW, height: loop * 2)
                let ordered = rotated(images, by: col * 3)
                // Two copies stacked so the loop is seamless.
                for i in 0..<(ordered.count * 2) {
                    let tile = CALayer()
                    tile.frame = CGRect(x: 0, y: CGFloat(i) * (tileH + spacing), width: colW, height: tileH)
                    tile.contents = ordered[i % ordered.count].cgImage
                    tile.contentsGravity = .resizeAspectFill
                    tile.masksToBounds = true
                    tile.cornerRadius = 14
                    tile.cornerCurve = .continuous
                    column.addSublayer(tile)
                }
                wall.addSublayer(column)

                // Columns 0 and 2 drift up, column 1 down; staggered starts.
                let up = col != 1
                let start = CGFloat(col) * tileH * 0.45
                // Keep the column covering the wall for the whole loop.
                let from = up ? -start : -loop - start
                let to = up ? from - loop : from + loop
                column.setAffineTransform(CGAffineTransform(translationX: 0, y: from))
                guard animated else { continue }
                let drift = CABasicAnimation(keyPath: "transform.translation.y")
                drift.fromValue = from
                drift.toValue = to
                drift.duration = CFTimeInterval(loop / speeds[col])
                drift.repeatCount = .infinity
                drift.timingFunction = CAMediaTimingFunction(name: .linear)
                drift.isRemovedOnCompletion = false
                column.add(drift, forKey: "drift")
            }

            let path = UIBezierPath()
            for i in 1...2 {
                let x = w * CGFloat(i) / 3, y = h * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y))
            }
            grid.frame = bounds
            grid.path = path.cgPath
        }

        private func rotated(_ a: [UIImage], by n: Int) -> [UIImage] {
            guard !a.isEmpty else { return a }
            let k = n % a.count
            return Array(a[k...] + a[..<k])
        }
    }
}
