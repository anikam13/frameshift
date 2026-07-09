import UIKit
import Photos

struct ExportService {

    enum Format {
        case story   // 9:16
        case square  // 1:1
    }

    // MARK: Card generation

    func generateCard(reference: UIImage, shot: UIImage, format: Format) -> UIImage? {
        let size: CGSize = format == .story
            ? CGSize(width: 1080, height: 1920)
            : CGSize(width: 1080, height: 1080)

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            // Background
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let (refRect, shotRect): (CGRect, CGRect) = {
                switch format {
                case .story:
                    let h = size.height / 2
                    return (
                        CGRect(x: 0, y: 0,    width: size.width, height: h),
                        CGRect(x: 0, y: h,    width: size.width, height: h)
                    )
                case .square:
                    let w = size.width / 2
                    return (
                        CGRect(x: 0, y: 0,    width: w, height: size.height),
                        CGRect(x: w, y: 0,    width: w, height: size.height)
                    )
                }
            }()

            drawFilled(reference, in: refRect,  context: ctx.cgContext)
            drawFilled(shot,      in: shotRect, context: ctx.cgContext)
            drawLabel("REFERENCE", in: refRect)
            drawLabel("YOUR SHOT", in: shotRect)
            drawWordmark(in: size)
        }
    }

    // MARK: Helpers

    private func drawFilled(_ image: UIImage, in rect: CGRect, context: CGContext) {
        guard let cg = image.cgImage else { return }
        let imgW = CGFloat(cg.width), imgH = CGFloat(cg.height)
        let imgAspect = imgW / imgH
        let rectAspect = rect.width / rect.height

        var drawRect = rect
        if imgAspect > rectAspect {
            let w = rect.height * imgAspect
            drawRect = CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: rect.height)
        } else {
            let h = rect.width / imgAspect
            drawRect = CGRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        }

        context.saveGState()
        context.clip(to: rect)
        image.draw(in: drawRect)
        context.restoreGState()
    }

    private func drawLabel(_ text: String, in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: UIColor.white,
            .kern: 1.5
        ]
        (text as NSString).draw(
            at: CGPoint(x: rect.minX + 20, y: rect.maxY - 50),
            withAttributes: attrs
        )
    }

    private func drawWordmark(in size: CGSize) {
        let text = "FrameShift" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .regular),
            .foregroundColor: UIColor.white.withAlphaComponent(0.35)
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(
            at: CGPoint(x: size.width - textSize.width - 24, y: size.height - textSize.height - 24),
            withAttributes: attrs
        )
    }

    // MARK: Save & share

    /// Shares regardless of the Photos-save outcome — sharing doesn't need
    /// Photos permission at all, and a denied/failed save shouldn't block it.
    ///
    /// `viewController` is typically the window's root, but the caller (e.g.
    /// GalleryPreviewView) is usually itself presented over that root as a
    /// fullScreenCover — presenting the share sheet directly on the root
    /// while something is already presented from it fails silently. Walk to
    /// the actual topmost presented controller before presenting.
    func saveAndShare(image: UIImage, from viewController: UIViewController, appState: AppState? = nil) {
        Task {
            let result = await PhotoLibrarySaver.save(image)
            await MainActor.run {
                switch result {
                case .saved:              break
                case .deniedOrRestricted: appState?.notePhotoLibraryDenied()
                case .failed:             appState?.showTransientNotice("Couldn't save to your camera roll")
                }
                let ac = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                Self.topmostViewController(from: viewController).present(ac, animated: true)
            }
        }
    }

    private static func topmostViewController(from viewController: UIViewController) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return topmostViewController(from: presented)
        }
        return viewController
    }
}
