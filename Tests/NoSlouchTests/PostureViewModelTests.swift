import Foundation
import XCTest
@testable import NoSlouch

final class PostureViewModelTests: XCTestCase {
    func testReadingAfterStopDoesNotNudge() {
        let motionProvider = FakeHeadMotionProvider()
        let audioMonitor = FakeAudioOutputMonitor(airPodsActive: true)
        let notifier = FakePostureNotifier()
        let settings = AppSettings(
            thresholdDegrees: 10,
            holdSeconds: 0,
            recoverSeconds: 1,
            alertCooldownSeconds: 0,
            soundEnabled: false,
            speechEnabled: false,
            invertedPitch: false
        )
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: audioMonitor,
            notifier: notifier,
            historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
            settings: settings
        )

        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
        viewModel.calibrate()
        viewModel.startMonitoring()
        viewModel.stopMonitoring()
        motionProvider.emit(pitch: 0, at: Date(timeIntervalSince1970: 1))
        motionProvider.emit(pitch: 0, at: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(notifier.nudgeCount, 0)
        XCTAssertFalse(viewModel.isMonitoring)
    }

    func testDisconnectStatusIsPreserved() {
        let motionProvider = FakeHeadMotionProvider()
        let audioMonitor = FakeAudioOutputMonitor(airPodsActive: true)
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: audioMonitor,
            notifier: FakePostureNotifier(),
            historyStore: PostureHistoryStore(defaults: isolatedDefaults())
        )

        viewModel.startMonitoring()
        audioMonitor.airPodsActive = false
        audioMonitor.onChange?(false)
        drainMainQueue()

        XCTAssertEqual(viewModel.statusText, "AirPods disconnected")
        XCTAssertFalse(viewModel.isMonitoring)
    }

    func testCalibrateShowsGoodCalibratedStatus() {
        let motionProvider = FakeHeadMotionProvider()
        let audioMonitor = FakeAudioOutputMonitor(airPodsActive: true)
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: audioMonitor,
            notifier: FakePostureNotifier(),
            historyStore: PostureHistoryStore(defaults: isolatedDefaults())
        )

        viewModel.startMonitoring()
        motionProvider.emit(pitch: -28.3, at: Date(timeIntervalSince1970: 0))
        drainMainQueue()
        viewModel.calibrate()

        XCTAssertEqual(viewModel.postureState, .good)
        XCTAssertEqual(viewModel.lastCalibratedPitch, -28.3)
        XCTAssertEqual(viewModel.statusText, "Calibrated, posture looks good")
    }

    func testEnableNotificationsRequestsPermission() {
        let notifier = FakePostureNotifier()
        notifier.nextAuthorizationResult = true
        let viewModel = PostureViewModel(
            motionProvider: FakeHeadMotionProvider(),
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: notifier,
            historyStore: PostureHistoryStore(defaults: isolatedDefaults())
        )

        viewModel.requestNotifications()
        drainMainQueue()

        XCTAssertTrue(viewModel.notificationsEnabled)
        XCTAssertEqual(notifier.requestCount, 2)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "NoSlouch.PostureViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
}

private final class FakeHeadMotionProvider: HeadMotionProvider {
    var onReading: ((HeadMotionReading) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    func start() {}
    func stop() {}

    func emit(pitch: Double, at timestamp: Date) {
        onReading?(HeadMotionReading(pitch: pitch, roll: 0, yaw: 0, timestamp: timestamp))
    }
}

private final class FakeAudioOutputMonitor: AudioOutputMonitoring {
    var airPodsActive: Bool
    var onChange: ((Bool) -> Void)?

    init(airPodsActive: Bool) {
        self.airPodsActive = airPodsActive
    }

    func start() {}
}

private final class FakePostureNotifier: PostureNotifying {
    private(set) var nudgeCount = 0
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0
    var nextAuthorizationResult = true

    func refreshAuthorization(completion: @escaping (Bool) -> Void) {
        completion(nextAuthorizationResult)
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestCount += 1
        completion(nextAuthorizationResult)
    }

    func openNotificationSettings() {
        openSettingsCount += 1
    }

    func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date) {
        nudgeCount += 1
    }
}
