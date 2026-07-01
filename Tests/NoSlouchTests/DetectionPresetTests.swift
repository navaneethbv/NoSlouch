import XCTest

@testable import NoSlouch

final class DetectionPresetTests: XCTestCase {
  func testStandardMatchesDefaultSettings() {
    XCTAssertEqual(DetectionPreset.matching(AppSettings()), .standard)
  }

  func testPresetValuesAreOrdered() {
    XCTAssertGreaterThan(
      DetectionPreset.gentle.thresholdDegrees, DetectionPreset.strict.thresholdDegrees)
    XCTAssertGreaterThan(
      DetectionPreset.gentle.holdSeconds, DetectionPreset.strict.holdSeconds)
  }

  func testMatchingStrict() {
    let settings = AppSettings(thresholdDegrees: 8, holdSeconds: 2, recoverSeconds: 1)
    XCTAssertEqual(DetectionPreset.matching(settings), .strict)
  }

  func testCustomValuesMatchNoPreset() {
    var settings = AppSettings()
    settings.thresholdDegrees = 11
    XCTAssertNil(DetectionPreset.matching(settings))
  }
}
