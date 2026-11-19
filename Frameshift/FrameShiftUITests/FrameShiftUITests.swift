import XCTest

/// Flow tests for the redesigned shell. Every test runs on in-memory data
/// (`-uitest-seed-references`: curated set + one import, no disk writes).
/// Tours are switched off through the launch-argument defaults domain,
/// which never persists, unless a test is about the tour.
final class FrameShiftUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(tours: Bool = false, session: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let done = tours ? "NO" : "YES"
        app.launchArguments = [
            "-uitest-seed-references",
            "-frameshift.tour.explore.done", done,
            "-frameshift.tour.camera.done", done,
            "-frameshift.welcome.done", "YES",
        ]
        if session { app.launchArguments.append("-preview-seed-session") }
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)[label].firstMatch
    }

    @MainActor
    func testLaunchesToGalleryHome() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["FrameShift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Explore"].exists)
        XCTAssertTrue(app.buttons["Yours"].exists)
        // No session yet → no Resume Camera (D-4).
        XCTAssertFalse(app.buttons["Resume Camera"].exists)
    }

    @MainActor
    func testYoursShowsImports() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["Yours"].waitForExistence(timeout: 5))
        app.buttons["Yours"].tap()
        XCTAssertTrue(element(app, "Your reference").waitForExistence(timeout: 3))
        XCTAssertFalse(element(app, "Curated reference").exists)
    }

    @MainActor
    func testExploreTourStepsThrough() throws {
        let app = launch(tours: true)
        XCTAssertTrue(app.staticTexts["Start with a photo"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Use your own photo"].waitForExistence(timeout: 3))
        app.buttons["Got It"].tap()
        XCTAssertTrue(app.staticTexts["Use your own photo"].waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testPreviewOpensWithRecreateAndGoesBack() throws {
        let app = launch()
        let tile = element(app, "Curated reference")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(app.buttons["Recreate"].waitForExistence(timeout: 3))
        app.buttons["Back"].tap()
        XCTAssertTrue(app.buttons["Recreate"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["FrameShift"].exists)
    }

    @MainActor
    func testSettingsAndStorage() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 5))
        app.buttons["More"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Permissions"].waitForExistence(timeout: 3))
        app.buttons["Storage"].tap()
        XCTAssertTrue(app.staticTexts["Stored by FrameShift"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Clear Imported References"].exists)
        XCTAssertFalse(app.buttons["Clear Captured Copies"].exists)
    }

    @MainActor
    func testCameraExplanationNotNowReturnsToGallery() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .camera)
        app.launchArguments = [
            "-uitest-seed-references", "-preview-seed-session",
            "-frameshift.tour.explore.done", "YES",
            "-frameshift.tour.camera.done", "YES",
            "-frameshift.welcome.done", "YES",
        ]
        app.launch()
        // An active session shows Resume Camera (D-4).
        let resume = app.buttons["Resume Camera"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        XCTAssertTrue(app.staticTexts["Enable your camera"].waitForExistence(timeout: 3))
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.staticTexts["FrameShift"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
