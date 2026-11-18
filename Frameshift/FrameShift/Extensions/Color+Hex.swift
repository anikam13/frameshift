import SwiftUI

extension Color {
    /// Initialise from a hex string e.g. "#FFD60A" or "FFD60A".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // MARK: Design tokens
    static let cameraYellow = Color(hex: "#FFD60A")
    static let boxIdle      = Color.white.opacity(0.80)
    static let boxLocked    = Color(hex: "#FFD60A")
    static let gridLine     = Color.white.opacity(0.25)
    static let levelNeutral = Color.white.opacity(0.40)
    static let levelLocked  = Color(hex: "#FFD60A")

    // Redesign tokens (Paper: "FrameShift — UX Redesign").
    /// Raised dark controls on camera chrome: zoom selection, flip button.
    static let cameraControl     = Color(hex: "#242424")
    /// Background behind a yellow glyph on a manually selected camera control.
    static let cameraAccentTint  = Color(hex: "#332B00")
    /// Translucent coaching pill over the live viewfinder (#000000B8).
    static let coachPill         = Color.black.opacity(0.72)
    /// Head-target circle at rest (#FFFFFFE6).
    static let guideIdle         = Color.white.opacity(0.9)
}

/// Fixed reference-overlay opacity. Approved spec: no slider, no per-photo value.
let referenceOverlayOpacity: Double = 0.35
