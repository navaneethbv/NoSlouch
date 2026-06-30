import Foundation

public struct SlouchEngine {
  public private(set) var state: SlouchState
  public private(set) var calibration: PostureCalibration?
  public private(set) var smoothedPitch: Double?
  public private(set) var currentDrop: Double?

  private let thresholdDegrees: Double
  private let holdSeconds: TimeInterval
  private let recoverSeconds: TimeInterval
  private let smoothingAlpha: Double
  private let invertedPitch: Bool
  private var badStartedAt: Date?
  private var recoveryStartedAt: Date?

  public init(
    thresholdDegrees: Double,
    holdSeconds: TimeInterval,
    recoverSeconds: TimeInterval,
    smoothingAlpha: Double = 0.2,
    invertedPitch: Bool = false
  ) {
    self.state = .unknown
    self.calibration = nil
    self.smoothedPitch = nil
    self.currentDrop = nil
    self.thresholdDegrees = thresholdDegrees
    self.holdSeconds = holdSeconds
    self.recoverSeconds = recoverSeconds
    self.smoothingAlpha = smoothingAlpha
    self.invertedPitch = invertedPitch
    self.badStartedAt = nil
    self.recoveryStartedAt = nil
  }

  public mutating func calibrate(pitch: Double) {
    calibration = PostureCalibration(baselinePitch: pitch)
    smoothedPitch = pitch
    currentDrop = 0
    state = .good
    badStartedAt = nil
    recoveryStartedAt = nil
  }

  public mutating func resetTransientState() {
    badStartedAt = nil
    recoveryStartedAt = nil
    smoothedPitch = calibration?.baselinePitch
    currentDrop = calibration == nil ? nil : 0
    state = calibration == nil ? .unknown : .good
  }

  public mutating func updateBaselinePitch(_ pitch: Double) {
    if var cal = calibration {
      cal.baselinePitch = pitch
      calibration = cal
    }
  }

  public mutating func update(pitch: Double, at timestamp: Date) -> SlouchState {
    updateSmoothedPitch(with: pitch)

    guard let calibration, let smoothedPitch else {
      state = .unknown
      return state
    }

    let drop =
      invertedPitch
      ? smoothedPitch - calibration.baselinePitch
      : calibration.baselinePitch - smoothedPitch
    currentDrop = drop
    let isBelowThreshold = drop < thresholdDegrees

    switch state {
    case .unknown:
      assertionFailure("update reached .unknown after calibration guard should have exited")
    case .good:
      updateGoodState(isBelowThreshold: isBelowThreshold, at: timestamp)
    case .bad:
      updateBadState(isBelowThreshold: isBelowThreshold, at: timestamp)
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

  private mutating func updateGoodState(isBelowThreshold: Bool, at timestamp: Date) {
    recoveryStartedAt = nil

    if isBelowThreshold {
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

  private mutating func updateBadState(isBelowThreshold: Bool, at timestamp: Date) {
    badStartedAt = nil

    if !isBelowThreshold {
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
