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

    func testContinuingBadPostureNudgesAgainAfterCooldown() {
        let motionProvider = FakeHeadMotionProvider()
        let notifier = FakePostureNotifier()
        let settings = AppSettings(
            thresholdDegrees: 10,
            holdSeconds: 0,
            recoverSeconds: 1,
            alertCooldownSeconds: 5,
            soundEnabled: false,
            speechEnabled: false,
            invertedPitch: false
        )
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: notifier,
            historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
            settings: settings
        )

        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
        drainMainQueue()
        viewModel.calibrate()
        viewModel.startMonitoring()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
        drainMainQueue()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 3))
        drainMainQueue()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 7))
        drainMainQueue()

        XCTAssertEqual(notifier.nudgeCount, 2)
    }

    func testThreeBadPostureNudgesPauseRemindersForTenMinutes() {
        let motionProvider = FakeHeadMotionProvider()
        let notifier = FakePostureNotifier()
        let settings = AppSettings(
            thresholdDegrees: 10,
            holdSeconds: 0,
            recoverSeconds: 1,
            alertCooldownSeconds: 5,
            soundEnabled: false,
            speechEnabled: false,
            invertedPitch: false
        )
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: notifier,
            historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
            settings: settings
        )

        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
        drainMainQueue()
        viewModel.calibrate()
        viewModel.startMonitoring()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
        drainMainQueue()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 6))
        drainMainQueue()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 11))
        drainMainQueue()
        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 16))
        drainMainQueue()

        XCTAssertEqual(notifier.nudgeCount, 3)
        XCTAssertEqual(notifier.pauseNoticeCount, 1)
        XCTAssertEqual(viewModel.statusText, "Nudges paused for 10 min")

        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 610))
        drainMainQueue()

        XCTAssertEqual(notifier.nudgeCount, 3)

        motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 611))
        drainMainQueue()

        XCTAssertEqual(notifier.nudgeCount, 4)
    }

    func testGoodPostureResetsIgnoredNudgeCount() {
        let motionProvider = FakeHeadMotionProvider()
        let notifier = FakePostureNotifier()
        let settings = AppSettings(
            thresholdDegrees: 10,
            holdSeconds: 0,
            recoverSeconds: 0,
            alertCooldownSeconds: 5,
            soundEnabled: false,
            speechEnabled: false,
            invertedPitch: false
        )
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: notifier,
            historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
            settings: settings
        )

        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
        drainMainQueue()
        viewModel.calibrate()
        viewModel.startMonitoring()
        motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 1))
        drainMainQueue()
        motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 6))
        drainMainQueue()
        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 7))
        drainMainQueue()
        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 8))
        drainMainQueue()
        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 9))
        drainMainQueue()
        motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 10))
        drainMainQueue()
        motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 12))
        drainMainQueue()
        motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 17))
        drainMainQueue()

        XCTAssertEqual(notifier.nudgeCount, 4)
        XCTAssertEqual(notifier.pauseNoticeCount, 0)
    }

    func testAlertCooldownSettingPersists() {
        let settings = AppSettings(
            thresholdDegrees: 10,
            holdSeconds: 0,
            recoverSeconds: 1,
            alertCooldownSeconds: 5,
            soundEnabled: false,
            speechEnabled: false,
            invertedPitch: false
        )
        let defaults = isolatedDefaults()
        let viewModel = PostureViewModel(
            motionProvider: FakeHeadMotionProvider(),
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: FakePostureNotifier(),
            historyStore: PostureHistoryStore(defaults: defaults),
            settingsDefaults: defaults,
            settings: settings
        )

        viewModel.updateAlertCooldown(30)

        XCTAssertEqual(AppSettings.load(from: defaults).alertCooldownSeconds, 30)
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

    func testAirPodsReconnectClearsDisconnectedStatus() {
        let audioMonitor = FakeAudioOutputMonitor(airPodsActive: true)
        let viewModel = PostureViewModel(
            motionProvider: FakeHeadMotionProvider(),
            audioOutputMonitor: audioMonitor,
            notifier: FakePostureNotifier(),
            historyStore: PostureHistoryStore(defaults: isolatedDefaults())
        )

        viewModel.startMonitoring()
        audioMonitor.airPodsActive = false
        audioMonitor.onChange?(false)
        drainMainQueue()
        audioMonitor.airPodsActive = true
        audioMonitor.onChange?(true)
        drainMainQueue()

        XCTAssertEqual(viewModel.statusText, "Ready")
        XCTAssertFalse(viewModel.disconnected)
    }

    func testSessionSummaryIgnoresPreviousDayStats() {
        let defaults = isolatedDefaults()
        let historyStore = PostureHistoryStore(defaults: defaults)
        let yesterday = Date().addingTimeInterval(-86_400)
        historyStore.add(PostureSession(
            startedAt: yesterday,
            endedAt: yesterday.addingTimeInterval(60),
            badSeconds: 10
        ))
        let viewModel = PostureViewModel(
            motionProvider: FakeHeadMotionProvider(),
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: FakePostureNotifier(),
            historyStore: historyStore
        )

        XCTAssertEqual(viewModel.sessionSummary, "Sessions today: 0")
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

    func testCalibrateUsesLatestPitchWhenDisplayedPitchIsThrottled() {
        let motionProvider = FakeHeadMotionProvider()
        let viewModel = PostureViewModel(
            motionProvider: motionProvider,
            audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
            notifier: FakePostureNotifier(),
            historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
            pitchDisplayUpdateInterval: 1.0
        )

        viewModel.startMonitoring()
        motionProvider.emit(pitch: -20.0, at: Date(timeIntervalSince1970: 0.0))
        motionProvider.emit(pitch: -30.0, at: Date(timeIntervalSince1970: 0.1))
        drainMainQueue()
        viewModel.calibrate()

        XCTAssertEqual(viewModel.currentPitch, -20.0)
        XCTAssertEqual(viewModel.lastCalibratedPitch, -30.0)
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
    private(set) var pauseNoticeCount = 0
    var nextAuthorizationResult = true
    private var lastNudgeAt: Date?

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

    func notifyPaused(until: Date, notificationsEnabled: Bool) {
        pauseNoticeCount += 1
    }

    func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date) {
        if let lastNudgeAt,
           now.timeIntervalSince(lastNudgeAt) < settings.alertCooldownSeconds {
            return
        }

        lastNudgeAt = now
        nudgeCount += 1
    }
}
