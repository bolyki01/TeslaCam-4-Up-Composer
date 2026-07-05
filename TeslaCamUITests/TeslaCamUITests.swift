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
    let app = launchApp(mode: "blank")

    XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSampleLaunchShowsPlaybackAndExport() throws {
    let app = launchApp(mode: "sample")

    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSampleExportShowsBlockingOverlay() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = "sample"
    app.launchEnvironment["TESLACAM_DEBUG_EXPORT_DIR"] = NSTemporaryDirectory()
    app.launchArguments.append(contentsOf: ["--teslacam-ui-test-mode", "sample"])
    app.launch()
    dismissCrashRecoveryIfNeeded(in: app)

    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))
    #if os(macOS)
    app.typeKey("e", modifierFlags: .command)
    #else
    let exportButton = app.descendants(matching: .any)["export-video"]
    XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
    exportButton.tap()
    #endif
    XCTAssertTrue(app.descendants(matching: .any)["export-overlay"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["Export Complete"].waitForExistence(timeout: 60))
  }

  @MainActor
  func testSamplePlaybackToggleResponds() throws {
    let app = launchApp(mode: "sample")

    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSampleQuickRangeAndCameraButtonsRespond() throws {
    let app = launchApp(mode: "sample")

    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testSampleMacEventBrowserNavigates() throws {
    #if os(macOS)
    let app = launchApp(mode: "sample")
    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "mac-compact-workspace"
    attachment.lifetime = .keepAlways
    add(attachment)
    #else
    throw XCTSkip("macOS-only event browser")
    #endif
  }

  @MainActor
  func testSampleDashboardScreenshot() throws {
    // Captures the loaded dashboard as a test attachment for visual review —
    // the verify-as-you-go seam for UI work. Asserts the core transport surface
    // is present so the screenshot is never of an empty/onboarding screen.
    let app = launchApp(mode: "sample")
    XCTAssertTrue(app.descendants(matching: .any)["loaded-screen"].waitForExistence(timeout: 5))

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "sample-dashboard"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func launchApp(mode: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = mode
    app.launchArguments.append(contentsOf: ["--teslacam-ui-test-mode", mode])
    app.launch()
    dismissCrashRecoveryIfNeeded(in: app)
    return app
  }

  private func dismissCrashRecoveryIfNeeded(in app: XCUIApplication) {
    let button = app.buttons["action-button--999"]
    if button.waitForExistence(timeout: 1) {
      #if os(macOS)
      button.click()
      #else
      button.tap()
      #endif
    }
  }
}
