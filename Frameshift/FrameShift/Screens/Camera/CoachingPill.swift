import SwiftUI

/// Floating translucent coaching pill (Paper: camera states, "Coaching
/// collapsed", "08a/08b alignment"). Independent of the visual-aid mode —
/// it shows in Overlay, Guides and Clean alike. One instruction at a time.
struct CoachingPill: View {
    enum Message: Equatable {
        case instruction(String)
        case lookingForSubject
        case lookingGood
        case readyCheck
        case collapsed
    }

    let content: Message
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                switch content {
                case .instruction(let text):
                    label(text)
                case .lookingForSubject:
                    label("Looking for subject")
                case .lookingGood:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Color.cameraYellow)
                        Text("Looking good")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color.coachPill, in: Capsule())
                case .readyCheck:
                    circle {
                        Image(systemName: "checkmark")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Color.cameraYellow)
                    }
                case .collapsed:
                    circle {
                        Image(systemName: "text.bubble")
                            .font(.system(.callout, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
            }
            .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: content)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(content == .collapsed ? "Shows coaching" : "Hides coaching")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Color.coachPill, in: Capsule())
    }

    private func circle<C: View>(@ViewBuilder _ glyph: () -> C) -> some View {
        glyph()
            .frame(width: 44, height: 44)
            .background(Color.coachPill, in: Circle())
    }

    private var accessibilityText: String {
        switch content {
        case .instruction(let text): return text
        case .lookingForSubject:     return "Looking for subject"
        case .lookingGood, .readyCheck: return "Looking good"
        case .collapsed:             return "Coaching hidden"
        }
    }
}
