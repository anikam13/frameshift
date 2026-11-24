import Foundation

/// Bundled starter references for the cold-start empty state — the app is
/// useless until a reference exists, and new users may have nothing saved.
/// Bundled in Assets.xcassets so first launch works fully offline. Newer
/// Explore photos arrive through `RemoteReferenceFeed` without an app update;
/// this pack stays the offline fallback.
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
        "SampleRefVelvetBooth",
        "SampleRefEspressoWindow",
        "SampleRefStorefrontLean",
        "SampleRefGardenPatio",
        "SampleRefSunsetRail",
        "SampleRefNightShore",
        "SampleRefBalconyNight",
        "SampleRefPierSunset",
        "SampleRefCocktailToast",
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
        "SampleRefVelvetBooth":     [.portraits, .seated],
        "SampleRefEspressoWindow":  [.portraits, .seated],
        "SampleRefStorefrontLean":  [.fullBody],
        "SampleRefGardenPatio":     [.portraits, .seated],
        "SampleRefSunsetRail":      [.portraits],
        "SampleRefNightShore":      [.portraits],
        "SampleRefBalconyNight":    [.portraits],
        "SampleRefPierSunset":      [.portraits],
        "SampleRefCocktailToast":   [.portraits, .seated],
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
        "SampleRefVelvetBooth":     .women,
        "SampleRefEspressoWindow":  .men,
        "SampleRefStorefrontLean":  .men,
        "SampleRefGardenPatio":     .women,
        "SampleRefSunsetRail":      .women,
        "SampleRefNightShore":      .women,
        "SampleRefBalconyNight":    .men,
        "SampleRefPierSunset":      .men,
        "SampleRefCocktailToast":   .women,
    ]
}
