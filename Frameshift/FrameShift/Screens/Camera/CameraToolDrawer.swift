import SwiftUI

/// Apple Camera-style tool drawer: the ⋯ button in the top pill slides this
/// sheet up over the bottom controls. Circular toggle buttons with uppercase
/// labels, matching the native FLASH / LIVE / TIMER drawer.
struct CameraToolDrawer: View {
    @ObservedObject var vm: CameraViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                toolButton(label: "LEVEL", isOn: $vm.isLevelVisible) {
                    LevelGlyph()
                }
                toolButton(label: "GRID", isOn: $vm.isGridVisible) {
                    Image(systemName: "grid")
                        .font(.system(size: 22, weight: .regular))
                }
                toolButton(label: "CIRCLE", isOn: $vm.isHeadCircleVisible) {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 22, weight: .regular))
                }
                toolButton(label: "TIPS", isOn: $vm.tipsEnabled) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 22, weight: .regular))
                }
            }

            HStack(spacing: 8) {
                aspectSegment(.fourThree, ratio: "4:3", hint: "POSTS")
                aspectSegment(.sixteenNine, ratio: "16:9", hint: "STORIES")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(.regularMaterial)
        )
        .environment(\.colorScheme, .dark)
    }

    /// Aspect pill with a "what it's for" hint — 4:3 fills a feed post,
    /// 16:9 (9:16 tall) fills a story.
    private func aspectSegment(
        _ aspect: CameraViewModel.CaptureAspect,
        ratio: String,
        hint: String
    ) -> some View {
        let isSelected = vm.captureAspect == aspect
        return Button {
            guard !isSelected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.25)) {
                vm.captureAspect = aspect
            }
        } label: {
            HStack(spacing: 7) {
                Text(ratio)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.cameraYellow : .white)
                Text(hint)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Color.cameraYellow.opacity(0.75) : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(isSelected ? 0.22 : 0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toolButton(
        label: String,
        isOn: Binding<Bool>,
        @ViewBuilder icon: () -> some View
    ) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isOn.wrappedValue ? 0.22 : 0.10))
                        .frame(width: 60, height: 60)
                    icon()
                        .foregroundStyle(isOn.wrappedValue ? Color.cameraYellow : .white)
                }
                Text(label)
                    .font(.system(size: 13, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// Two-dash glyph mimicking the on-screen level indicator — SF Symbols has no
/// reliable "level" icon across iOS 16, so this stays pixel-faithful instead.
private struct LevelGlyph: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule().frame(width: 13, height: 2.5)
            Capsule().frame(width: 13, height: 2.5)
        }
    }
}
