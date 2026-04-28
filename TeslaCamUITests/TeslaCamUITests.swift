import XCTest

final class TeslaCamUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testBlankLaunchShowsOnboarding() throws {
    let app = launchApp(mode: "blank")

    XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testDefaultLaunchShowsOnboarding() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSampleLaunchShowsPlaybackAndExport() throws {
    let app = launchApp(mode: "sample")

    XCTAssertTrue(app.buttons["export-video"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["toggle-playback"].exists)
    XCTAssertTrue(app.otherElements["merged-timeline-track"].exists)
  }

  @MainActor
  func testSampleExportShowsBlockingOverlay() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = "sample"
    app.launchEnvironment["TESLACAM_DEBUG_EXPORT_DIR"] = NSTemporaryDirectory()
    app.launch()

    XCTAssertTrue(app.buttons["export-video"].waitForExistence(timeout: 5))
    app.buttons["export-video"].click()

    XCTAssertTrue(app.descendants(matching: .any)["export-overlay"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSamplePlaybackToggleResponds() throws {
    let app = launchApp(mode: "sample")

    let playbackButton = app.buttons["toggle-playback"]
    XCTAssertTrue(playbackButton.waitForExistence(timeout: 5))
    XCTAssertEqual(playbackButton.value as? String, "paused")
    playbackButton.click()

    let playingPredicate = NSPredicate(format: "value == %@", "playing")
    expectation(for: playingPredicate, evaluatedWith: playbackButton)
    waitForExpectations(timeout: 5)
  }

  @MainActor
  func testSampleQuickRangeAndCameraButtonsRespond() throws {
    let app = launchApp(mode: "sample")

    let wholeTimeline = app.buttons["range-whole-timeline"]
    let currentMinute = app.buttons["range-current-minute"]
    let lastFive = app.buttons["range-last-5m"]
    let lastFifteen = app.buttons["range-last-15m"]
    let frontCamera = app.buttons["camera-front"]

    XCTAssertTrue(wholeTimeline.waitForExistence(timeout: 5))
    XCTAssertTrue(currentMinute.exists)
    XCTAssertTrue(lastFive.exists)
    XCTAssertTrue(lastFifteen.exists)
    XCTAssertTrue(frontCamera.exists)

    wholeTimeline.click()
    currentMinute.click()
    lastFive.click()
    lastFifteen.click()

    let initialFrontValue = frontCamera.value as? String
    frontCamera.click()
    let toggledFrontValue = frontCamera.value as? String

    XCTAssertNotEqual(initialFrontValue, toggledFrontValue)
  }

  private func launchApp(mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = mode
    app.launch()
    return app
  }
}
