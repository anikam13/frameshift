import SwiftUI

/// In-app first-use tours (D-27; Paper "Explore tour" / "Camera tour", V2).
/// Replaces the onboarding carousel: short spotlight cards anchored to the
/// real controls, skippable, shown once per surface. Settings → Replay
/// Tutorial resets them.
enum FirstUseTour {
    static let exploreDoneKey = "frameshift.tour.explore.done"
    static let cameraDoneKey = "frameshift.tour.camera.done"

    static func reset() {
        UserDefaults.standard.set(false, forKey: exploreDoneKey)
        UserDefaults.standard.set(false, forKey: cameraDoneKey)
    }

    struct Step {
        let target: TourTarget
        let area: String
        let title: String
        let body: String
        var nextTitle = "Next"
        /// Draw a ring around the target (round toolbar buttons).
        var ringed = false
    }

    static let explore: [Step] = [
        Step(target: .exploreFirstTile, area: "Explore",
             title: "Start with a photo",
             body: "Choose a sample you’d like to recreate."),
        Step(target: .exploreImport, area: "Explore",
             title: "Use your own photo",
             body: "Tap + to import a photo. Find it later in Yours.",
             nextTitle: "Got It", ringed: true),
    ]

    static let camera: [Step] = [
        Step(target: .cameraOverlay, area: "Camera",
             title: "Person-only overlay",
             body: "Only the person is overlaid, keeping your scene visible.",
             ringed: true),
        Step(target: .cameraGuides, area: "Camera",
             title: "Choose your guide",
             body: "Tap Guides for a framing target. Tap it again for a clean view.",
             ringed: true),
        Step(target: .cameraCoaching, area: "Camera",
             title: "Keep coaching quiet",
             body: "Tap the message to collapse it. Tap the small icon to reopen."),
        Step(target: .cameraShutter, area: "Camera",
             title: "Take your shot",
             body: "Tap for one photo. Hold the shutter for a burst.",
             nextTitle: "Start Shooting"),
    ]
}

enum TourTarget: Hashable {
    case exploreFirstTile, exploreImport
    case cameraOverlay, cameraGuides, cameraCoaching, cameraShutter
}

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as a tour spotlight target.
    func tourAnchor(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// Dimmed overlay + coach card for the current step. Taps outside the card
/// are swallowed so the tour can't be half-interacted with.
struct TourOverlay: View {
    let steps: [FirstUseTour.Step]
    @Binding var index: Int?
    let anchors: [TourTarget: Anchor<CGRect>]
    let onFinish: () -> Void

    private let arrowSize = CGSize(width: 18, height: 9)

    var body: some View {
        GeometryReader { proxy in
            if let index, steps.indices.contains(index) {
                let step = steps[index]
                let rect = anchors[step.target].map { proxy[$0] }
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {}

                    if let rect, step.ringed {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 1.5)
                            .frame(width: 48, height: 48)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }

                    placedCard(step: step, number: index + 1, rect: rect, in: proxy.size)
                }
                .transition(.opacity)
                .id(index)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
    }

    @ViewBuilder
    private func placedCard(step: FirstUseTour.Step, number: Int, rect: CGRect?, in size: CGSize) -> some View {
        let width = min(304, size.width - 32)
        if let rect {
            let x = min(max(rect.midX - width / 2, 16), size.width - 16 - width)
            let arrowX = rect.midX - x
            if rect.midY < size.height * 0.55 {
                // Card below the target, arrow pointing up.
                card(step: step, number: number, arrowX: arrowX, arrowOnTop: true)
                    .frame(width: width)
                    .offset(x: x, y: rect.maxY + 10)
            } else {
                // Card above the target, arrow pointing down.
                card(step: step, number: number, arrowX: arrowX, arrowOnTop: false)
                    .frame(width: width)
                    .frame(width: size.width, height: max(rect.minY - 10, 0), alignment: .bottomLeading)
                    .offset(x: x)
            }
        } else {
            card(step: step, number: number, arrowX: nil, arrowOnTop: true)
                .frame(width: width)
                .frame(width: size.width, height: size.height)
        }
    }

    private func card(step: FirstUseTour.Step, number: Int, arrowX: CGFloat?, arrowOnTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(step.area)
                Spacer()
                Text("\(number) of \(steps.count)")
                    .monospacedDigit()
            }
            .font(.system(.footnote))
            .foregroundStyle(Color(hex: "#636366"))

            Text(step.title)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(Color(hex: "#1C1C1E"))
                .padding(.top, 10)
            Text(step.body)
                .font(.system(.subheadline))
                .foregroundStyle(Color(hex: "#636366"))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            HStack {
                Button("Skip Tour") { finish() }
                    .font(.system(.subheadline))
                    .foregroundStyle(Color(hex: "#1C1C1E"))
                Spacer()
                Button {
                    advance()
                } label: {
                    HStack(spacing: 8) {
                        Text(step.nextTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(.caption, weight: .semibold))
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(Color(hex: "#1C1C1E")))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(alignment: arrowOnTop ? .topLeading : .bottomLeading) {
            if let arrowX {
                TourArrow(pointsUp: arrowOnTop)
                    .fill(Color.white)
                    .frame(width: arrowSize.width, height: arrowSize.height)
                    .offset(
                        x: min(max(arrowX - arrowSize.width / 2, 20), 304 - 38),
                        y: arrowOnTop ? -arrowSize.height + 0.5 : arrowSize.height - 0.5
                    )
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func advance() {
        guard let index else { return }
        if index + 1 < steps.count {
            self.index = index + 1
        } else {
            finish()
        }
    }

    private func finish() {
        index = nil
        onFinish()
    }
}

private struct TourArrow: Shape {
    let pointsUp: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
