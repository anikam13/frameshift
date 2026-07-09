import UIKit

/// A user-created filter look: a photo picked in the filter sheet whose
/// color statistics captures are matched toward (`FilterService.matchColors`).
struct CustomFilterPreset: Identifiable {
    let id: UUID
    let name: String
    /// Downsampled look source — only its color stats matter; never shown large.
    let image: UIImage
    let createdAt: Date
}
