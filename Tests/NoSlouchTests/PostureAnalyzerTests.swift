import Foundation
import XCTest

@testable import NoSlouch

final class PostureAnalyzerTests: XCTestCase {
  func testStartsUnknownBeforeCalibration() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0
    )

    XCTAssertEqual(analyzer.state, .unknown)
    XCTAssertNil(analyzer.calibration)
    XCTAssertNil(analyzer.smoothedPitch)
    XCTAssertEqual(analyzer.update(pitch: 0.0, at: Date(timeIntervalSince1970: 0)), .unknown)
  }

  func testCalibrationStartsGood() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0
    )

    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.state, .good)
    XCTAssertEqual(analyzer.calibration, PostureCalibration(baselinePitch: 20.0))
    XCTAssertEqual(analyzer.smoothedPitch, 20.0)
  }

  func testSustainedDropBecomesBad() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 1.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 2.0)), .bad)
  }

  func testBriefDropDoesNotBecomeBad() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 1.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 2.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 3.0)), .good)
  }

  func testRecoveryReturnsToGood() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 2.0)), .bad)
    XCTAssertEqual(analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 2.5)), .bad)
    XCTAssertEqual(analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 3.5)), .good)
  }

  func testInvertedPitchUsesOppositeDrop() {
    var analyzer = PostureAnalyzer(
      thresholdDegrees: 10.0,
      holdSeconds: 1.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0,
      invertedPitch: true
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 30.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 30.0, at: Date(timeIntervalSince1970: 1.0)), .bad)
  }
}
