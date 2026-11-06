import Foundation

/// Bundled starter references for the cold-start empty state — the app is
/// useless until a reference exists, and new users may have nothing saved.
/// Original Gemini (Nano Banana) stills, bundled in Assets.xcassets so
/// importing them stays fully offline. Fashion / travel poses the analyzer
/// can guide against.
enum SampleReferencePack {
    static let assetNames = [
        "SampleRefCinqueFloral",
        "SampleRefAlleyWhite",
        "SampleRefCoastalDress",
        "SampleRefPatioGlance",
        "SampleRefDinnerTable",
        "SampleRefPromenadeGlance",
        "SampleRefBeachWalk",
        "SampleRefCafeSip",
        "SampleRefStoneLean",
        "SampleRefSofaProfile",
    ]
}
