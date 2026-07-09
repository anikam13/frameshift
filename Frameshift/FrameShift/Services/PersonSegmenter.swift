import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Cuts the person out of a reference photo, returning an image with a
/// transparent background for the camera ghost overlay. Like ShotSpec,
/// cutouts are computed once per reference and kept in memory only.
/// nonisolated: pure Vision/CoreImage work, runs on background tasks.
nonisolated struct PersonSegmenter {

    /// The image must already be upright (`UIImage.upright()`) so the mask
    /// aligns with the pixels. Returns nil when segmentation fails.
    func cutout(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate   // one-shot at import, favor quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let maskBuffer = request.results?.first?.pixelBuffer else { return nil }

        let input = CIImage(cgImage: cgImage)
        let mask = CIImage(cvPixelBuffer: maskBuffer).transformed(by: CGAffineTransform(
            scaleX: input.extent.width / CGFloat(CVPixelBufferGetWidth(maskBuffer)),
            y: input.extent.height / CGFloat(CVPixelBufferGetHeight(maskBuffer))
        ))

        let blend = CIFilter.blendWithMask()
        blend.inputImage = input
        blend.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
        blend.maskImage = mask

        let context = CIContext()
        guard
            let output = blend.outputImage,
            let outCG = context.createCGImage(output, from: input.extent)
        else { return nil }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }
}
