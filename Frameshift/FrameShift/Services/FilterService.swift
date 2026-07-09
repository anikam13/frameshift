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

    /// `strength` crossfades between the original (0) and the full look (1),
    /// matching the sheet's opacity-overlay preview exactly.
    static func apply(_ preset: FilterPreset, to image: UIImage, strength: Float = 1) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        var output: CIImage
        switch preset {
        case .disposable: output = disposable(input)
        case .film:       output = film(input)
        case .digital:    output = digital(input)
        }
        if strength < 1 {
            let dissolve = CIFilter.dissolveTransition()
            dissolve.inputImage = input
            dissolve.targetImage = output
            dissolve.time = max(0, strength)
            output = dissolve.outputImage ?? output
        }
        guard let cg = context.createCGImage(output, from: input.extent) else { return nil }
        // CIImage(image:) reads raw pixels; re-attach the original orientation.
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: Reference color match

    /// Reinhard-style statistical color transfer: shifts each channel's mean
    /// and spread toward the reference's, so the shot takes on its overall
    /// color mood without needing a real LUT. `strength` blends between the
    /// original (0) and the full match (1); full strength overcorrects on
    /// heavily tinted references, so the default holds back.
    static func matchColors(of image: UIImage, toReference reference: UIImage, strength: Float = 0.75) -> UIImage? {
        guard let input = CIImage(image: image),
              let referenceInput = CIImage(image: reference),
              let source = colorStats(of: input),
              let target = colorStats(of: referenceInput) else { return nil }

        var gain = [CGFloat](repeating: 1, count: 3)
        var bias = [CGFloat](repeating: 0, count: 3)
        for channel in 0..<3 {
            // Clamps keep near-flat sources and extreme grades from blowing out.
            let spread = min(max(target.std[channel] / max(source.std[channel], 0.005), 0.5), 1.8)
            let shift = min(max(target.mean[channel] - spread * source.mean[channel], -0.3), 0.3)
            // Blending the coefficients equals blending the outputs (the
            // transform is affine), so strength needs no second render pass.
            gain[channel] = CGFloat(1 + (spread - 1) * strength)
            bias[channel] = CGFloat(shift * strength)
        }

        let matched = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain[0], y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain[1], z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain[2], w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias[0], y: bias[1], z: bias[2], w: 0)
        ]).applyingFilter("CIColorClamp")

        guard let cg = context.createCGImage(matched, from: input.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Per-channel mean and standard deviation, read in the linear working
    /// space where CIColorMatrix applies.
    private static func colorStats(of image: CIImage) -> (mean: [Float], std: [Float])? {
        let squared = image.applyingFilter(
            "CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: image]
        )
        guard let mean = averageColor(of: image),
              let meanOfSquares = averageColor(of: squared) else { return nil }
        let std = (0..<3).map { sqrt(max(meanOfSquares[$0] - mean[$0] * mean[$0], 0)) }
        return (mean, std)
    }

    private static func averageColor(of image: CIImage) -> [Float]? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: MemoryLayout<Float>.size * 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        )
        return Array(pixel[0..<3])
    }

    // MARK: Looks

    /// Grain fades out of highlights (well-exposed film reads clean there)
    /// but stays in shadows and midtones.
    private static let filmGrainCurve = [
        CGPoint(x: 0, y: 0.9), CGPoint(x: 0.25, y: 1.0), CGPoint(x: 0.5, y: 0.9),
        CGPoint(x: 0.75, y: 0.55), CGPoint(x: 1, y: 0.15)
    ]

    /// Digicam sensor noise lives in the shadows and vanishes in bright areas.
    private static let shadowNoiseCurve = [
        CGPoint(x: 0, y: 1.0), CGPoint(x: 0.25, y: 0.8), CGPoint(x: 0.5, y: 0.45),
        CGPoint(x: 0.75, y: 0.2), CGPoint(x: 1, y: 0.05)
    ]

    private static func disposable(_ input: CIImage) -> CIImage {
        let scale = renderScale(input)
        var image = temperature(input, target: 7400)
        image = colorControls(image, saturation: 1.18, contrast: 1.12)
        image = vignette(image, intensity: 1.2, radius: 1.8)
        image = grain(
            image, strength: 0.14, size: 1.5 * scale,
            monochrome: true, maskCurve: filmGrainCurve
        )
        return image
    }

    private static func film(_ input: CIImage) -> CIImage {
        let scale = renderScale(input)
        var image = temperature(input, target: 6900)
        image = colorControls(image, saturation: 0.86, contrast: 1.02)
        image = fadedBlacks(image, lift: 0.09)
        // Halation: highlights glow softly into their surroundings.
        image = bloom(image, intensity: 0.25, radius: Float(10 * scale))
        image = vignette(image, intensity: 0.6, radius: 1.4)
        image = grain(
            image, strength: 0.10, size: 1.8 * scale,
            monochrome: true, maskCurve: filmGrainCurve
        )
        return image
    }

    private static func digital(_ input: CIImage) -> CIImage {
        let scale = renderScale(input)
        var image = temperature(input, target: 5900)
        image = colorControls(image, saturation: 1.3, contrast: 1.08)
        // Low dynamic range: blacks never quite reach black.
        image = fadedBlacks(image, lift: 0.04)
        // Cheap lens + anti-alias filter softness, then CCD highlight bloom.
        image = soften(image, radius: Float(0.8 * scale))
        image = bloom(image, intensity: 0.5, radius: Float(8 * scale))
        // Chunky colored sensor noise, mostly in the shadows.
        image = grain(
            image, strength: 0.09, size: 2.4 * scale,
            monochrome: false, maskCurve: shadowNoiseCurve
        )
        // In-camera oversharpening runs last so it crunches the noise too.
        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.55
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

    /// Ratio of this render's size to the display tier, so pixel-sized
    /// effects (grain clumps, bloom/blur radii) look the same on the sheet's
    /// display-sized previews and the full-resolution save.
    private static func renderScale(_ input: CIImage) -> CGFloat {
        max(1, max(input.extent.width, input.extent.height) / UIImage.displayMaxPixelSize)
    }

    /// Bright areas bleed softly into their surroundings — film halation or
    /// CCD blooming depending on the radius/intensity.
    private static func bloom(_ input: CIImage, intensity: Float, radius: Float) -> CIImage {
        let filter = CIFilter.bloom()
        filter.inputImage = input.clampedToExtent()
        filter.intensity = intensity
        filter.radius = radius
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    private static func soften(_ input: CIImage, radius: Float) -> CIImage {
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = radius
        return filter.outputImage?.cropped(to: input.extent) ?? input
    }

    /// Noise centered on mid-gray, soft-light blended so the mean exposure is
    /// unchanged; `strength` is the ± swing around gray. `size` scales the
    /// noise up so grains become soft clumps rather than single pixels, and
    /// `maskCurve` shapes where grain shows by luminance (white = full grain).
    /// Monochrome reads as film grain; colored reads as digital sensor noise.
    private static func grain(
        _ input: CIImage, strength: CGFloat, size: CGFloat,
        monochrome: Bool, maskCurve: [CGPoint]
    ) -> CIImage {
        guard let noise = CIFilter.randomGenerator().outputImage else { return input }
        let bias = 0.5 - strength / 2
        // Monochrome ties all channels to one random value; colored noise
        // keeps the channels independent.
        let red = CIVector(x: strength, y: 0, z: 0, w: 0)
        let green = monochrome ? red : CIVector(x: 0, y: strength, z: 0, w: 0)
        let blue = monochrome ? red : CIVector(x: 0, y: 0, z: strength, w: 0)
        let speckles = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": red,
            "inputGVector": green,
            "inputBVector": blue,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
        ])
        .transformed(by: CGAffineTransform(scaleX: size, y: size))
        .cropped(to: input.extent)

        let grained = speckles.applyingFilter(
            "CISoftLightBlendMode",
            parameters: [kCIInputBackgroundImageKey: input]
        )

        let blend = CIFilter.blendWithMask()
        blend.inputImage = grained
        blend.backgroundImage = input
        blend.maskImage = luminanceMask(of: input, curve: maskCurve)
        return blend.outputImage ?? grained
    }

    /// Grayscale mask from the image's luminance reshaped by a tone curve,
    /// for masking effects into shadows / out of highlights.
    private static func luminanceMask(of input: CIImage, curve: [CGPoint]) -> CIImage {
        let gray = input.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0
        ])
        let filter = CIFilter.toneCurve()
        filter.inputImage = gray
        filter.point0 = curve[0]
        filter.point1 = curve[1]
        filter.point2 = curve[2]
        filter.point3 = curve[3]
        filter.point4 = curve[4]
        return filter.outputImage ?? gray
    }
}
