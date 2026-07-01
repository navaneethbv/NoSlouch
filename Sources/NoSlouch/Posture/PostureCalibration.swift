public struct PostureCalibration: Equatable {
  public var baselinePitch: Double
  public var baselineRoll: Double

  public init(baselinePitch: Double, baselineRoll: Double = 0) {
    self.baselinePitch = baselinePitch
    self.baselineRoll = baselineRoll
  }
}
