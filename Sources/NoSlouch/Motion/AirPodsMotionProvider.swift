import CoreMotion
import Foundation

final class AirPodsMotionProvider: NSObject, HeadMotionProvider {
    var onReading: ((HeadMotionReading) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue

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
            guard let motion else {
                return
            }

            let reading = HeadMotionReading(
                pitch: motion.attitude.pitch.degrees,
                roll: motion.attitude.roll.degrees,
                yaw: motion.attitude.yaw.degrees,
                timestamp: Date()
            )
            self?.onReading?(reading)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
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

private extension Double {
    var degrees: Double {
        self * 180.0 / .pi
    }
}
