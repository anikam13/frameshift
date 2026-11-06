import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Cuts the primary person out of a reference photo, returning an image with
/// a transparent background for the camera ghost overlay. Like ShotSpec,
/// cutouts are computed once per reference and kept in memory only.
/// nonisolated: pure Vision/CoreImage work, runs on background tasks.
nonisolated struct PersonSegmenter {

    private static let context = CIContext()

    /// App-facing quality so callers don't need to import Vision.
    enum CutoutQuality: Sendable {
        /// Fresh imports — best mask edges for the ghost overlay.
        case accurate
        /// Launch restore — cheaper; avoids starving the camera session.
        case balanced
    }

    /// The image must already be upright (`UIImage.upright()`) so the mask
    /// aligns with the pixels. `subjectNormalized` is the ShotSpec body box
    /// in UIKit 0–1 space; when set, other people in the frame are dropped.
    /// Returns nil when segmentation fails.
    func cutout(
        from image: UIImage,
        quality: CutoutQuality = .accurate,
        subjectNormalized: CGRect? = nil
    ) async -> UIImage? {
        let level: VNGeneratePersonSegmentationRequest.QualityLevel = {
            switch quality {
            case .accurate: return .accurate
            case .balanced: return .balanced
            }
        }()
        return await cutout(
            from: image,
            visionQuality: level,
            subjectNormalized: subjectNormalized
        )
    }

    private func cutout(
        from image: UIImage,
        visionQuality quality: VNGeneratePersonSegmentationRequest.QualityLevel,
        subjectNormalized: CGRect?
    ) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let instanceRequest = VNGenerateForegroundInstanceMaskRequest()
        let personRequest = VNGeneratePersonSegmentationRequest()
        personRequest.qualityLevel = quality
        personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([instanceRequest, personRequest])
        } catch {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        let personMask = scaledMask(
            personRequest.results?.first?.pixelBuffer,
            to: input.extent
        )
        let instanceMask = primaryInstanceMask(
            instanceRequest.results?.first,
            inputExtent: input.extent,
            subjectNormalized: subjectNormalized
        )

        // Instance isolates the main subject; person segmentation supplies
        // cleaner hair/edge detail. Either alone is enough to blend.
        let mask: CIImage
        if let instanceMask, let personMask {
            mask = instanceMask.applyingFilter("CIMultiplyCompositing", parameters: [
                kCIInputBackgroundImageKey: personMask
            ])
        } else if let instanceMask {
            mask = instanceMask
        } else if let personMask {
            mask = constrainToSubject(personMask, subjectNormalized: subjectNormalized, extent: input.extent)
        } else {
            return nil
        }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = input
        blend.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
        blend.maskImage = mask

        guard
            let output = blend.outputImage,
            let outCG = Self.context.createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }

    /// Picks the instance that overlaps the subject box the most. With no
    /// box, the largest instance wins (solo portraits / onboarding).
    private func primaryInstanceMask(
        _ observation: VNInstanceMaskObservation?,
        inputExtent: CGRect,
        subjectNormalized: CGRect?
    ) -> CIImage? {
        guard let observation, !observation.allInstances.isEmpty else { return nil }

        let subjectCI = subjectNormalized.map { uiKitToCI($0, extent: inputExtent, padding: 0.12) }
        var bestIndex: Int?
        var bestScore: CGFloat = -1

        for index in observation.allInstances {
            guard let buffer = try? observation.generateMask(forInstances: IndexSet(integer: index)),
                  let mask = scaledMask(buffer, to: inputExtent)
            else { continue }

            let score: CGFloat
            if let subjectCI {
                score = maskedArea(mask, in: subjectCI)
            } else {
                score = maskedArea(mask, in: inputExtent)
            }
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        guard let bestIndex,
              let buffer = try? observation.generateMask(forInstances: IndexSet(integer: bestIndex))
        else { return nil }
        return scaledMask(buffer, to: inputExtent)
    }

    /// Last resort when instance masks fail: keep person pixels only inside
    /// a feathered subject window so distant extras drop out.
    private func constrainToSubject(
        _ mask: CIImage,
        subjectNormalized: CGRect?,
        extent: CGRect
    ) -> CIImage {
        guard let subjectNormalized else { return mask }
        let window = uiKitToCI(subjectNormalized, extent: extent, padding: 0.16)
        let box = CIImage(color: .white)
            .cropped(to: window)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: max(8, min(extent.width, extent.height) * 0.02))
            .cropped(to: extent)
        return mask.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: box
        ])
    }

    private func scaledMask(_ buffer: CVPixelBuffer?, to extent: CGRect) -> CIImage? {
        guard let buffer else { return nil }
        let mask = CIImage(cvPixelBuffer: buffer)
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        guard sx.isFinite, sy.isFinite, sx > 0, sy > 0 else { return nil }
        return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }

    /// UIKit top-left 0–1 → Core Image bottom-left pixels, padded.
    private func uiKitToCI(_ normalized: CGRect, extent: CGRect, padding: CGFloat) -> CGRect {
        var n = normalized.insetBy(dx: -normalized.width * padding, dy: -normalized.height * padding)
        n.origin.x = max(0, n.origin.x)
        n.origin.y = max(0, n.origin.y)
        n.size.width = min(1 - n.origin.x, n.width)
        n.size.height = min(1 - n.origin.y, n.height)
        return CGRect(
            x: extent.minX + n.minX * extent.width,
            y: extent.minY + (1 - n.maxY) * extent.height,
            width: n.width * extent.width,
            height: n.height * extent.height
        )
    }

    private func maskedArea(_ mask: CIImage, in rect: CGRect) -> CGFloat {
        guard rect.width > 1, rect.height > 1 else { return 0 }
        let filter = CIFilter.areaAverage()
        filter.inputImage = mask
        filter.extent = rect
        guard let output = filter.outputImage else { return 0 }
        var pixel = [UInt8](repeating: 0, count: 4)
        Self.context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return CGFloat(pixel[0]) / 255.0 * rect.width * rect.height
    }
}
