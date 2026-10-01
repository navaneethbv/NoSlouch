import XCTest

@testable import NoSlouch

final class PostureNotifierMessageTests: XCTestCase {
  func testTestNotificationCannotTriggerPostureActionsOrDuplicateAudio() {
    let request = PostureNotifier.testNotificationRequest()
    XCTAssertEqual(request.identifier, "noslouch.test")
    XCTAssertTrue(request.content.title.contains("test"))
    XCTAssertTrue(request.content.categoryIdentifier.isEmpty)
    XCTAssertNil(request.content.sound)
    XCTAssertNil(request.trigger)
  }

  func testNotificationContentDoesNotRequestAdditionalSystemAudio() {
    XCTAssertNil(PostureNotifier.silentContent().sound)
  }

  func testUsesDropMessageWhenNoCustomMessages() {
    let settings = AppSettings()
    XCTAssertEqual(
      PostureNotifier.nudgeMessage(settings: settings, drop: 14.4, index: 0),
      "Your head dropped 14° below your baseline."
    )
  }

  func testGenericFallbackWhenNoDropAndNoCustomMessages() {
    let settings = AppSettings()
    XCTAssertEqual(
      PostureNotifier.nudgeMessage(settings: settings, drop: nil, index: 0),
      "Sit up straight"
    )
  }

  func testRotatesThroughCustomMessages() {
    let settings = AppSettings(customNudgeMessages: ["A", "B", "C"])
    XCTAssertEqual(PostureNotifier.nudgeMessage(settings: settings, drop: 20, index: 0), "A")
    XCTAssertEqual(PostureNotifier.nudgeMessage(settings: settings, drop: 20, index: 1), "B")
    XCTAssertEqual(PostureNotifier.nudgeMessage(settings: settings, drop: 20, index: 2), "C")
    XCTAssertEqual(PostureNotifier.nudgeMessage(settings: settings, drop: 20, index: 3), "A")
  }

  func testIgnoresBlankCustomMessages() {
    let settings = AppSettings(customNudgeMessages: ["   ", ""])
    XCTAssertEqual(
      PostureNotifier.nudgeMessage(settings: settings, drop: nil, index: 0),
      "Sit up straight"
    )
  }
}
