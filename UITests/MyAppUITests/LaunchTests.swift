import XCTest

/// UI tests stay XCTest — Swift Testing has no XCUI integration.
///
/// `nonisolated` on the class is load-bearing: `XCTestCase.setUp()` is a
/// nonisolated override, and under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
/// an unannotated subclass would try to override it with a main-actor-isolated
/// method. The test methods are individually `@MainActor` because
/// `XCUIApplication` is.
///
/// This class doubles as the fastlane `snapshot` driver: every `snapshot(_:)`
/// call below becomes one App Store screenshot per device and locale.
nonisolated final class LaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndCaptureScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["-uiTestMode", "1"]
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "The app never reached the foreground."
        )
        snapshot("01_Home")

        // Accessibility identifiers are the contract between the app and this
        // test. Never assert on label text — it is localized.
        let startButton = app.buttons["startSessionButton"]
        XCTAssertTrue(
            startButton.waitForExistence(timeout: 10),
            "Missing accessibility identifier 'startSessionButton' on the home screen."
        )

        startButton.tap()
        snapshot("02_ActiveSession")
    }

    @MainActor
    func testRelaunchRestoresState() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMode", "1"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "The app failed to relaunch after termination."
        )
    }
}
