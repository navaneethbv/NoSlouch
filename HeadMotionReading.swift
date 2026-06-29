import Foundation

public struct HeadMotionReading: Equatable {
  public var pitch: Double
  public var roll: Double
  public var yaw: Double
  public var timestamp: Date

  public init(pitch: Double, roll: Double, yaw: Double, timestamp: Date) {
    self.pitch = pitch
    self.roll = roll
    self.yaw = yaw
    self.timestamp = timestamp
  }
}
