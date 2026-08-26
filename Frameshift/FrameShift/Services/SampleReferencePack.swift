import Foundation

/// Bundled starter references for the cold-start empty state — the app is
/// useless until a reference exists, and new users may have nothing saved.
/// All photos are from Pexels (license: free to use, no attribution
/// required), bundled in Assets.xcassets so importing them stays fully
/// offline. Chosen as fashion / urban full-body poses the analyzer can
/// guide against.
///
/// Provenance (pexels.com/photo/<id>):
///   SampleRefFringeWalk   29444963  full-body street walk, fringe sweater
///   SampleRefWalkwayLean  28765787  full-body lean on railing, golden hour
///   SampleRefBeretCoat    10815502  three-quarter urban chic, beret + coat
///   SampleRefPlaidGlance  37245847  full-body over-shoulder glance, plaid
///   SampleRefWinterCap    7255442   full-body winter street style, flat cap
///   SampleRefGrayCoat     9571995   full-body smart-casual, gray overcoat
enum SampleReferencePack {
    static let assetNames = [
        "SampleRefFringeWalk",
        "SampleRefWalkwayLean",
        "SampleRefBeretCoat",
        "SampleRefPlaidGlance",
        "SampleRefWinterCap",
        "SampleRefGrayCoat",
    ]
}
