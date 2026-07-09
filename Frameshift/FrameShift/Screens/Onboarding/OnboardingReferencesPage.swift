import SwiftUI

/// Illustrates the References grid — grouped by style, same as the real
/// screen — using placeholder swatches since onboarding runs before any
/// photo library access and can't show real imported photos.
struct OnboardingReferencesPage: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private let groups: [(title: String, hues: [Double])] = [
        ("Landscape", [0.58, 0.62, 0.08]),
        ("Urban",     [0.0, 0.75, 0.55])
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Save a shot you love.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Import a reference photo to get started.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 60)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(group.hues, id: \.self) { hue in
                                swatch(hue: hue)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    private func swatch(hue: Double) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(hue: hue, saturation: 0.35, brightness: 0.55))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.white.opacity(0.5))
            }
    }
}
