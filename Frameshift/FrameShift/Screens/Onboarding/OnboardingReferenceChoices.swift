import SwiftUI

/// Photos shown on the first onboarding step. The Cinque Terre floral
/// portrait sits second so the carousel can land on it after a short intro pan.
enum OnboardingReferenceChoices {
    static let featured = "SampleRefCinqueFloral"

    static let assetNames = [
        "SampleRefBeachWalk",
        featured,
        "SampleRefCafeSip",
        "SampleRefPatioGlance",
        "SampleRefStoneLean",
        "SampleRefCoastalDress",
    ]
}
