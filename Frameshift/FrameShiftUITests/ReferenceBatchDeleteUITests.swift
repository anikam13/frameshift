import XCTest

/// Documents the References batch-delete flow and the automation gap found
/// while fixing it (July 2026).
///
/// The original bug: the selection bar was a bottom `safeAreaInset` inside
/// `ReferencesView`, but the camera chrome is another bottom inset layered
/// on top of the whole view — the chrome's material overlapped the bar and
/// swallowed every tap aimed at its trash button ("can mass select but not
/// mass delete"). The fix moved the selection controls into the navigation
/// toolbar (Photos-style: Cancel · count · trash).
///
/// These tests are skipped because XCUITest synthetic touches do not land
/// anywhere inside `ReferencesView` in this nested hosting arrangement
/// (verified against grid cells, the old bottom bar, and even the Settings
/// gear), while real touches work. Verified instead via hierarchy-dump
/// geometry plus a simulator screenshot with the `-uitest-seed-references` /
/// `-uitest-start-selecting` launch arguments.
final class ReferenceBatchDeleteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBatchDeleteRemovesSelectedReferences() throws {
        throw XCTSkip("""
            Synthetic touches don't reach ReferencesView's subtree under \
            XCUITest; batch delete is verified manually. Launch the app with \
            -uitest-seed-references -uitest-start-selecting \
            -frameshift.hasCompletedOnboarding YES to reproduce the state.
            """)
    }
}
