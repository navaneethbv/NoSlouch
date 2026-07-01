import Foundation
import XCTest

@testable import NoSlouch

final class SlouchEngineTests: XCTestCase {
  func testStartsUnknownBeforeCalibration() {
    var analyzer = SlouchEngine(
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
    var analyzer = SlouchEngine(
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
    var analyzer = SlouchEngine(
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
    var analyzer = SlouchEngine(
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
    var analyzer = SlouchEngine(
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
    var analyzer = SlouchEngine(
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

  func testCurrentDropIsNilBeforeCalibration() {
    let analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0
    )

    XCTAssertNil(analyzer.currentDrop)
  }

  func testCurrentDropIsZeroAfterCalibration() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0
    )

    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.currentDrop, 0.0)
  }

  func testCurrentDropEqualsBaselineMinusSmoothedPitchAfterUpdate() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    _ = analyzer.update(pitch: 6.0, at: Date(timeIntervalSince1970: 0.0))

    XCTAssertEqual(analyzer.currentDrop, 14.0)
  }

  func testResetForNewSessionReturnsToGoodAndRequiresFreshHold() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 2.0)), .bad)

    analyzer.resetForNewSession()

    XCTAssertEqual(analyzer.state, .good)
    XCTAssertEqual(analyzer.smoothedPitch, 20.0)
    XCTAssertEqual(analyzer.currentDrop, 0.0)

    // A single below-baseline reading far in the future must NOT instantly flip to
    // bad — a fresh hold window is required after a session reset (BUG-1).
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 10_000.0)), .good)
  }

  func testTiltBeyondThresholdBecomesBadWhenEnabled() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0,
      tiltEnabled: true,
      tiltThresholdDegrees: 15.0
    )
    analyzer.calibrate(pitch: 20.0, roll: 0.0)

    // Pitch stays upright (drop 0); head tilts 20° > 15° tilt threshold.
    XCTAssertEqual(
      analyzer.update(pitch: 20.0, roll: 20.0, at: Date(timeIntervalSince1970: 0)), .good)
    XCTAssertEqual(
      analyzer.update(pitch: 20.0, roll: 20.0, at: Date(timeIntervalSince1970: 2)), .bad)
  }

  func testTiltIgnoredWhenDisabled() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0,
      tiltEnabled: false,
      tiltThresholdDegrees: 15.0
    )
    analyzer.calibrate(pitch: 20.0, roll: 0.0)

    XCTAssertEqual(
      analyzer.update(pitch: 20.0, roll: 40.0, at: Date(timeIntervalSince1970: 0)), .good)
    XCTAssertEqual(
      analyzer.update(pitch: 20.0, roll: 40.0, at: Date(timeIntervalSince1970: 2)), .good)
  }

  func testResetForNewSessionStaysUnknownWhenUncalibrated() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0
    )

    analyzer.resetForNewSession()

    XCTAssertEqual(analyzer.state, .unknown)
    XCTAssertNil(analyzer.smoothedPitch)
    XCTAssertNil(analyzer.currentDrop)
  }

  func testCurrentDropUsesOppositeSignWhenInverted() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0,
      invertedPitch: true
    )
    analyzer.calibrate(pitch: 20.0)

    _ = analyzer.update(pitch: 34.0, at: Date(timeIntervalSince1970: 0.0))

    XCTAssertEqual(analyzer.currentDrop, 14.0)
  }
}
