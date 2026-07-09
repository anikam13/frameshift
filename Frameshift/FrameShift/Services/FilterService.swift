import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// The gallery's camera-look presets, modeled on popular travel cameras.
enum FilterPreset: String, CaseIterable, Identifiable {
    /// 90s flash point-and-shoot: warm, contrasty, heavy vignette, grainy.
    case disposable = "Disposable"
    /// 35mm negative: lifted blacks, muted color, gentle warmth, fine grain.
    case film = "Film"
    /// Early-2000s digicam: punchy saturation, cool cast, oversharpened.
    case digital = "Digital"

    var id: String { rawValue }
}

/// Applies `FilterPreset` looks with CoreImage (system framework — the
/// no-third-party-dependencies constraint holds). Pure pixel work; callers
/// run it off the main actor for full-resolution renders.
/// nonisolated: the project defaults to MainActor isolation.
nonisolated enum FilterService {

    private static let context = CIContext()

    static func apply(_ preset: FilterPreset, to image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let output: CIImage
        switch preset {
        case .disposable: output = disposable(input)
        case .film:       output = film(input)
        case .digital:    output = digital(input)
        }
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        // CIImage(image:) reads raw pixels; re-attach the original orientation.
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: Looks

    private static func disposable(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 7400)
        image = colorControls(image, saturation: 1.18, contrast: 1.12)
        image = vignette(image, intensity: 1.2, radius: 1.8)
        image = grain(image, strength: 0.14)
        return image
    }

    private static func film(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 6900)
        image = colorControls(image, saturation: 0.86, contrast: 1.02)
        image = fadedBlacks(image, lift: 0.09)
        image = vignette(image, intensity: 0.6, radius: 1.4)
        image = grain(image, strength: 0.08)
        return image
    }

    private static func digital(_ input: CIImage) -> CIImage {
        var image = temperature(input, target: 5900)
        image = colorControls(image, saturation: 1.3, contrast: 1.08)
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.5
        return sharpen.outputImage ?? image
    }

    // MARK: Building blocks

    /// target > 6500 warms the image, < 6500 cools it.
    private static func temperature(_ input: CIImage, target: CGFloat) -> CIImage {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = input
        filter.neutral = CIVector(x: 6500, y: 0)
        filter.targetNeutral = CIVector(x: target, y: 0)
        return filter.outputImage ?? input
    }

    private static func colorControls(_ input: CIImage, saturation: Float, contrast: Float) -> CIImage {
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = saturation
        filter.contrast = contrast
        return filter.outputImage ?? input
    }

    /// Tone curve that lifts shadows and caps highlights — the faded-print look.
    private static func fadedBlacks(_ input: CIImage, lift: CGFloat) -> CIImage {
        let filter = CIFilter.toneCurve()
        filter.inputImage = input
        filter.point0 = CGPoint(x: 0, y: lift)
        filter.point1 = CGPoint(x: 0.25, y: 0.25 + lift * 0.5)
        filter.point2 = CGPoint(x: 0.5, y: 0.5)
        filter.point3 = CGPoint(x: 0.75, y: 0.76)
        filter.point4 = CGPoint(x: 1, y: 0.97)
        return filter.outputImage ?? input
    }

    private static func vignette(_ input: CIImage, intensity: Float, radius: Float) -> CIImage {
        let filter = CIFilter.vignette()
        filter.inputImage = input
        filter.intensity = intensity
        filter.radius = radius
        return filter.outputImage ?? input
    }

    /// Monochrome noise centered on mid-gray, soft-light blended so the mean
    /// exposure is unchanged; `strength` is the ± swing around gray.
    private static func grain(_ input: CIImage, strength: CGFloat) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return input }
        let bias = 0.5 - strength / 2
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: strength, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ]).cropped(to: input.extent)
        return mono.applyingFilter(
            "CISoftLightBlendMode",
            parameters: [kCIInputBackgroundImageKey: input]
        )
    }
}
