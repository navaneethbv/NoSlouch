import Foundation

public struct PostureSession: Equatable {
  public var startedAt: Date
  public var endedAt: Date
  public var badSeconds: TimeInterval
  public var goodSeconds: TimeInterval
  public var slouchEvents: Int

  public var duration: TimeInterval {
    endedAt.timeIntervalSince(startedAt)
  }

  public init(
    startedAt: Date,
    endedAt: Date,
    badSeconds: TimeInterval,
    goodSeconds: TimeInterval = 0,
    slouchEvents: Int = 0
  ) {
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.badSeconds = badSeconds
    self.goodSeconds = goodSeconds
    self.slouchEvents = slouchEvents
  }
}
