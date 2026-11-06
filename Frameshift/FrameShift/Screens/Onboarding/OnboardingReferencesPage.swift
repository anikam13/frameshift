import SwiftUI
import UIKit

/// Coach loop on the photo picked in step 1. Ghost is that reference;
/// the live scene is the garden still, which never moves.
struct OnboardingReferencesPage: View {
    var imageName: String
    var isActive: Bool = true

    var body: some View {
        ViewfinderCoachDemo(imageName: imageName, isActive: isActive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum CoachBeat: Equatable {
    case moveRight, moveLeft, hold, snapshot

    var label: String {
        switch self {
        case .moveRight: return "Move right"
        case .moveLeft:  return "Move left"
        case .hold:      return "Hold"
        case .snapshot:  return "Snapshot"
        }
    }
}

/// Wide live still stays put. The reference ghost slides with the finder
/// until shoulder height and span land on the subject.
private struct ViewfinderCoachDemo: View {
    var imageName: String
    var isActive: Bool

    @State private var beat: CoachBeat = .moveRight
    @State private var panX: CGFloat = -0.13
    @State private var faceInCircle = false
    @State private var flash = 0.0
    @State private var ghostOpacity: Double = 0.52
    @State private var still: UIImage?
    @State private var cutout: UIImage?
    @State private var cutoutFailed = false
    @State private var refSpec: ShotSpec?
    @State private var liveSpec: ShotSpec?

    private let alignedX: CGFloat = 0
    private let ghostRestingOpacity: Double = 0.52
    private let finderCorner: CGFloat = 16
    private let liveStillName = "OnboardingLiveStill"

    private var isReady: Bool { still != nil && (cutout != nil || cutoutFailed) }

    var body: some View {
        VStack(spacing: 0) {
            headline
                .padding(.top, 32)
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            GeometryReader { geo in
                let cardWidth = geo.size.width * 0.52
                let idealHeight = cardWidth * 4.0 / 3.0
                let bleed: CGFloat = 72
                let cardHeight = min(idealHeight, max(geo.size.height - bleed * 2, geo.size.height * 0.76))
                let stage = CGSize(
                    width: geo.size.width,
                    height: min(geo.size.height, cardHeight + bleed * 2)
                )
                let match = OverlayMatch.resolve(
                    ref: refSpec,
                    live: liveSpec,
                    stage: stage,
                    finder: CGSize(width: cardWidth, height: cardHeight)
                )
                let finder = finderRect(match: match, stage: stage)
                let fadeStop = stage.height > 0 ? min(0.16, (bleed * 0.9) / stage.height) : 0.12
                ZStack {
                    subjectBackdrop(stage: stage)

                    if isReady {
                        dimmer(stage: stage, finder: finder)
                    }

                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0), location: fadeStop),
                            .init(color: .black.opacity(0), location: 1 - fadeStop),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: stage.width, height: stage.height)
                    .allowsHitTesting(false)

                    if isReady {
                        referenceGhost(finder: finder, match: match)
                        finderChrome(finder: finder, match: match)
                    }

                    coachingChip
                        .opacity(isReady ? 1 : 0)
                        .position(
                            x: stage.width / 2,
                            y: max(34, finder.minY - 56)
                        )
                        .allowsHitTesting(false)
                }
                .animation(nil, value: isReady)
                .frame(width: stage.width, height: stage.height)
                .clipped()
                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            }

            Spacer(minLength: 16)
        }
        .task(id: imageName) {
            await loadAssets()
        }
        .task(id: isActive) {
            guard isActive else { return }
            await runLoop()
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text("Step 2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.cameraYellow)
                .textCase(.uppercase)
                .tracking(1.2)
            Text("Let FrameShift coach you through your shot")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
        }
        .multilineTextAlignment(.center)
    }

    private var coachingChip: some View {
        Text(beat.label)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(faceInCircle ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                (faceInCircle ? Color.cameraYellow : Color.black.opacity(0.72)),
                in: Capsule()
            )
            .animation(.easeOut(duration: 0.18), value: faceInCircle)
            .animation(nil, value: beat)
    }

    private func finderRect(match: OverlayMatch, stage: CGSize) -> CGRect {
        var rect = CGRect(origin: match.alignedOrigin, size: match.finderSize)
        rect.origin.x += panX * stage.width
        let topPad: CGFloat = 62
        let bottomPad: CGFloat = 12
        let maxY = stage.height - rect.height - bottomPad
        if maxY >= topPad {
            rect.origin.y = min(max(rect.origin.y, topPad), maxY)
        }
        return rect
    }

    private func subjectBackdrop(stage: CGSize) -> some View {
        Group {
            if let still {
                Image(uiImage: still)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .frame(width: stage.width, height: stage.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func dimmer(stage: CGSize, finder: CGRect) -> some View {
        Color.black.opacity(0.62)
            .frame(width: stage.width, height: stage.height)
            .reverseMask {
                RoundedRectangle(cornerRadius: finderCorner, style: .continuous)
                    .frame(width: finder.width, height: finder.height)
                    .position(x: finder.midX, y: finder.midY)
            }
            .allowsHitTesting(false)
    }

    private func referenceGhost(finder: CGRect, match: OverlayMatch) -> some View {
        Group {
            if let cutout {
                Image(uiImage: cutout)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else if cutoutFailed {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
        }
        .frame(width: finder.width, height: finder.height)
        .scaleEffect(
            match.ghostScale,
            anchor: UnitPoint(x: match.anchorUnit.x, y: match.anchorUnit.y)
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: finderCorner, style: .continuous))
        .opacity(ghostOpacity)
        .position(x: finder.midX, y: finder.midY)
        .allowsHitTesting(false)
    }

    private func finderChrome(finder: CGRect, match: OverlayMatch) -> some View {
        let headCenter = CGPoint(
            x: finder.minX + finder.width * match.headUnit.x,
            y: finder.minY + finder.height * match.headUnit.y
        )
        let headR = match.headRadius

        return ZStack {
            RoundedRectangle(cornerRadius: finderCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.75)
                .frame(width: finder.width, height: finder.height)
                .position(x: finder.midX, y: finder.midY)

            FinderGrid()
                .frame(width: finder.width, height: finder.height)
                .clipShape(RoundedRectangle(cornerRadius: finderCorner, style: .continuous))
                .position(x: finder.midX, y: finder.midY)

            Circle()
                .stroke(
                    faceInCircle ? Color.cameraYellow : Color.white,
                    style: StrokeStyle(lineWidth: faceInCircle ? 3.5 : 2.25, lineCap: .round)
                )
                .frame(width: headR * 2, height: headR * 2)
                .position(headCenter)
                .shadow(color: faceInCircle ? Color.cameraYellow.opacity(0.85) : .clear, radius: 8)

            if faceInCircle {
                Circle()
                    .fill(Color.cameraYellow.opacity(0.16))
                    .frame(width: headR * 2, height: headR * 2)
                    .position(headCenter)
                    .allowsHitTesting(false)
            }

            RoundedRectangle(cornerRadius: finderCorner, style: .continuous)
                .fill(.white.opacity(flash))
                .frame(width: finder.width, height: finder.height)
                .position(x: finder.midX, y: finder.midY)
                .allowsHitTesting(false)
        }
    }

    @MainActor
    private func loadAssets() async {
        still = nil
        cutout = nil
        cutoutFailed = false
        refSpec = nil
        liveSpec = nil

        guard let liveRaw = UIImage(named: liveStillName) else {
            cutoutFailed = true
            return
        }
        let live = liveRaw.upright()
        still = Self.screenScaled(live)

        guard let refRaw = UIImage(named: imageName) else {
            cutoutFailed = true
            return
        }
        let ref = refRaw.upright()

        async let cutoutWork = PersonSegmenter().cutout(from: ref, quality: .accurate)
        async let refWork = VisionAnalyzer().analyze(image: ref)
        async let liveWork = VisionAnalyzer().analyze(image: live)

        let (cut, analyzedRef, analyzedLive) = await (cutoutWork, refWork, liveWork)
        guard !Task.isCancelled else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let cut {
                cutout = Self.screenScaled(cut)
            } else {
                cutoutFailed = true
            }
            refSpec = analyzedRef
            liveSpec = analyzedLive
        }
    }

    private static func screenScaled(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        return UIImage(cgImage: cg, scale: UIScreen.main.scale, orientation: image.imageOrientation)
    }

    @MainActor
    private func animatePan(
        to target: CGFloat,
        duration: TimeInterval,
        easing: (CGFloat) -> CGFloat,
        onTick: ((CGFloat) -> Void)? = nil
    ) async {
        let from = panX
        let start = CACurrentMediaTime()
        while !Task.isCancelled {
            let t = min((CACurrentMediaTime() - start) / duration, 1)
            let x = from + (target - from) * easing(CGFloat(t))
            panX = x
            onTick?(x)
            if t >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }
        if !Task.isCancelled {
            panX = target
            onTick?(target)
        }
    }

    private static func easeInOutCubic(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    @MainActor
    private func runLoop() async {
        while !isReady && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(40))
        }
        guard !Task.isCancelled else { return }

        let startX: CGFloat = -0.13
        let overshootX: CGFloat = 0.13

        while !Task.isCancelled {
            flash = 0
            faceInCircle = false
            ghostOpacity = ghostRestingOpacity
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                panX = startX
                beat = .moveRight
            }

            try? await Task.sleep(for: .milliseconds(680))
            guard !Task.isCancelled else { return }

            await animatePan(to: overshootX, duration: 1.55, easing: Self.easeInOutCubic) { x in
                if beat == .moveRight, x >= alignedX {
                    beat = .moveLeft
                }
            }
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            await animatePan(to: alignedX, duration: 1.7, easing: Self.easeInOutCubic) { x in
                if beat == .moveLeft, x <= 0.006 {
                    beat = .hold
                    withAnimation(.easeOut(duration: 0.22)) {
                        faceInCircle = true
                    }
                    withAnimation(.timingCurve(0.22, 0.08, 0.18, 1.0, duration: 1.05)) {
                        ghostOpacity = 0
                    }
                }
            }
            guard !Task.isCancelled else { return }
            if beat != .hold {
                beat = .hold
                faceInCircle = true
            }

            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }

            beat = .snapshot
            withAnimation(.easeOut(duration: 0.08)) { flash = 0.78 }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            try? await Task.sleep(for: .milliseconds(1100))
        }
    }
}

/// Scale the reference so body height and shoulder span match the live
/// subject, then park the scaled ghost head on the live face when pan is 0.
/// The live still never moves.
private struct OverlayMatch {
    var ghostScale: CGFloat
    var anchorUnit: CGPoint
    var headUnit: CGPoint
    var headRadius: CGFloat
    var finderSize: CGSize
    var alignedOrigin: CGPoint

    static func finderSize(in stage: CGSize) -> CGSize {
        var width = stage.width * 0.70
        var height = width * 4.0 / 3.0
        let maxH = stage.height * 0.92
        if height > maxH {
            height = maxH
            width = height * 3.0 / 4.0
        }
        return CGSize(width: width, height: height)
    }

    static func resolve(
        ref: ShotSpec?,
        live: ShotSpec?,
        stage: CGSize,
        finder: CGSize? = nil
    ) -> OverlayMatch {
        let size = finder ?? finderSize(in: stage)
        let fallbackOrigin = CGPoint(
            x: (stage.width - size.width) / 2,
            y: (stage.height - size.height) / 2
        )
        guard let ref else {
            return OverlayMatch(
                ghostScale: 1,
                anchorUnit: CGPoint(x: 0.5, y: 0.38),
                headUnit: CGPoint(x: 0.5, y: 0.32),
                headRadius: size.width * 0.13,
                finderSize: size,
                alignedOrigin: fallbackOrigin
            )
        }

        let refPose = PoseAnchor.resolve(spec: ref, in: size)
        let refHead = ImageContentMapper.point(
            CGPoint(x: ref.headCenterX, y: ref.headCenterY),
            contentSize: ref.referenceSize,
            in: size,
            mode: .fill
        )
        let refHeadRadius = ImageContentMapper.scalar(
            ref.headRadius,
            contentSize: ref.referenceSize,
            in: size,
            mode: .fill
        )
        let anchorUnit = CGPoint(
            x: size.width > 0 ? refPose.mid.x / size.width : 0.5,
            y: size.height > 0 ? refPose.mid.y / size.height : 0.38
        )

        guard let live else {
            let headUnit = CGPoint(
                x: size.width > 0 ? refHead.x / size.width : 0.5,
                y: size.height > 0 ? refHead.y / size.height : 0.32
            )
            return OverlayMatch(
                ghostScale: 1.15,
                anchorUnit: anchorUnit,
                headUnit: headUnit,
                headRadius: max(refHeadRadius, 8),
                finderSize: size,
                alignedOrigin: fallbackOrigin
            )
        }

        let livePose = PoseAnchor.resolve(spec: live, in: stage)
        let liveHead = ImageContentMapper.point(
            CGPoint(x: live.headCenterX, y: live.headCenterY),
            contentSize: live.referenceSize,
            in: stage,
            mode: .fill
        )
        let liveHeadRadius = ImageContentMapper.scalar(
            live.headRadius,
            contentSize: live.referenceSize,
            in: stage,
            mode: .fill
        )
        let heightScale = refPose.height > 1 ? livePose.height / refPose.height : 1.2
        let spanScale = refPose.span > 1 ? livePose.span / refPose.span : heightScale
        let bodyScale = (heightScale + spanScale) / 2
        let scale = min(max(bodyScale * 1.03, 0.92), 1.95)

        // Scale is around the shoulders, so the drawn head moves. Park that
        // scaled head on the live face so the circle and ghost agree.
        let scaledRefHead = CGPoint(
            x: refPose.mid.x + (refHead.x - refPose.mid.x) * scale,
            y: refPose.mid.y + (refHead.y - refPose.mid.y) * scale
        )
        let origin = CGPoint(
            x: liveHead.x - scaledRefHead.x,
            y: liveHead.y - scaledRefHead.y
        )
        let headUnit = CGPoint(
            x: size.width > 0 ? scaledRefHead.x / size.width : 0.5,
            y: size.height > 0 ? scaledRefHead.y / size.height : 0.32
        )
        return OverlayMatch(
            ghostScale: scale,
            anchorUnit: anchorUnit,
            headUnit: headUnit,
            headRadius: max(liveHeadRadius, 8),
            finderSize: size,
            alignedOrigin: origin
        )
    }
}

private struct PoseAnchor {
    var mid: CGPoint
    var span: CGFloat
    var height: CGFloat

    static func resolve(spec: ShotSpec, in container: CGSize) -> PoseAnchor {
        let left = ImageContentMapper.point(
            spec.leftShoulder,
            contentSize: spec.referenceSize,
            in: container,
            mode: .fill
        )
        let right = ImageContentMapper.point(
            spec.rightShoulder,
            contentSize: spec.referenceSize,
            in: container,
            mode: .fill
        )
        let span = hypot(right.x - left.x, right.y - left.y)
        let shouldersValid = span > 8 && spec.leftShoulder != .zero && spec.rightShoulder != .zero
        let mid: CGPoint
        if shouldersValid {
            mid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        } else {
            mid = ImageContentMapper.point(
                CGPoint(x: spec.headCenterX, y: spec.headCenterY + spec.headRadius),
                contentSize: spec.referenceSize,
                in: container,
                mode: .fill
            )
        }
        let body = ImageContentMapper.rect(
            CGRect(
                x: spec.subjectLeft,
                y: spec.subjectTop,
                width: spec.subjectWidth,
                height: spec.subjectHeight
            ),
            contentSize: spec.referenceSize,
            in: container,
            mode: .fill
        )
        return PoseAnchor(
            mid: mid,
            span: max(span, 1),
            height: max(body.height, 1)
        )
    }
}

private struct FinderGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let style = StrokeStyle(lineWidth: 0.5)
            let color = GraphicsContext.Shading.color(.gridLine)
            for fraction in [1.0 / 3.0, 2.0 / 3.0] as [CGFloat] {
                var h = Path()
                h.move(to: CGPoint(x: 0, y: size.height * fraction))
                h.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                ctx.stroke(h, with: color, style: style)

                var v = Path()
                v.move(to: CGPoint(x: size.width * fraction, y: 0))
                v.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                ctx.stroke(v, with: color, style: style)
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            Rectangle()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        )
    }
}

#Preview("Step 1") {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingChoosePage(selectedAsset: .constant(""))
    }
    .preferredColorScheme(.dark)
}

#Preview("Step 2") {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingReferencesPage(imageName: OnboardingReferenceChoices.featured)
    }
    .preferredColorScheme(.dark)
}
