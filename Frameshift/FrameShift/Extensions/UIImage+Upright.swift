import UIKit

extension UIImage {

    /// Bakes `imageOrientation` into pixels so Vision coordinates match SwiftUI display.
    /// nonisolated: pure CoreGraphics rendering, called from background load/import paths.
    nonisolated func upright() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
