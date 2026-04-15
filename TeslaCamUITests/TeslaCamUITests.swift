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

    XCTAssertTrue(app.buttons["Export Video"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Play"].exists || app.buttons["Pause"].exists)
    XCTAssertTrue(app.staticTexts["Timeline"].exists)
  }

  @MainActor
  func testSampleExportShowsBlockingOverlay() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = "sample"
    app.launchEnvironment["TESLACAM_DEBUG_EXPORT_DIR"] = NSTemporaryDirectory()
    app.launch()

    XCTAssertTrue(app.buttons["Export Video"].waitForExistence(timeout: 5))
    app.buttons["Export Video"].click()

    XCTAssertTrue(
      app.staticTexts["Exporting Video"].waitForExistence(timeout: 5) ||
      app.staticTexts["Export Complete"].waitForExistence(timeout: 5)
    )
  }

  private func launchApp(mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = mode
    app.launch()
    return app
  }
}
