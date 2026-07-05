import XCTest

@testable import NoSlouch

final class URLCommandRouterTests: XCTestCase {
  private func url(_ string: String) -> URL {
    URL(string: string)!
  }

  func testParsesSimpleCommands() {
    XCTAssertEqual(URLCommand.parse(url("noslouch://start")), .start)
    XCTAssertEqual(URLCommand.parse(url("noslouch://stop")), .stop)
    XCTAssertEqual(URLCommand.parse(url("noslouch://calibrate")), .calibrate)
    XCTAssertEqual(URLCommand.parse(url("noslouch://resume")), .resume)
  }

  func testParsesSnoozeWithMinutes() {
    XCTAssertEqual(URLCommand.parse(url("noslouch://snooze?minutes=30")), .snooze(minutes: 30))
  }

  func testSnoozeDefaultsToFifteenMinutes() {
    XCTAssertEqual(URLCommand.parse(url("noslouch://snooze")), .snooze(minutes: 15))
  }

  func testRejectsInvalidSnoozeMinutes() {
    XCTAssertNil(URLCommand.parse(url("noslouch://snooze?minutes=0")))
    XCTAssertNil(URLCommand.parse(url("noslouch://snooze?minutes=-5")))
    XCTAssertNil(URLCommand.parse(url("noslouch://snooze?minutes=soon")))
  }

  func testRejectsForeignSchemesAndUnknownCommands() {
    XCTAssertNil(URLCommand.parse(url("https://start")))
    XCTAssertNil(URLCommand.parse(url("noslouch://selfdestruct")))
  }

  func testHostIsCaseInsensitive() {
    XCTAssertEqual(URLCommand.parse(url("NoSlouch://Start")), .start)
  }
}
