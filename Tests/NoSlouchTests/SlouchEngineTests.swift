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

  func testResetTransientStateClearsTimers() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    // Bad reading at t=0
    _ = analyzer.update(pitch: 5.0, at: Date(timeIntervalSince1970: 0.0))
    
    // Reset transient state
    analyzer.resetTransientState()
    
    // Bad reading at t=1. It should NOT trigger bad state instantly, because timer was reset
    XCTAssertEqual(analyzer.update(pitch: 5.0, at: Date(timeIntervalSince1970: 1.0)), .good)
    
    // Hold for 2 seconds from t=1 -> t=3
    XCTAssertEqual(analyzer.update(pitch: 5.0, at: Date(timeIntervalSince1970: 2.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 5.0, at: Date(timeIntervalSince1970: 3.0)), .bad)
  }
}
