import CoreGraphics

/// Maps normalized 0–1 image coordinates into a container.
enum ImageContentMapper {

    enum Mode {
        /// `scaledToFill` — crops to cover the container.
        case fill
        /// `scaledToFit` — full image visible, letterboxed like Photos / Camera review.
        case fit
    }

    static func contentRect(contentSize: CGSize, in containerSize: CGSize, mode: Mode = .fit) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return .zero }
        let scale: CGFloat
        switch mode {
        case .fill:
            scale = max(
                containerSize.width / contentSize.width,
                containerSize.height / contentSize.height
            )
        case .fit:
            scale = min(
                containerSize.width / contentSize.width,
                containerSize.height / contentSize.height
            )
        }
        let width  = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: (containerSize.width  - width)  / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func point(
        _ normalized: CGPoint,
        contentSize: CGSize,
        in containerSize: CGSize,
        mode: Mode = .fit
    ) -> CGPoint {
        let rect = contentRect(contentSize: contentSize, in: containerSize, mode: mode)
        return CGPoint(
            x: rect.minX + normalized.x * rect.width,
            y: rect.minY + normalized.y * rect.height
        )
    }

    static func scalar(
        _ normalized: CGFloat,
        contentSize: CGSize,
        in containerSize: CGSize,
        mode: Mode = .fit
    ) -> CGFloat {
        let rect = contentRect(contentSize: contentSize, in: containerSize, mode: mode)
        return normalized * min(rect.width, rect.height)
    }

    /// Maps a normalized rect in content space to container coordinates.
    static func rect(
        _ normalized: CGRect,
        contentSize: CGSize,
        in containerSize: CGSize,
        mode: Mode = .fit
    ) -> CGRect {
        let content = contentRect(contentSize: contentSize, in: containerSize, mode: mode)
        return CGRect(
            x: content.minX + normalized.minX * content.width,
            y: content.minY + normalized.minY * content.height,
            width: normalized.width * content.width,
            height: normalized.height * content.height
        )
    }

    /// Maps content-normalized rect into 0–1 viewfinder coordinates.
    static func viewfinderNormalized(
        _ normalized: CGRect,
        contentSize: CGSize,
        in containerSize: CGSize,
        mode: Mode
    ) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let screen = rect(normalized, contentSize: contentSize, in: containerSize, mode: mode)
        return CGRect(
            x: screen.minX / containerSize.width,
            y: screen.minY / containerSize.height,
            width: screen.width / containerSize.width,
            height: screen.height / containerSize.height
        )
    }
}

// Keep old name for any fill-mode callers.
typealias AspectFillMapper = ImageContentMapper

extension ImageContentMapper {
    static func contentRect(contentSize: CGSize, in containerSize: CGSize) -> CGRect {
        contentRect(contentSize: contentSize, in: containerSize, mode: .fill)
    }

    static func point(_ normalized: CGPoint, contentSize: CGSize, in containerSize: CGSize) -> CGPoint {
        point(normalized, contentSize: contentSize, in: containerSize, mode: .fill)
    }

    static func scalar(_ normalized: CGFloat, contentSize: CGSize, in containerSize: CGSize) -> CGFloat {
        scalar(normalized, contentSize: contentSize, in: containerSize, mode: .fill)
    }
}
