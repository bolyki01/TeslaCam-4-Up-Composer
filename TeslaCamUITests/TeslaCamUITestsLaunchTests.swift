import XCTest

final class TeslaCamUITestsLaunchTests: XCTestCase {
  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchScreenshot() throws {
    let app = XCUIApplication()
    app.launchEnvironment["TESLACAM_UI_TEST_MODE"] = "blank"
    app.launch()

    XCTAssertTrue(app.buttons["Choose Folder"].waitForExistence(timeout: 5))

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "TeslaCam Onboarding"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
