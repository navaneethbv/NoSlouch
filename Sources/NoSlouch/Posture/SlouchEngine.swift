import Foundation

public struct SlouchEngine {
  public private(set) var state: SlouchState
  public private(set) var calibration: PostureCalibration?
  public private(set) var smoothedPitch: Double?
  public private(set) var smoothedRoll: Double?
  public private(set) var currentDrop: Double?
  public private(set) var currentTilt: Double?

  private let thresholdDegrees: Double
  private let holdSeconds: TimeInterval
  private let recoverSeconds: TimeInterval
  private let smoothingAlpha: Double
  private let invertedPitch: Bool
  private let tiltEnabled: Bool
  private let tiltThresholdDegrees: Double
  private var badStartedAt: Date?
  private var recoveryStartedAt: Date?

  public init(
    thresholdDegrees: Double,
    holdSeconds: TimeInterval,
    recoverSeconds: TimeInterval,
    smoothingAlpha: Double = 0.2,
    invertedPitch: Bool = false,
    tiltEnabled: Bool = false,
    tiltThresholdDegrees: Double = 15.0
  ) {
    self.state = .unknown
    self.calibration = nil
    self.smoothedPitch = nil
    self.smoothedRoll = nil
    self.currentDrop = nil
    self.currentTilt = nil
    self.thresholdDegrees = thresholdDegrees
    self.holdSeconds = holdSeconds
    self.recoverSeconds = recoverSeconds
    self.smoothingAlpha = smoothingAlpha
    self.invertedPitch = invertedPitch
    self.tiltEnabled = tiltEnabled
    self.tiltThresholdDegrees = tiltThresholdDegrees
    self.badStartedAt = nil
    self.recoveryStartedAt = nil
  }

  public mutating func calibrate(pitch: Double, roll: Double = 0) {
    calibration = PostureCalibration(baselinePitch: pitch, baselineRoll: roll)
    smoothedPitch = pitch
    smoothedRoll = roll
    currentDrop = 0
    currentTilt = 0
    state = .good
    badStartedAt = nil
    recoveryStartedAt = nil
  }

  public mutating func updateBaselinePitch(_ pitch: Double) {
    if var cal = calibration {
      cal.baselinePitch = pitch
      calibration = cal
    }
  }

  /// Clears the transient hold/recover timers and smoothing so a new monitoring
  /// session starts cleanly, while preserving the calibration baseline (BUG-1).
  public mutating func resetForNewSession() {
    badStartedAt = nil
    recoveryStartedAt = nil
    smoothedPitch = calibration?.baselinePitch
    smoothedRoll = calibration?.baselineRoll
    currentDrop = calibration == nil ? nil : 0
    currentTilt = calibration == nil ? nil : 0
    state = calibration == nil ? .unknown : .good
  }

  public mutating func update(pitch: Double, roll: Double = 0, at timestamp: Date) -> SlouchState {
    updateSmoothedPitch(with: pitch)
    updateSmoothedRoll(with: roll)

    guard let calibration, let smoothedPitch else {
      state = .unknown
      return state
    }

    let drop =
      invertedPitch
      ? smoothedPitch - calibration.baselinePitch
      : calibration.baselinePitch - smoothedPitch
    currentDrop = drop

    let tilt = abs((smoothedRoll ?? calibration.baselineRoll) - calibration.baselineRoll)
    currentTilt = tilt

    // "Offending" = forward-head drop past the threshold, or (when tilt detection
    // is on) sustained lateral head tilt past its own threshold (A1).
    let isOffending = drop >= thresholdDegrees || (tiltEnabled && tilt >= tiltThresholdDegrees)

    switch state {
    case .unknown:
      assertionFailure("update reached .unknown after calibration guard should have exited")
    case .good:
      updateGoodState(isOffending: isOffending, at: timestamp)
    case .bad:
      updateBadState(isOffending: isOffending, at: timestamp)
    }

    return state
  }

  private mutating func updateSmoothedPitch(with pitch: Double) {
    guard let current = smoothedPitch else {
      smoothedPitch = pitch
      return
    }
    smoothedPitch = current + smoothingAlpha * (pitch - current)
  }

  private mutating func updateSmoothedRoll(with roll: Double) {
    guard let current = smoothedRoll else {
      smoothedRoll = roll
      return
    }
    smoothedRoll = current + smoothingAlpha * (roll - current)
  }

  private mutating func updateGoodState(isOffending: Bool, at timestamp: Date) {
    recoveryStartedAt = nil

    if !isOffending {
      badStartedAt = nil
      return
    }

    if badStartedAt == nil {
      badStartedAt = timestamp
    }

    if let badStartedAt, timestamp.timeIntervalSince(badStartedAt) >= holdSeconds {
      state = .bad
      recoveryStartedAt = nil
    }
  }

  private mutating func updateBadState(isOffending: Bool, at timestamp: Date) {
    badStartedAt = nil

    if isOffending {
      recoveryStartedAt = nil
      return
    }

    if recoveryStartedAt == nil {
      recoveryStartedAt = timestamp
    }

    if let recoveryStartedAt, timestamp.timeIntervalSince(recoveryStartedAt) >= recoverSeconds {
      state = .good
      badStartedAt = nil
    }
  }
}
