import UIKit
import ImageIO

extension UIImage {

    /// Display-tier max edge for in-memory gallery / reference thumbnails.
    /// Keeps launch RAM bounded while still looking sharp on modern iPhones.
    nonisolated static let displayMaxPixelSize: CGFloat = 1600

    /// Ghost / grid-tier max edge — overlays and cells don't need more.
    nonisolated static let overlayMaxPixelSize: CGFloat = 1024

    /// Longest edge written for an imported reference. Coaching and the
    /// ghost overlay don't need the original 12MP HEIC.
    nonisolated static let referenceMaxPixelSize: CGFloat = 1600

    /// JPEG quality for stored references. Captured shots stay at 0.92.
    nonisolated static let referenceJPEGQuality: CGFloat = 0.72

    /// Downsamples then JPEG-encodes for the reference library.
    nonisolated func compressedReferenceJPEG(
        maxPixelSize: CGFloat = UIImage.referenceMaxPixelSize,
        quality: CGFloat = UIImage.referenceJPEGQuality
    ) -> Data? {
        downsampled(maxPixelSize: maxPixelSize).jpegData(compressionQuality: quality)
    }

    /// Decodes a downsampled upright image via ImageIO without materializing
    /// the full-resolution bitmap first. Prefer this over `UIImage(data:)` +
    /// `upright()` when restoring from disk.
    nonisolated static func downsampled(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary)
        else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbOptions as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Downsamples an already-decoded image. Used after capture so
    /// `AppState.capturedShots` holds display-sized bitmaps while the full
    /// JPEG is written to disk.
    nonisolated func downsampled(maxPixelSize: CGFloat) -> UIImage {
        let longest = max(size.width * scale, size.height * scale)
        guard longest > maxPixelSize else { return self }

        let ratio = maxPixelSize / longest
        let target = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
