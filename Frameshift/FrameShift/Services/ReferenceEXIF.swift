import UIKit
import ImageIO

/// EXIF metadata parsed once per reference import (US-105).
/// All fields are optional — Pinterest/screenshot crops carry no EXIF.
/// nonisolated: called from VisionAnalyzer off the main actor.
nonisolated struct ReferenceEXIF {

    /// 35mm-equivalent focal length, when derivable.
    let focalLength35mm: CGFloat?

    /// Apple maker-note acceleration vector (tag 8), in units of g, device
    /// coordinate frame (same axes as CoreMotion). Only present in original
    /// iPhone captures; stripped by re-encodes and most web downloads.
    let accelerationVector: (x: Double, y: Double, z: Double)?

    static func parse(image: UIImage, imageData: Data?) -> ReferenceEXIF {
        if let data = imageData, let props = properties(from: data) {
            return ReferenceEXIF(
                focalLength35mm: focalLength(from: props),
                accelerationVector: accelerationVector(from: props)
            )
        }
        // Re-encoded fallback keeps focal length but strips maker notes.
        guard let data = image.jpegData(compressionQuality: 1),
              let props = properties(from: data)
        else { return ReferenceEXIF(focalLength35mm: nil, accelerationVector: nil) }
        return ReferenceEXIF(
            focalLength35mm: focalLength(from: props),
            accelerationVector: nil
        )
    }

    // MARK: - Private

    private static func properties(from data: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }

    private static func focalLength(from props: [String: Any]) -> CGFloat? {
        guard let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return nil }
        if let fl = exif[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? CGFloat, fl > 0 {
            return fl
        }
        if let fl = exif[kCGImagePropertyExifFocalLength as String] as? CGFloat, fl > 0 {
            return fl * 1.6
        }
        return nil
    }

    /// Apple maker note tag 8 ("AccelerationVector"): gravity direction at
    /// capture time. Undocumented but stable across iOS versions; treated as
    /// best-effort — any unexpected shape returns nil.
    private static func accelerationVector(from props: [String: Any]) -> (x: Double, y: Double, z: Double)? {
        guard
            let maker = props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any],
            let raw = maker["8"] as? [Any], raw.count == 3,
            let x = (raw[0] as? NSNumber)?.doubleValue,
            let y = (raw[1] as? NSNumber)?.doubleValue,
            let z = (raw[2] as? NSNumber)?.doubleValue
        else { return nil }
        return (x, y, z)
    }
}
