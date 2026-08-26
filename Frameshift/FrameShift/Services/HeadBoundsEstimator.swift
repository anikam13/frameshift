import CoreGraphics

/// Computes the head guide circle for a reference photo once at import (US-101/102).
///
/// Inputs are normalized (0–1) UIKit top-left coordinates in upright image space.
/// Output center is normalized to image width/height; radius is normalized to
/// min(imageWidth, imageHeight) so it survives uniform aspect-fit mapping
/// (see `ShotSpec.headCircle(in:)`).
/// nonisolated: used by VisionAnalyzer / LiveVisionAnalyzer off MainActor.
nonisolated enum HeadBoundsEstimator {

    // MARK: - Tunable constants

    // FR-1 — face-rect padding. Vision's face box spans roughly brows → chin,
    // so the top needs the most room for forehead and hair.
    static let facePaddingTop: CGFloat = 0.35        // × face height
    static let facePaddingBottom: CGFloat = 0.18     // × face height
    static let facePaddingHorizontal: CGFloat = 0.12 // × face width

    // FR-3 — wide (profile-ish) face rects get a boosted radius.
    static let profileAspectThreshold: CGFloat = 1.4
    static let profileRadiusBoost: CGFloat = 1.15

    // US-102 — landmark path.
    static let landmarkConfidenceThreshold: Float = 0.5
    static let landmarkHairPadding: CGFloat = 0.22   // × face height above landmark top
    // Vision's chin contour traces the jawline under facial hair; a full
    // beard extends ~0.3 face-heights below it (measured on device, R4).
    static let landmarkChinPadding: CGFloat = 0.28   // × face height below contour chin

    // FR-2 — pose fallback, wider than the old ShotSpec heuristic.
    static let poseForeheadFactor: CGFloat = 1.2     // × eye-to-nose distance above eyes
    static let poseChinFactor: CGFloat = 0.65        // × nose-to-neck distance below nose

    // Last-resort fallback: assume the head fills the top of the upper-body box.
    static let fallbackHeadHeightRatio: CGFloat = 0.34 // × upper-body height

    // MARK: - Types

    /// Extremes of the face contour + median line, normalized UIKit coords.
    struct LandmarkExtremes {
        let topY: CGFloat
        let chinY: CGFloat
        let minX: CGFloat
        let maxX: CGFloat
        let confidence: Float
    }

    struct PoseInput {
        let nose: CGPoint
        let neck: CGPoint
        let leftEye: CGPoint?
        let rightEye: CGPoint?
    }

    struct Estimate {
        let centerX: CGFloat   // normalized to image width
        let centerY: CGFloat   // normalized to image height
        let radius: CGFloat    // normalized to min(imageWidth, imageHeight)
        let source: ShotSpec.HeadBoundsSource
    }

    // MARK: - Entry point

    static func estimate(
        faceRect: CGRect?,
        landmarks: LandmarkExtremes?,
        pose: PoseInput?,
        upperBody: CGRect,
        imageSize: CGSize
    ) -> Estimate {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return Estimate(centerX: 0.5, centerY: 0.3, radius: 0.15, source: .fallback)
        }
        if let faceRect {
            let facePx = pixelRect(faceRect, imageSize)
            if let landmarks, landmarks.confidence > landmarkConfidenceThreshold {
                return landmarkEstimate(facePx: facePx, landmarks: landmarks, imageSize: imageSize)
            }
            return faceRectEstimate(facePx: facePx, imageSize: imageSize)
        }
        if let pose {
            return poseEstimate(pose: pose, imageSize: imageSize)
        }
        return fallbackEstimate(upperBody: upperBody, imageSize: imageSize)
    }

    // MARK: - Tiers

    /// FR-1: face rect + fixed padding.
    private static func faceRectEstimate(facePx: CGRect, imageSize: CGSize) -> Estimate {
        let top = facePx.minY - facePx.height * facePaddingTop
        let bottom = facePx.maxY + facePx.height * facePaddingBottom
        let left = facePx.minX - facePx.width * facePaddingHorizontal
        let right = facePx.maxX + facePx.width * facePaddingHorizontal

        var radius = max(right - left, bottom - top) / 2
        // FR-3: wide rects mean a turned head — the narrow axis undershoots,
        // so grow the circle instead of trying to be asymmetric.
        if facePx.height > 0, facePx.width / facePx.height > profileAspectThreshold {
            radius *= profileRadiusBoost
        }
        return normalized(
            centerPx: CGPoint(x: (left + right) / 2, y: (top + bottom) / 2),
            radiusPx: radius,
            imageSize: imageSize,
            source: .faceRect
        )
    }

    /// US-102: contour/medianLine extremes give a real chin and side bounds;
    /// the contour stops at the brow line, so the top still gets hair padding.
    private static func landmarkEstimate(
        facePx: CGRect,
        landmarks: LandmarkExtremes,
        imageSize: CGSize
    ) -> Estimate {
        let lmTop = landmarks.topY * imageSize.height
        let lmChin = landmarks.chinY * imageSize.height
        let lmMinX = landmarks.minX * imageSize.width
        let lmMaxX = landmarks.maxX * imageSize.width

        let top = min(lmTop, facePx.minY) - facePx.height * landmarkHairPadding
        let bottom = max(lmChin, facePx.maxY) + facePx.height * landmarkChinPadding
        let left = min(lmMinX, facePx.minX) - facePx.width * facePaddingHorizontal
        let right = max(lmMaxX, facePx.maxX) + facePx.width * facePaddingHorizontal

        let radius = max(right - left, bottom - top) / 2
        return normalized(
            centerPx: CGPoint(x: (left + right) / 2, y: (top + bottom) / 2),
            radiusPx: radius,
            imageSize: imageSize,
            source: .faceLandmarks
        )
    }

    /// FR-2: body-pose fallback when no face is detected.
    private static func poseEstimate(pose: PoseInput, imageSize: CGSize) -> Estimate {
        let nosePx = pixelPoint(pose.nose, imageSize)
        let neckPx = pixelPoint(pose.neck, imageSize)
        let neckLen = max(neckPx.y - nosePx.y, imageSize.height * 0.01)
        let chinY = nosePx.y + neckLen * poseChinFactor

        if let le = pose.leftEye, let re = pose.rightEye {
            let lePx = pixelPoint(le, imageSize)
            let rePx = pixelPoint(re, imageSize)
            let eyeMid = CGPoint(x: (lePx.x + rePx.x) / 2, y: (lePx.y + rePx.y) / 2)
            let eyeSpan = max(abs(rePx.x - lePx.x), imageSize.width * 0.01)
            let eyeToNose = max(nosePx.y - eyeMid.y, eyeSpan * 0.4)
            let topY = eyeMid.y - eyeToNose * poseForeheadFactor

            let radius = max((chinY - topY) / 2, eyeSpan * 0.95)
            return normalized(
                centerPx: CGPoint(x: eyeMid.x, y: (topY + chinY) / 2),
                radiusPx: radius,
                imageSize: imageSize,
                source: .pose
            )
        }

        let topY = nosePx.y - neckLen * poseForeheadFactor
        let radius = max((chinY - topY) / 2, neckLen * 0.7)
        return normalized(
            centerPx: CGPoint(x: nosePx.x, y: (topY + chinY) / 2),
            radiusPx: radius,
            imageSize: imageSize,
            source: .pose
        )
    }

    /// Last resort: head assumed at the top-center of the upper-body box.
    private static func fallbackEstimate(upperBody: CGRect, imageSize: CGSize) -> Estimate {
        let upperPx = pixelRect(upperBody, imageSize)
        let headHeight = max(upperPx.height * fallbackHeadHeightRatio, imageSize.height * 0.05)
        return normalized(
            centerPx: CGPoint(x: upperPx.midX, y: upperPx.minY + headHeight / 2),
            radiusPx: headHeight / 2,
            imageSize: imageSize,
            source: .fallback
        )
    }

    // MARK: - Helpers

    private static func pixelRect(_ normalized: CGRect, _ size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }

    private static func pixelPoint(_ normalized: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private static func normalized(
        centerPx: CGPoint,
        radiusPx: CGFloat,
        imageSize: CGSize,
        source: ShotSpec.HeadBoundsSource
    ) -> Estimate {
        Estimate(
            centerX: centerPx.x / imageSize.width,
            centerY: centerPx.y / imageSize.height,
            radius: radiusPx / min(imageSize.width, imageSize.height),
            source: source
        )
    }
}
