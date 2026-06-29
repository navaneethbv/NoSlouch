import CoreMotion
import Foundation

final class AirPodsMotionProvider: NSObject, HeadMotionProvider {
  var onReading: ((HeadMotionReading) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?

  private let manager = CMHeadphoneMotionManager()
  private let queue: OperationQueue
  private let minimumReadingInterval: TimeInterval = 0.1
  private var lastReadingAt: Date?

  override init() {
    queue = OperationQueue()
    queue.name = "NoSlouch.AirPodsMotionProvider"
    queue.qualityOfService = .userInitiated
    super.init()
    manager.delegate = self
  }

  func start() {
    guard manager.isDeviceMotionAvailable else {
      onConnectionChanged?(false)
      return
    }

    manager.startConnectionStatusUpdates()
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
      guard let self, let motion else {
        return
      }

      let now = Date()
      if let lastReadingAt = self.lastReadingAt,
        now.timeIntervalSince(lastReadingAt) < self.minimumReadingInterval
      {
        return
      }
      self.lastReadingAt = now

      let sampleDate = Date(
        timeIntervalSinceNow: motion.timestamp - ProcessInfo.processInfo.systemUptime)
      let reading = HeadMotionReading(
        pitch: motion.attitude.pitch.degrees,
        roll: motion.attitude.roll.degrees,
        yaw: motion.attitude.yaw.degrees,
        timestamp: sampleDate
      )
      self.onReading?(reading)
    }
  }

  func stop() {
    manager.stopDeviceMotionUpdates()
    manager.stopConnectionStatusUpdates()
    lastReadingAt = nil
  }
}

extension AirPodsMotionProvider: CMHeadphoneMotionManagerDelegate {
  func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
    onConnectionChanged?(true)
  }

  func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
    onConnectionChanged?(false)
  }
}

extension Double {
  fileprivate var degrees: Double {
    self * 180.0 / .pi
  }
}
