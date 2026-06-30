import CoreMotion
import Foundation

final class AirPodsMotionProvider: NSObject, HeadMotionProvider {
  var isAvailable: Bool {
    manager.isDeviceMotionAvailable
  }

  var onReading: ((HeadMotionReading) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onError: ((String) -> Void)?

  private let manager = CMHeadphoneMotionManager()
  private let queue: OperationQueue
  private let minimumReadingInterval: TimeInterval = 0.1
  private var lastReadingAt: Date?

  override init() {
    queue = OperationQueue()
    queue.name = "NoSlouch.AirPodsMotionProvider"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 1
    super.init()
    manager.delegate = self
  }

  func start() {
    guard manager.isDeviceMotionAvailable else {
      DispatchQueue.main.async { [weak self] in
        self?.onError?(
          "Headphone motion unavailable. Connect AirPods (Pro/3/Max) or Beats Fit Pro."
        )
        self?.onConnectionChanged?(false)
      }
      return
    }

    manager.startConnectionStatusUpdates()
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
      guard let self else { return }
      if let error {
        DispatchQueue.main.async { self.onError?(error.localizedDescription) }
        return
      }
      guard let motion else { return }

      // Throttle on the background queue to avoid flooding main (NB-10 fix).
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
      DispatchQueue.main.async { self.onReading?(reading) }
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
    DispatchQueue.main.async { [weak self] in
      self?.onConnectionChanged?(true)
    }
  }

  func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
    DispatchQueue.main.async { [weak self] in
      self?.onConnectionChanged?(false)
    }
  }
}

extension Double {
  fileprivate var degrees: Double {
    self * 180.0 / .pi
  }
}
