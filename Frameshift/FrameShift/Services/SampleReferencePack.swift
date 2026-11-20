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

    /// Hand-assigned Explore chips for the curated set (D-7; O-3). Curated
    /// photos are tagged rather than classified so chips work before (or
    /// without) Vision. No couples/group photos yet, so those chips hide.
    static let tags: [String: Set<CompositionFilter>] = [
        "SampleRefCinqueFloral":    [.portraits],
        "SampleRefAlleyWhite":      [.fullBody],
        "SampleRefCoastalDress":    [.fullBody],
        "SampleRefPatioGlance":     [.fullBody],
        "SampleRefDinnerTable":     [.portraits, .seated],
        "SampleRefPromenadeGlance": [.portraits],
        "SampleRefBeachWalk":       [.fullBody],
        "SampleRefCafeSip":         [.fullBody, .seated],
        "SampleRefStoneLean":       [.fullBody],
        "SampleRefSofaProfile":     [.fullBody, .seated],
    ]

    /// Explore's Women / Men toggle. Hand-assigned like `tags`.
    enum Subject: Hashable { case women, men }
    static let subjects: [String: Subject] = [
        "SampleRefCinqueFloral":    .women,
        "SampleRefAlleyWhite":      .women,
        "SampleRefCoastalDress":    .women,
        "SampleRefPatioGlance":     .women,
        "SampleRefDinnerTable":     .women,
        "SampleRefPromenadeGlance": .women,
        "SampleRefBeachWalk":       .men,
        "SampleRefCafeSip":         .men,
        "SampleRefStoneLean":       .men,
        "SampleRefSofaProfile":     .men,
    ]
}
