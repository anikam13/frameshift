import Testing
import UIKit
@testable import FrameShift

struct FilterServiceTests {

    /// A neutral gray shot matched to a warm orange reference should move
    /// warmer: red up, blue down.
    @Test func matchColorsShiftsTowardReference() throws {
        let gray = Self.solidImage(UIColor(white: 0.5, alpha: 1))
        let warm = Self.solidImage(UIColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))

        let matched = try #require(FilterService.matchColors(of: gray, toReference: warm))

        let before = try #require(Self.averageRGB(of: gray))
        let after = try #require(Self.averageRGB(of: matched))
        #expect(after.red > before.red)
        #expect(after.blue < before.blue)
    }

    @Test func matchColorsPreservesDimensions() throws {
        let source = Self.solidImage(UIColor(white: 0.4, alpha: 1), size: CGSize(width: 120, height: 80))
        let reference = Self.solidImage(.systemTeal)

        let matched = try #require(FilterService.matchColors(of: source, toReference: reference))

        #expect(matched.size == source.size)
    }

    @Test func matchColorsAtZeroStrengthIsIdentity() throws {
        let source = Self.solidImage(UIColor(white: 0.5, alpha: 1))
        let reference = Self.solidImage(.systemOrange)

        let matched = try #require(
            FilterService.matchColors(of: source, toReference: reference, strength: 0)
        )

        let before = try #require(Self.averageRGB(of: source))
        let after = try #require(Self.averageRGB(of: matched))
        #expect(abs(after.red - before.red) < 0.02)
        #expect(abs(after.green - before.green) < 0.02)
        #expect(abs(after.blue - before.blue) < 0.02)
    }

    /// The blur/bloom stages clamp and re-crop the working extent; every
    /// preset must still come out at the source size.
    @Test(arguments: FilterPreset.allCases)
    func applyPreservesDimensions(preset: FilterPreset) throws {
        let source = Self.solidImage(UIColor(white: 0.6, alpha: 1), size: CGSize(width: 120, height: 80))

        let filtered = try #require(FilterService.apply(preset, to: source))

        #expect(filtered.size == source.size)
    }

    @Test func applyAtZeroStrengthIsIdentity() throws {
        let source = Self.solidImage(UIColor(red: 0.6, green: 0.4, blue: 0.3, alpha: 1))

        let filtered = try #require(FilterService.apply(.film, to: source, strength: 0))

        let before = try #require(Self.averageRGB(of: source))
        let after = try #require(Self.averageRGB(of: filtered))
        #expect(abs(after.red - before.red) < 0.02)
        #expect(abs(after.green - before.green) < 0.02)
        #expect(abs(after.blue - before.blue) < 0.02)
    }

    @Test func applyAtHalfStrengthLandsBetweenOriginalAndFull() throws {
        let source = Self.solidImage(UIColor(white: 0.5, alpha: 1))

        let full = try #require(FilterService.apply(.digital, to: source, strength: 1))
        let half = try #require(FilterService.apply(.digital, to: source, strength: 0.5))

        let original = try #require(Self.averageRGB(of: source)).blue
        let fullBlue = try #require(Self.averageRGB(of: full)).blue
        let halfBlue = try #require(Self.averageRGB(of: half)).blue
        // The look must move blue enough to measure, and half strength must
        // land strictly between the original and the full look.
        #expect(abs(fullBlue - original) > 0.01)
        #expect(halfBlue > min(original, fullBlue))
        #expect(halfBlue < max(original, fullBlue))
    }

    // MARK: Helpers

    private static func solidImage(
        _ color: UIColor, size: CGSize = CGSize(width: 64, height: 64)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Average color read by drawing the image into a single pixel.
    private static func averageRGB(
        of image: UIImage
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}
