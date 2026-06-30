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

  // MARK: - G4 Edge-case tests

  func testNaNPitchDoesNotCorruptState() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    // Feed a good reading, then a NaN, then a good reading
    _ = analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 0.0))
    _ = analyzer.update(pitch: Double.nan, at: Date(timeIntervalSince1970: 1.0))
    let state = analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 2.0))

    // smoothedPitch should still be finite, state should be .good
    XCTAssertEqual(state, .good)
    if let sp = analyzer.smoothedPitch {
      XCTAssertTrue(sp.isFinite)
    }
  }

  func testInfinityPitchDoesNotCorruptState() {
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    _ = analyzer.update(pitch: Double.infinity, at: Date(timeIntervalSince1970: 0.0))
    let state = analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 1.0))

    XCTAssertEqual(state, .good)
    if let sp = analyzer.smoothedPitch {
      XCTAssertTrue(sp.isFinite)
    }
  }

  func testExactlyAtThresholdBecomesBadAfterHold() {
    // The engine uses `drop < thresholdDegrees` (strict less-than).
    // drop == threshold is NOT below threshold, so it starts the hold timer.
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    // pitch of 10.0 → drop = 10.0, exactly at threshold → starts bad timer
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 1.9)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.0, at: Date(timeIntervalSince1970: 2.0)), .bad)
  }

  func testOneDegreeBelowThresholdStaysGood() {
    // drop = 9.999 (< 10.0) should remain good indefinitely
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    // pitch of 10.001 → drop = 9.999 < 10.0 → below threshold → stays good
    XCTAssertEqual(analyzer.update(pitch: 10.001, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 10.001, at: Date(timeIntervalSince1970: 2.5)), .good)
  }

  func testOneDegreeAboveThresholdBecomesBadAfterHold() {
    // drop = 11.0 (> 10.0) should become bad after holdSeconds
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 1.9)), .good)
    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 2.0)), .bad)
  }

  func testHoldTimerResetsOnBriefRecovery() {
    // Going good mid-hold resets the timer; you need a fresh holdSeconds after
    var analyzer = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    analyzer.calibrate(pitch: 20.0)

    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 0.0)), .good)
    // Briefly recover at t=1 (before hold completes)
    XCTAssertEqual(analyzer.update(pitch: 20.0, at: Date(timeIntervalSince1970: 1.0)), .good)
    // Start slouching again — timer must restart
    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 1.5)), .good)
    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 3.0)), .good)
    XCTAssertEqual(analyzer.update(pitch: 9.0, at: Date(timeIntervalSince1970: 3.5)), .bad)
  }

  func testInvertedPitchSymmetry() {
    // A non-inverted engine going -10° should behave the same as an inverted engine going +10°
    var normal = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0
    )
    normal.calibrate(pitch: 20.0)

    var inverted = SlouchEngine(
      thresholdDegrees: 10.0,
      holdSeconds: 2.0,
      recoverSeconds: 1.0,
      smoothingAlpha: 1.0,
      invertedPitch: true
    )
    inverted.calibrate(pitch: 20.0)

    for t in [0.0, 1.0, 2.0] {
      let ts = Date(timeIntervalSince1970: t)
      let normalState = normal.update(pitch: 10.0, at: ts)   // drop 10 -> bad path
      let invertedState = inverted.update(pitch: 30.0, at: ts) // rise 10 -> same bad path
      XCTAssertEqual(normalState, invertedState, "states should match at t=\(t)")
    }
  }
}
