import Foundation

public struct PostureSession: Equatable {
    public var startedAt: Date
    public var endedAt: Date
    public var badSeconds: TimeInterval

    public var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    public init(startedAt: Date, endedAt: Date, badSeconds: TimeInterval) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.badSeconds = badSeconds
    }
}
