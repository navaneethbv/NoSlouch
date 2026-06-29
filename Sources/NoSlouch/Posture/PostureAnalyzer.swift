import Foundation

public struct PostureAnalyzer {
  public private(set) var state: PostureState
  public private(set) var calibration: PostureCalibration?
  public private(set) var smoothedPitch: Double?

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
    state = .good
    badStartedAt = nil
    recoveryStartedAt = nil
  }

  public mutating func update(pitch: Double, at timestamp: Date) -> PostureState {
    updateSmoothedPitch(with: pitch)

    guard let calibration, let smoothedPitch else {
      state = .unknown
      return state
    }

    let drop =
      invertedPitch
      ? smoothedPitch - calibration.baselinePitch
      : calibration.baselinePitch - smoothedPitch
    let isBelowThreshold = drop < thresholdDegrees

    switch state {
    case .unknown:
      state = isBelowThreshold ? .good : .unknown
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
