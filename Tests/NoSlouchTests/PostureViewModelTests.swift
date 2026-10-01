import AppKit
import Foundation
import XCTest

@testable import NoSlouch

final class PostureViewModelTests: XCTestCase {
  func testInvalidMotionCannotPoisonCalibrationOrAccounting() {
    let motion = FakeHeadMotionProvider()
    let settingsDefaults = isolatedDefaults()
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: settingsDefaults,
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
    let start = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: .nan, at: start)
    drainMainQueue()
    XCTAssertFalse(viewModel.canCalibrate)
    XCTAssertNil(viewModel.currentPitch)

    motion.emit(pitch: 20, roll: 5, at: start)
    motion.emit(pitch: .infinity, at: start.addingTimeInterval(1))
    motion.emit(pitch: 90, roll: .nan, at: start.addingTimeInterval(2))
    drainMainQueue()
    viewModel.calibrateAveraged()
    XCTAssertEqual(viewModel.lastCalibratedPitch, 20)
    XCTAssertEqual(AppSettings.load(from: settingsDefaults).calibratedBaselineRoll, 5)

    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: start)
    motion.emit(pitch: .nan, at: start.addingTimeInterval(10))
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: .infinity))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 0)
    motion.emit(pitch: 20, at: start.addingTimeInterval(20))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 20)
  }

  func testOutOfOrderMotionDoesNotDoubleCountTimeOrChangeCalibration() {
    let motion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
    let start = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: start)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: start)
    motion.emit(pitch: 20, at: start.addingTimeInterval(10))
    motion.emit(pitch: -100, at: start.addingTimeInterval(5))
    motion.emit(pitch: -100, at: start.addingTimeInterval(10))
    motion.emit(pitch: 20, at: start.addingTimeInterval(20))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 20)
    XCTAssertEqual(viewModel.sessionSlouchEvents, 0)
    viewModel.calibrateAveraged()
    XCTAssertEqual(viewModel.lastCalibratedPitch, 20)
  }

  func testClearHistoryStopsAndDiscardsActiveSessionWithoutRestoringDeletedData() {
    let motion = FakeHeadMotionProvider()
    let defaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: defaults)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.add(
      PostureSession(startedAt: start, endedAt: start.addingTimeInterval(60), badSeconds: 10))
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: store,
      settingsDefaults: defaults,
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
    motion.emit(pitch: 20, at: start)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: start)
    motion.emit(pitch: 20, at: start.addingTimeInterval(20))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 20)

    viewModel.clearHistory()
    motion.emit(pitch: 20, at: start.addingTimeInterval(30))
    drainMainQueue()
    viewModel.stopMonitoring()

    XCTAssertFalse(viewModel.isMonitoring)
    XCTAssertTrue(viewModel.dailyStats.isEmpty)
    XCTAssertTrue(viewModel.hourlyStats.isEmpty)
    XCTAssertTrue(viewModel.deviationSamples.isEmpty)
    XCTAssertEqual(viewModel.sessionGoodSeconds, 0)
    XCTAssertEqual(viewModel.todayUprightText, "Today: no data yet")
    XCTAssertTrue(PostureHistoryStore(defaults: defaults).stats.isEmpty)
    XCTAssertEqual(AppSettings.load(from: defaults).calibratedBaselinePitch, 20)
  }

  func testAwayWithoutMotionDoesNotBookIdleTimeOnReturn() {
    let motion = FakeHeadMotionProvider()
    let activity = FakeActivityMonitor()
    var settings = AppSettings()
    settings.calibratedBaselinePitch = 20
    settings.pauseWhenAwayEnabled = true
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: FakePostureNotifier(), settings: settings, activity: activity)
    let start = Date(timeIntervalSince1970: 0)
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: start)
    motion.emit(pitch: 20, at: start.addingTimeInterval(10))
    drainMainQueue()
    activity.emit(away: true)
    drainMainQueue()
    activity.emit(away: false)
    drainMainQueue()
    motion.emit(pitch: 20, at: start.addingTimeInterval(200))
    motion.emit(pitch: 20, at: start.addingTimeInterval(210))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 20)
  }

  func testInitialAwayStateSuppressesTrackingWithoutAChangeCallback() {
    let motion = FakeHeadMotionProvider()
    var settings = AppSettings()
    settings.calibratedBaselinePitch = 20
    settings.pauseWhenAwayEnabled = true
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: FakeActivityMonitor(isUserAway: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(), settings: settings,
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 10))
    drainMainQueue()
    XCTAssertTrue(viewModel.isUserAway)
    XCTAssertEqual(viewModel.sessionGoodSeconds, 0)
  }

  func testInitialMicrophoneStateSuppressesNudgesWithoutAChangeCallback() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    var settings = AppSettings()
    settings.calibratedBaselinePitch = 20
    settings.holdSeconds = 0
    settings.muteInMeetings = true
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(isMicActive: true),
      activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(), settings: settings,
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
    viewModel.startMonitoring()
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    XCTAssertEqual(viewModel.postureState, .bad)
    XCTAssertTrue(viewModel.isMicActive)
    XCTAssertEqual(notifier.nudgeCount, 0)
  }

  func testReadingAfterStopDoesNotNudge() {
    let motionProvider = FakeHeadMotionProvider()
    let audioMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true)
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
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
    XCTAssertEqual(viewModel.statusText, "Nudges paused · 10 min left")

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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.updateAlertCooldown(30)

    XCTAssertEqual(AppSettings.load(from: defaults).alertCooldownSeconds, 30)
  }

  func testSpeechEnabledSettingPersists() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.updateSpeechEnabled(true)

    XCTAssertEqual(AppSettings.load(from: defaults).speechEnabled, true)
  }

  func testHoldSecondsUpdatePersistsAndRebuildsAnalyzer() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.updateHoldSeconds(2.0)

    XCTAssertEqual(AppSettings.load(from: defaults).holdSeconds, 2.0)
    XCTAssertNil(viewModel.lastCalibratedPitch)
  }

  func testRecoverSecondsSettingPersists() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.updateRecoverSeconds(2.5)

    XCTAssertEqual(AppSettings.load(from: defaults).recoverSeconds, 2.5)
  }

  func testDisconnectStatusIsPreserved() {
    let motionProvider = FakeHeadMotionProvider()
    let audioMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: audioMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    viewModel.startMonitoring()
    audioMonitor.isHeadphoneOutput = false
    audioMonitor.onChange?(false)
    drainMainQueue()

    XCTAssertEqual(viewModel.statusText, "AirPods disconnected")
    XCTAssertFalse(viewModel.isMonitoring)
  }

  func testAirPodsReconnectClearsDisconnectedStatus() {
    let audioMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true)
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: audioMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.startMonitoring()
    audioMonitor.isHeadphoneOutput = false
    audioMonitor.onChange?(false)
    drainMainQueue()
    audioMonitor.isHeadphoneOutput = true
    audioMonitor.onChange?(true)
    drainMainQueue()

    XCTAssertEqual(viewModel.statusText, "Ready")
    XCTAssertFalse(viewModel.disconnected)
  }

  func testSessionSummaryIgnoresPreviousDayStats() {
    let defaults = isolatedDefaults()
    let historyStore = PostureHistoryStore(defaults: defaults)
    let yesterday = Date().addingTimeInterval(-86_400)
    historyStore.add(
      PostureSession(
        startedAt: yesterday,
        endedAt: yesterday.addingTimeInterval(60),
        badSeconds: 10
      ))
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: historyStore,
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertEqual(viewModel.sessionSummary, "Sessions today: 0")
  }

  func testCalibrateShowsGoodCalibratedStatus() {
    let motionProvider = FakeHeadMotionProvider()
    let audioMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: audioMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      pitchDisplayUpdateInterval: 1.0,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.requestNotifications()
    drainMainQueue()

    XCTAssertTrue(viewModel.notificationsEnabled)
    XCTAssertEqual(notifier.requestCount, 1)
    XCTAssertEqual(notifier.refreshCount, 1)
  }

  func testDidBecomeActiveRefreshesNotificationStatus() {
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertEqual(notifier.refreshCount, 1)

    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    drainMainQueue()

    XCTAssertEqual(notifier.refreshCount, 2)
    _ = viewModel
  }

  func testCalibratePersistsBaselinePitch() {
    let defaults = isolatedDefaults()
    let motionProvider = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 15.5, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()

    XCTAssertEqual(viewModel.settings.calibratedBaselinePitch, 15.5)
    XCTAssertEqual(viewModel.lastCalibratedPitch, 15.5)
    XCTAssertFalse(viewModel.isBaselineRestored)

    let loadedSettings = AppSettings.load(from: defaults)
    XCTAssertEqual(loadedSettings.calibratedBaselinePitch, 15.5)

    let secondViewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertEqual(secondViewModel.settings.calibratedBaselinePitch, 15.5)
    XCTAssertEqual(secondViewModel.lastCalibratedPitch, 15.5)
    XCTAssertTrue(secondViewModel.isBaselineRestored)

    secondViewModel.startMonitoring()
    XCTAssertEqual(secondViewModel.postureState, .good)
  }

  func testChangingThresholdClearsPersistedBaselinePitch() {
    let defaults = isolatedDefaults()
    let motionProvider = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 15.5, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()

    XCTAssertEqual(viewModel.settings.calibratedBaselinePitch, 15.5)

    viewModel.updateThreshold(15.0)

    XCTAssertNil(viewModel.settings.calibratedBaselinePitch)
    XCTAssertNil(viewModel.lastCalibratedPitch)
    XCTAssertFalse(viewModel.isBaselineRestored)
    XCTAssertEqual(viewModel.postureState, .unknown)
  }

  func testMicActiveSuppressesNudges() {
    let motionProvider = FakeHeadMotionProvider()
    let micMonitor = FakeMicrophoneMonitor(isMicActive: false)
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 5,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      muteInMeetings: true
    )
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: micMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    // 1. Mic is inactive. Emit bad pitch. Should nudge!
    motionProvider.emit(pitch: -100.0, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    XCTAssertEqual(notifier.nudgeCount, 1)

    // 2. Set mic active. Emit bad pitch. Should NOT nudge!
    micMonitor.emit(active: true)
    drainMainQueue()
    XCTAssertEqual(viewModel.statusText, "Nudges paused (mic active)")

    motionProvider.emit(pitch: -100.0, at: Date(timeIntervalSince1970: 7))
    drainMainQueue()
    XCTAssertEqual(notifier.nudgeCount, 1)

    // 3. Set mic inactive again. Emit bad pitch. Should nudge!
    micMonitor.emit(active: false)
    drainMainQueue()
    motionProvider.emit(pitch: -100.0, at: Date(timeIntervalSince1970: 13))
    drainMainQueue()
    XCTAssertEqual(notifier.nudgeCount, 2)
  }

  func testBreakReminderTriggersAfterConfiguredTime() {
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 5,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      breakRemindersEnabled: true,
      breakReminderMinutes: 10.0
    )
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    // Establish the session start timestamp at 0s
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()

    XCTAssertEqual(notifier.breakNudgeCount, 0)

    // 0s to 300s (5 minutes)
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 300))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 0)

    // 300s to 600s (another 5 minutes -> total 10 minutes)
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 600))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 1)

    // 600s to 900s (15 minutes total -> 5 minutes since last break nudge)
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 900))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 1)

    // 900s to 1200s (20 minutes total -> 10 minutes since last break nudge)
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 1200))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 2)
  }

  func testBreakReminderDeferredWhileMicActive() {
    let motionProvider = FakeHeadMotionProvider()
    let micMonitor = FakeMicrophoneMonitor(isMicActive: false)
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 5,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      muteInMeetings: true,
      breakRemindersEnabled: true,
      breakReminderMinutes: 10.0
    )
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: micMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    // Anchor the monitored-time clock at 0s within the session.
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()

    // Mic goes active before the interval elapses (in a meeting).
    micMonitor.emit(active: true)
    drainMainQueue()

    // 10 minutes of monitored time elapse while the mic is active: the break is
    // due but must be suppressed.
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 300))
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 600))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 0)

    // Mic frees up; the deferred break fires on the next reading.
    micMonitor.emit(active: false)
    drainMainQueue()
    motionProvider.emit(pitch: 20.0, at: Date(timeIntervalSince1970: 601))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 1)
  }

  func testBadPostureNudgePassesPositiveDrop() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()

    XCTAssertEqual(notifier.nudgeCount, 1)
    XCTAssertNotNil(notifier.lastDrop)
    XCTAssertGreaterThan(notifier.lastDrop ?? 0, 0)
  }

  func testConnectedDeviceNameShownWhenNotMonitoring() {
    let audioMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true, deviceName: "AirPods Pro")
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: audioMonitor,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    drainMainQueue()

    XCTAssertFalse(viewModel.isMonitoring)
    XCTAssertEqual(viewModel.statusText, "AirPods Pro connected")
  }

  func testUprightSessionAccumulatesGoodSeconds() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 4))
    drainMainQueue()

    XCTAssertEqual(viewModel.sessionGoodSeconds, 3)
    XCTAssertEqual(viewModel.sessionBadSeconds, 0)
  }

  func testSlouchEventsCountTransitionsIntoBad() {
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()

    XCTAssertEqual(viewModel.sessionSlouchEvents, 1)

    for second in 3...12 {
      motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: TimeInterval(second)))
      drainMainQueue()
    }
    XCTAssertEqual(viewModel.postureState, .good)

    motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 13))
    drainMainQueue()
    motionProvider.emit(pitch: -40, at: Date(timeIntervalSince1970: 14))
    drainMainQueue()

    XCTAssertEqual(viewModel.sessionSlouchEvents, 2)
  }

  func testUpdateSoundNamePersists() {
    let defaults = isolatedDefaults()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.updateSoundName("Ping")

    XCTAssertEqual(AppSettings.load(from: defaults).soundName, "Ping")
  }

  func testPreviewSoundCallsNotifier() {
    let notifier = FakePostureNotifier()
    var settings = AppSettings()
    settings.soundName = "Ping"
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.previewSound()

    XCTAssertEqual(notifier.previewCount, 1)
    XCTAssertEqual(notifier.lastPreviewName, "Ping")
  }

  func testDeviationBufferDownsamplesToFiveHz() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    for step in 1...20 {
      motionProvider.emit(pitch: 18, at: Date(timeIntervalSince1970: TimeInterval(step) * 0.05))
      drainMainQueue()
    }

    XCTAssertGreaterThan(viewModel.deviationSamples.count, 0)
    XCTAssertLessThanOrEqual(viewModel.deviationSamples.count, 8)
  }

  func testDeviationBufferDropsSamplesOlderThanSixtySeconds() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motionProvider.emit(pitch: 18, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    motionProvider.emit(pitch: 18, at: Date(timeIntervalSince1970: 62))
    drainMainQueue()

    XCTAssertEqual(viewModel.deviationSamples.count, 1)
    XCTAssertEqual(viewModel.deviationSamples.first?.timestamp, Date(timeIntervalSince1970: 62))
  }

  func testSnoozeSuppressesNudges() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    viewModel.snoozeNudges(for: 600)
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 3))
    drainMainQueue()

    XCTAssertEqual(notifier.nudgeCount, 0)
    XCTAssertEqual(viewModel.statusText, "Nudges snoozed · 10 min left")
  }

  func testSnoozeStatusCountsDownFromReadingClock() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(isMicActive: false),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.snoozeNudges(for: 600)
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 120))
    drainMainQueue()

    XCTAssertEqual(viewModel.statusText, "Nudges snoozed · 8 min left")
  }

  func testPauseStatusCountsDownFromReadingClock() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(isMicActive: false),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    // Three bad nudges trip the auto-pause; the third sets the deadline at t=11+600.
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 6))
    drainMainQueue()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 11))
    drainMainQueue()
    // 120 s after the pause deadline was set: 600 - 120 = 480 s → 8 min left.
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 131))
    drainMainQueue()

    XCTAssertEqual(viewModel.statusText, "Nudges paused · 8 min left")
    XCTAssertTrue(viewModel.statusText.hasSuffix(" min left"))
  }

  func testSnoozeSurvivesGoodPostureReading() {
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 0,
      alertCooldownSeconds: 0,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false
    )
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    viewModel.snoozeNudges(for: 600)
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()

    XCTAssertNotNil(viewModel.snoozedUntil)

    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 3))
    drainMainQueue()

    XCTAssertEqual(notifier.nudgeCount, 0)
  }

  func testResumeNudgesClearsSnooze() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    viewModel.snoozeNudges(for: 600)
    viewModel.resumeNudges()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()

    XCTAssertNil(viewModel.snoozedUntil)
    XCTAssertEqual(notifier.nudgeCount, 1)
  }

  func testDailyStatsReflectHistoryStore() {
    let defaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: defaults)
    let day = Date()
    store.add(
      PostureSession(
        startedAt: day,
        endedAt: day.addingTimeInterval(60),
        badSeconds: 10,
        goodSeconds: 50,
        slouchEvents: 2))
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: store,
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertEqual(viewModel.dailyStats.count, 1)
    XCTAssertEqual(viewModel.dailyStats.first?.slouchEvents, 2)
    XCTAssertEqual(viewModel.hourlyStats.count, 1)
    XCTAssertEqual(viewModel.hourlyStats.first?.slouchEvents, 2)
  }

  func testTodayUprightTextCombinesStoredStats() {
    let defaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: defaults)
    let now = Date()
    store.add(
      PostureSession(
        startedAt: now,
        endedAt: now.addingTimeInterval(100),
        badSeconds: 25,
        goodSeconds: 75,
        slouchEvents: 3))
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: store,
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertEqual(viewModel.todayUprightText, "Today: 75% upright · 3 slouches")
  }

  func testTerminationNotificationStopsMonitoring() {
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    viewModel.startMonitoring()
    XCTAssertTrue(viewModel.isMonitoring)

    NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
    drainMainQueue()

    XCTAssertFalse(viewModel.isMonitoring)
  }

  func testMenuBarSymbolReflectsState() {
    let motionProvider = FakeHeadMotionProvider()
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
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    XCTAssertEqual(viewModel.menuBarSymbolName, "figure.stand")

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    XCTAssertEqual(viewModel.menuBarSymbolName, "figure.stand")

    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()
    XCTAssertEqual(viewModel.menuBarSymbolName, "figure.seated.side")

    viewModel.snoozeNudges(for: 600)
    XCTAssertEqual(viewModel.menuBarSymbolName, "moon.zzz")
  }

  private func isolatedDefaults() -> UserDefaults {
    let suiteName = "NoSlouch.PostureViewModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }

  /// Older reminder scenarios use sparse synthetic frames to advance minutes at a time.
  /// Keep their clock and relaxed gap policy together; production-gap tests use the default policy.
  private func makeCoarseSampleViewModel(
    motion: FakeHeadMotionProvider,
    notifier: FakePostureNotifier,
    settings: AppSettings,
    activity: FakeActivityMonitor = FakeActivityMonitor()
  ) -> PostureViewModel {
    PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: activity,
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )
  }

  private func drainMainQueue() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  }

  func testAutoDriftAdjustsBaselineWhenEnabledWithoutPersisting() {
    let defaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: defaults)
    let fakeMotion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: fakeMotion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: store,
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, now: { fakeMotion.currentDate }, startHeartbeat: false
    )
    viewModel.updateAutoDriftEnabled(true)

    viewModel.toggleMonitoring()  // start monitoring
    fakeMotion.emit(pitch: 15.0, at: Date())
    drainMainQueue()
    viewModel.calibrate()
    XCTAssertEqual(viewModel.lastCalibratedPitch, 15.0)
    XCTAssertEqual(viewModel.settings.calibratedBaselinePitch, 15.0)

    // Emit 1000 good readings slightly above baseline; the analyzer baseline
    // (surfaced via lastCalibratedPitch) drifts toward 16.0.
    let now = Date()
    for i in 0..<1000 {
      fakeMotion.emit(pitch: 16.0, at: now.addingTimeInterval(Double(i) * 0.1))
    }
    drainMainQueue()

    let drifted = viewModel.lastCalibratedPitch ?? 0.0
    XCTAssertGreaterThan(drifted, 15.0)
    XCTAssertLessThan(drifted, 16.0)
    // NB-1: drift is in-memory only; the persisted baseline is untouched.
    XCTAssertEqual(viewModel.settings.calibratedBaselinePitch, 15.0)

    // Drift is bounded to original ± 2.0 (15.0 + 2.0 = 17.0).
    for i in 0..<10000 {
      fakeMotion.emit(pitch: 20.0, at: now.addingTimeInterval(100.0 + Double(i) * 0.1))
    }
    drainMainQueue()
    XCTAssertEqual(viewModel.lastCalibratedPitch ?? 0.0, 17.0, accuracy: 0.01)

    // NB-1: an unrelated settings save must not flush the drifted baseline to disk.
    viewModel.updateSoundEnabled(false)
    XCTAssertEqual(AppSettings.load(from: defaults).calibratedBaselinePitch, 15.0)
  }

  func testAutoDriftDoesNothingWhenDisabled() {
    let defaults = isolatedDefaults()
    let fakeMotion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: fakeMotion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, now: { fakeMotion.currentDate }, startHeartbeat: false
    )
    // autoDriftEnabled defaults to false (NB-2).

    viewModel.toggleMonitoring()
    fakeMotion.emit(pitch: 15.0, at: Date())
    drainMainQueue()
    viewModel.calibrate()
    XCTAssertEqual(viewModel.lastCalibratedPitch, 15.0)

    let now = Date()
    for i in 0..<1000 {
      fakeMotion.emit(pitch: 16.0, at: now.addingTimeInterval(Double(i) * 0.1))
    }
    drainMainQueue()

    XCTAssertEqual(viewModel.lastCalibratedPitch, 15.0)
  }

  func testStartMonitoringRequiresMotionAvailability() {
    let fakeMotion = FakeHeadMotionProvider()
    fakeMotion.isDeviceMotionAvailable = false
    let viewModel = PostureViewModel(
      motionProvider: fakeMotion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { fakeMotion.currentDate }, startHeartbeat: false
    )

    viewModel.startMonitoring()

    XCTAssertFalse(viewModel.isMonitoring)
    XCTAssertTrue(viewModel.statusText.contains("motion unavailable"))
  }

  func testLoweringBreakIntervalReanchorsAndDoesNotFireImmediately() {
    let fakeMotion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 0,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      muteInMeetings: false,
      breakRemindersEnabled: true,
      breakReminderMinutes: 50
    )
    let viewModel = makeCoarseSampleViewModel(
      motion: fakeMotion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    fakeMotion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    // Accumulate ~10 minutes of good monitored time (< the 50-minute interval).
    fakeMotion.emit(pitch: 20, at: t0)
    fakeMotion.emit(pitch: 20, at: Date(timeIntervalSince1970: 300))
    fakeMotion.emit(pitch: 20, at: Date(timeIntervalSince1970: 600))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 0)

    // Lowering to 5 minutes must re-anchor so it does NOT fire against the 10
    // minutes already accumulated (BUG-7).
    viewModel.updateBreakReminderMinutes(5)
    fakeMotion.emit(pitch: 20, at: Date(timeIntervalSince1970: 601))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 0)
  }

  func testAwayPauseFreezesAccountingWhenEnabled() {
    let motion = FakeHeadMotionProvider()
    let activity = FakeActivityMonitor()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 0,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      muteInMeetings: false,
      pauseWhenAwayEnabled: true
    )
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings, activity: activity)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 100))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 100, accuracy: 0.001)

    // Go away: bad-posture readings must neither accumulate nor nudge (H1).
    activity.emit(away: true)
    drainMainQueue()
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 200))
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 260))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionBadSeconds, 0, accuracy: 0.001)
    XCTAssertEqual(notifier.nudgeCount, 0)
    XCTAssertTrue(viewModel.statusText.contains("away"))

    // Return: accounting resumes without booking the ~60s away gap.
    activity.emit(away: false)
    drainMainQueue()
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 261))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 100, accuracy: 0.001)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 262))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 101, accuracy: 0.001)
  }

  func testEscalatingNudgesRaisesIntensity() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      alertCooldownSeconds: 0,
      soundEnabled: false,
      speechEnabled: false,
      invertedPitch: false,
      muteInMeetings: false,
      escalatingNudges: true
    )
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()
    XCTAssertEqual(notifier.lastIntensity, 1)
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()
    XCTAssertEqual(notifier.lastIntensity, 2)
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 3))
    drainMainQueue()
    XCTAssertEqual(notifier.lastIntensity, 3)
  }

  func testApplyPresetSetsValuesAndClearsBaseline() {
    let defaults = isolatedDefaults()
    let motion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )

    motion.emit(pitch: 20, at: Date())
    drainMainQueue()
    viewModel.calibrate()
    XCTAssertNotNil(viewModel.lastCalibratedPitch)

    viewModel.applyPreset(.strict)

    XCTAssertEqual(viewModel.settings.thresholdDegrees, 8)
    XCTAssertEqual(viewModel.settings.holdSeconds, 2)
    XCTAssertEqual(viewModel.settings.recoverSeconds, 1)
    XCTAssertEqual(viewModel.currentPreset, .strict)
    // Analyzer-affecting change clears the baseline.
    XCTAssertNil(viewModel.lastCalibratedPitch)
  }

  func testGoalMetTodayReflectsLiveSession() {
    let motion = FakeHeadMotionProvider()
    let settings = AppSettings(
      minimumDailyMinutes: 1,
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      dailyUprightGoalPercent: 80
    )
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: FakePostureNotifier(), settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 100))
    drainMainQueue()

    XCTAssertTrue(viewModel.goalMetToday)
  }

  func testNeedsRecalibrationAfterConfiguredDays() {
    let recent = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(recalibrationReminderDays: 14, lastCalibrationDate: Date()),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    XCTAssertFalse(recent.needsRecalibration)

    let stale = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(
        recalibrationReminderDays: 14,
        lastCalibrationDate: Date(timeIntervalSinceNow: -15 * 86_400)),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    XCTAssertTrue(stale.needsRecalibration)
  }

  func testEyeRestReminderFiresIndependentlyOfBreak() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false,
      muteInMeetings: false, eyeRestEnabled: true, eyeRestMinutes: 20)
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: t0)
    for step in 1...4 {
      motion.emit(pitch: 20, at: Date(timeIntervalSince1970: Double(step) * 300))
    }
    drainMainQueue()

    XCTAssertEqual(notifier.reminderCounts[.eyeRest], 1)
    XCTAssertEqual(notifier.reminderCounts[.breakTime, default: 0], 0)
  }

  func testRemindersDoNotStackWithinMinGap() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      breakRemindersEnabled: true, breakReminderMinutes: 20,
      eyeRestEnabled: true, eyeRestMinutes: 20)
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    for step in 1...4 {
      motion.emit(pitch: 20, at: Date(timeIntervalSince1970: Double(step) * 300))
    }
    drainMainQueue()
    // Both due at once; only the first (break) fires this tick.
    XCTAssertEqual(notifier.reminderCounts[.breakTime], 1)
    XCTAssertEqual(notifier.reminderCounts[.eyeRest, default: 0], 0)

    // Still within the 120s min-gap: eye-rest holds.
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1_201))
    drainMainQueue()
    XCTAssertEqual(notifier.reminderCounts[.eyeRest, default: 0], 0)

    // Once the gap clears, eye-rest fires.
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1_330))
    drainMainQueue()
    XCTAssertEqual(notifier.reminderCounts[.eyeRest], 1)
  }

  func testQuietHoursSuppressBadPostureNudge() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      quietHoursEnabled: true, quietStartMinutes: 0, quietEndMinutes: 1_440)
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()

    XCTAssertEqual(notifier.nudgeCount, 0)
    XCTAssertTrue(viewModel.statusText.contains("Quiet"))
  }

  func testQuietHoursDeferRemindersUntilCleared() {
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      breakRemindersEnabled: true, breakReminderMinutes: 20,
      quietHoursEnabled: true, quietStartMinutes: 0, quietEndMinutes: 1_440)
    let viewModel = makeCoarseSampleViewModel(
      motion: motion, notifier: notifier, settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    for step in 1...4 {
      motion.emit(pitch: 20, at: Date(timeIntervalSince1970: Double(step) * 300))
    }
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 0)  // due, but deferred by quiet hours

    viewModel.updateQuietHoursEnabled(false)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1_201))
    drainMainQueue()
    XCTAssertEqual(notifier.breakNudgeCount, 1)  // fires once quiet hours clear
  }

  func testLowBatteryWarningFiresOnceThenRearms() {
    let battery = FakeAirPodsBatteryMonitor()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      batteryMonitor: battery,
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    battery.emit(AirPodsBatteryInfo(leftPercentage: 12, rightPercentage: 50))
    drainMainQueue()
    XCTAssertEqual(notifier.lowBatteryCount, 1)
    XCTAssertEqual(notifier.lastLowBatteryPercentage, 12)

    // Still low → no repeat.
    battery.emit(AirPodsBatteryInfo(leftPercentage: 10, rightPercentage: 50))
    drainMainQueue()
    XCTAssertEqual(notifier.lowBatteryCount, 1)

    // Recover, then drop again → re-armed, fires a second time.
    battery.emit(AirPodsBatteryInfo(leftPercentage: 80, rightPercentage: 80))
    drainMainQueue()
    battery.emit(AirPodsBatteryInfo(leftPercentage: 5, rightPercentage: 80))
    drainMainQueue()
    XCTAssertEqual(notifier.lowBatteryCount, 2)
    XCTAssertEqual(viewModel.batteryInfo?.leftPercentage, 5)
  }

  func testCalibrateAveragedUsesRecentAverage() {
    let motion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motion.currentDate }, startHeartbeat: false
    )

    motion.emit(pitch: 10, at: Date(timeIntervalSince1970: 0))
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    motion.emit(pitch: 30, at: Date(timeIntervalSince1970: 2))
    drainMainQueue()

    viewModel.calibrateAveraged()
    XCTAssertEqual(viewModel.lastCalibratedPitch ?? 0, 20, accuracy: 0.001)
  }

  func testOnboardingFlagFlips() {
    let defaults = isolatedDefaults()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: AppSettings(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )

    XCTAssertTrue(viewModel.needsOnboarding)
    viewModel.completeOnboarding()
    XCTAssertFalse(viewModel.needsOnboarding)
    XCTAssertTrue(AppSettings.load(from: defaults).hasCompletedOnboarding)
  }

  func testStalledReadingGapIsNotBooked() {
    // A long delivery gap (Mac sleep, BT dropout) must not be booked as posture
    // time or fast-forward reminders (NB-15).
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      breakRemindersEnabled: true, breakReminderMinutes: 10.0)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 10))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 10, accuracy: 0.001)

    // 40-minute stall: nothing booked, no reminder burst on the next reading.
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 2_410))
    drainMainQueue()
    XCTAssertEqual(viewModel.sessionGoodSeconds, 10, accuracy: 0.001)
    XCTAssertEqual(notifier.breakNudgeCount, 0)
  }

  func testStopMonitoringClearsAutoPause() {
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 5,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 1))
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 6))
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 11))
    drainMainQueue()
    XCTAssertEqual(notifier.pauseNoticeCount, 1)

    // Stopping must drop both the paused status text and the pause itself
    // (NB-24).
    viewModel.stopMonitoring()
    XCTAssertFalse(viewModel.statusText.contains("paused"), viewModel.statusText)

    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 100))
    motionProvider.emit(pitch: -100, at: Date(timeIntervalSince1970: 120))
    drainMainQueue()
    XCTAssertEqual(notifier.nudgeCount, 4)
  }

  func testCalibrateAveragedIgnoresPreviousSessionReadings() {
    // Stale buffered readings from a finished session must not seed the guided
    // calibration average (NB-25).
    let motionProvider = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    viewModel.startMonitoring()
    for i in 0..<5 {
      motionProvider.emit(pitch: 0, at: Date(timeIntervalSince1970: Double(i)))
    }
    drainMainQueue()
    viewModel.stopMonitoring()

    motionProvider.emit(pitch: 10, at: Date(timeIntervalSince1970: 100))
    drainMainQueue()
    viewModel.calibrateAveraged()

    XCTAssertEqual(viewModel.lastCalibratedPitch ?? 0, 10.0, accuracy: 0.001)
  }

  func testRemindersAdvanceWhileAnalyzerUncalibrated() {
    // An uncalibrated analyzer accumulates no good/bad seconds; the reminder
    // clock must keep running anyway (NB-23).
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      breakRemindersEnabled: true, breakReminderMinutes: 10.0)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 300))
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 600))
    drainMainQueue()

    XCTAssertEqual(viewModel.postureState, .unknown)
    XCTAssertEqual(notifier.breakNudgeCount, 1)
  }

  func testLowBatteryWarningIgnoresCaseLevel() {
    // A drained charging case doesn't affect tracking and must not trigger the
    // buds-low warning (NB-28).
    let battery = FakeAirPodsBatteryMonitor()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: battery,
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    _ = viewModel

    battery.emit(AirPodsBatteryInfo(leftPercentage: 90, rightPercentage: 88, casePercentage: 10))
    drainMainQueue()
    XCTAssertEqual(notifier.lowBatteryCount, 0)

    battery.emit(AirPodsBatteryInfo(leftPercentage: 12, rightPercentage: 88, casePercentage: 10))
    drainMainQueue()
    XCTAssertEqual(notifier.lowBatteryCount, 1)
  }

  func testBaselineRollPersistsAndRestores() {
    // Tilt detection against a restored baseline must use the calibrated roll,
    // not 0 (NB-16) ; otherwise a natural 16° sensor roll nudges forever after
    // relaunch.
    let defaults = isolatedDefaults()
    let motionProvider = FakeHeadMotionProvider()
    let settings = AppSettings(
      thresholdDegrees: 10, holdSeconds: 0, recoverSeconds: 1, alertCooldownSeconds: 0,
      soundEnabled: false, speechEnabled: false, invertedPitch: false, muteInMeetings: false,
      tiltDetectionEnabled: true, tiltThresholdDegrees: 15.0)
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, roll: 16, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    XCTAssertEqual(
      AppSettings.load(from: defaults).calibratedBaselineRoll ?? 0, 16, accuracy: 0.001)

    // Relaunch: a fresh ViewModel restores pitch AND roll, so sitting at the
    // calibrated roll stays .good.
    let notifier2 = FakePostureNotifier()
    let motion2 = FakeHeadMotionProvider()
    let viewModel2 = PostureViewModel(
      motionProvider: motion2,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier2,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: defaults,
      maxReadingGapSeconds: 300, now: { motion2.currentDate }, startHeartbeat: false
    )
    viewModel2.startMonitoring()
    motion2.emit(pitch: 20, roll: 16, at: Date(timeIntervalSince1970: 0))
    motion2.emit(pitch: 20, roll: 16, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()

    XCTAssertEqual(viewModel2.postureState, .good)
  }

  func testWeeklyDigestFiresWhenDue() {
    let defaults = isolatedDefaults()
    let historyDefaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: historyDefaults)
    let yesterday = Date().addingTimeInterval(-86_400)
    store.add(
      PostureSession(
        startedAt: yesterday, endedAt: yesterday.addingTimeInterval(600),
        badSeconds: 100, goodSeconds: 500, slouchEvents: 2))
    let notifier = FakePostureNotifier()
    let settings = AppSettings(
      weeklyDigestEnabled: true,
      lastWeeklyDigestDate: Date().addingTimeInterval(-8 * 86_400)
    )
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: store,
      settingsDefaults: defaults,
      settings: settings,
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    drainMainQueue()

    XCTAssertEqual(notifier.digestCount, 1)
    // The sent date is persisted so the next launch doesn't re-fire.
    let saved = AppSettings.load(from: defaults).lastWeeklyDigestDate
    XCTAssertNotNil(saved)
    XCTAssertLessThan(abs(saved?.timeIntervalSinceNow ?? 1_000), 60)
    _ = viewModel
  }

  func testWeeklyDigestAnchorsWithoutFiringOnFirstActivation() {
    let defaults = isolatedDefaults()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: defaults,
      settings: AppSettings(weeklyDigestEnabled: true),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    drainMainQueue()

    XCTAssertEqual(notifier.digestCount, 0)
    XCTAssertNotNil(AppSettings.load(from: defaults).lastWeeklyDigestDate)
    _ = viewModel
  }

  func testWeeklyDigestDoesNothingWhenDisabled() {
    let defaults = isolatedDefaults()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: defaults,
      settings: AppSettings(lastWeeklyDigestDate: Date().addingTimeInterval(-8 * 86_400)),
      maxReadingGapSeconds: 300, startHeartbeat: false
    )
    drainMainQueue()

    XCTAssertEqual(notifier.digestCount, 0)
    _ = viewModel
  }

  func testNotificationSnoozeActionSnoozesNudges() {
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 1))
    drainMainQueue()

    XCTAssertNil(viewModel.snoozedUntil)
    notifier.simulate(action: .snooze15)
    drainMainQueue()

    // Snoozed 15 min against the reading clock (B3).
    XCTAssertEqual(
      viewModel.snoozedUntil, Date(timeIntervalSince1970: 1).addingTimeInterval(15 * 60))
  }

  func testNotificationRecalibrateActionStartsGuidedCalibration() {
    let motionProvider = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    motionProvider.emit(pitch: 12.5, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()

    notifier.simulate(action: .recalibrate)
    drainMainQueue()

    XCTAssertTrue(viewModel.isCalibrating)
    XCTAssertNil(viewModel.lastCalibratedPitch)
  }

  func testURLCommandsDriveTheViewModel() {
    let motionProvider = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motionProvider,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      batteryMonitor: FakeAirPodsBatteryMonitor(),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(
        defaults: isolatedDefaults(), now: { Date(timeIntervalSince1970: 0) }),
      settingsDefaults: isolatedDefaults(),
      settings: AppSettings(),
      maxReadingGapSeconds: 300, now: { motionProvider.currentDate }, startHeartbeat: false
    )

    viewModel.handle(.start)
    XCTAssertTrue(viewModel.isMonitoring)

    motionProvider.emit(pitch: 20, at: Date(timeIntervalSince1970: 0))
    drainMainQueue()
    viewModel.handle(.snooze(minutes: 30))
    XCTAssertEqual(
      viewModel.snoozedUntil, Date(timeIntervalSince1970: 0).addingTimeInterval(30 * 60))

    viewModel.handle(.resume)
    XCTAssertNil(viewModel.snoozedUntil)

    viewModel.handle(.calibrate)
    XCTAssertTrue(viewModel.isCalibrating)
    XCTAssertNil(viewModel.lastCalibratedPitch)

    viewModel.handle(.stop)
    XCTAssertFalse(viewModel.isMonitoring)
  }
}

private final class FakeHeadMotionProvider: HeadMotionProvider {
  var currentDate = Date()
  var authorization: MotionAuthorization = .authorized
  var isDeviceMotionAvailable = true
  var onReading: ((HeadMotionReading) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onError: ((String) -> Void)?

  func start() {}
  func stop() {}

  func emit(pitch: Double, roll: Double = 0, at timestamp: Date) {
    currentDate = timestamp
    onReading?(HeadMotionReading(pitch: pitch, roll: roll, yaw: 0, timestamp: timestamp))
  }
}

private final class FakeAudioOutputMonitor: AudioOutputMonitoring {
  var isHeadphoneOutput: Bool
  var deviceName: String
  var onChange: ((Bool) -> Void)?

  init(isHeadphoneOutput: Bool, deviceName: String = "") {
    self.isHeadphoneOutput = isHeadphoneOutput
    self.deviceName = deviceName
  }

  func start() {}
}

private final class FakePostureNotifier: PostureNotifying {
  var onAction: ((PostureNudgeAction) -> Void)?
  private(set) var digestCount = 0
  private(set) var lastDigestSummary: String?
  private(set) var nudgeCount = 0
  private(set) var requestCount = 0
  private(set) var refreshCount = 0
  private(set) var openSettingsCount = 0
  private(set) var pauseNoticeCount = 0
  private(set) var lastDrop: Double?
  private(set) var lastIntensity = 0
  private(set) var previewCount = 0
  private(set) var lastPreviewName: String?
  var nextAuthorizationResult = true
  private(set) var testNotificationCount = 0
  private(set) var testNotificationSettings: AppSettings?
  var testNotificationError: Error?

  func testNotification(settings: AppSettings, completion: @escaping (Error?) -> Void) {
    testNotificationCount += 1
    testNotificationSettings = settings
    completion(testNotificationError)
  }

  func refreshAuthorization(completion: @escaping (Bool) -> Void) {
    refreshCount += 1
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

  private(set) var lowBatteryCount = 0
  private(set) var lastLowBatteryPercentage: Int?
  func notifyLowBattery(percentage: Int, notificationsEnabled: Bool) {
    lowBatteryCount += 1
    lastLowBatteryPercentage = percentage
  }

  func nudge(
    settings: AppSettings, notificationsEnabled: Bool, now: Date, drop: Double?, intensity: Int
  ) {
    nudgeCount += 1
    lastDrop = drop
    lastIntensity = intensity
  }

  private(set) var reminderCounts: [ReminderKind: Int] = [:]
  var breakNudgeCount: Int { reminderCounts[.breakTime, default: 0] }
  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool) {
    reminderCounts[kind, default: 0] += 1
  }

  func previewSound(named name: String) {
    previewCount += 1
    lastPreviewName = name
  }

  func notifyWeeklyDigest(summary: String, notificationsEnabled: Bool) {
    digestCount += 1
    lastDigestSummary = summary
  }

  func simulate(action: PostureNudgeAction) {
    onAction?(action)
  }
}

private final class FakeMicrophoneMonitor: MicrophoneMonitoring {
  var isMicActive: Bool
  var onChange: ((Bool) -> Void)?

  init(isMicActive: Bool = false) {
    self.isMicActive = isMicActive
  }

  func start() {}

  func emit(active: Bool) {
    isMicActive = active
    onChange?(active)
  }
}

private final class FakeAirPodsBatteryMonitor: AirPodsBatteryMonitoring {
  var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)?

  func start() {}
  func stop() {}

  func emit(_ info: AirPodsBatteryInfo) {
    onBatteryUpdate?(info)
  }
}

private final class FakeActivityMonitor: ActivityMonitoring {
  var isUserAway: Bool
  var onChange: ((Bool) -> Void)?

  init(isUserAway: Bool = false) {
    self.isUserAway = isUserAway
  }

  func start() {}
  func stop() {}

  func emit(away: Bool) {
    isUserAway = away
    onChange?(away)
  }
}

private final class TrackingTestClock {
  var date: Date
  init(_ date: Date = Date()) { self.date = date }
}

extension PostureViewModelTests {
  private func trackingFixture(settings: AppSettings = AppSettings()) -> (
    PostureViewModel, FakeHeadMotionProvider, FakePostureNotifier, TrackingTestClock, UserDefaults
  ) {
    let clock = TrackingTestClock()
    let motion = FakeHeadMotionProvider()
    let notifier = FakePostureNotifier()
    let defaults = isolatedDefaults()
    let vm = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(isHeadphoneOutput: true),
      microphoneMonitor: FakeMicrophoneMonitor(), activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(), notifier: notifier,
      historyStore: PostureHistoryStore(defaults: defaults, now: { clock.date }),
      settingsDefaults: defaults, settings: settings, now: { clock.date }, startHeartbeat: false)
    return (vm, motion, notifier, clock, defaults)
  }

  func testSensorGapDoesNotBookUnmeasuredTimeOrSatisfyHold() {
    let (vm, motion, notifier, clock, _) = trackingFixture(
      settings: AppSettings(thresholdDegrees: 10, holdSeconds: 5))
    let start = clock.date
    motion.emit(pitch: 20, at: start)
    drainMainQueue()
    vm.calibrate()
    vm.startMonitoring()
    motion.emit(pitch: 20, at: start)
    drainMainQueue()
    clock.date = start.addingTimeInterval(120)
    motion.emit(pitch: -80, at: clock.date)
    drainMainQueue()
    XCTAssertEqual(vm.sessionGoodSeconds, 0)
    XCTAssertEqual(vm.postureState, .good)
    clock.date = start.addingTimeInterval(720)
    motion.emit(pitch: -80, at: clock.date)
    drainMainQueue()
    XCTAssertEqual(vm.postureState, .good)
    XCTAssertEqual(vm.sessionSlouchEvents, 0)
    XCTAssertEqual(notifier.nudgeCount, 0)
  }

  func testDisconnectInvalidatesCalibrationAndStopCancelsResume() {
    let (vm, motion, _, clock, _) = trackingFixture(
      settings: AppSettings(resumeAfterInterruption: true))
    vm.startMonitoring()
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    motion.onConnectionChanged?(false)
    drainMainQueue()
    XCTAssertFalse(vm.canCalibrate)
    vm.calibrateAveraged()
    XCTAssertNil(vm.lastCalibratedPitch)
    motion.onConnectionChanged?(true)
    drainMainQueue()
    XCTAssertTrue(vm.isMonitoring)
    vm.stopMonitoring()
    motion.onConnectionChanged?(true)
    drainMainQueue()
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.isMonitoring)
  }

  func testSleepWaitsForWakeAndExplicitStopCancelsWakeResume() {
    let (vm, _, _, _, _) = trackingFixture(settings: AppSettings(resumeAfterInterruption: true))
    vm.startMonitoring()
    vm.handleSystemSleep()
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.isMonitoring)
    vm.handleSystemWake()
    XCTAssertTrue(vm.isMonitoring)
    vm.handleSystemSleep()
    vm.stopMonitoring()
    vm.handleSystemWake()
    XCTAssertFalse(vm.isMonitoring)
  }

  func testReconnectDoesNotResumeWithoutOptIn() {
    let (vm, motion, _, _, _) = trackingFixture()
    vm.startMonitoring()
    motion.onConnectionChanged?(false)
    drainMainQueue()
    motion.onConnectionChanged?(true)
    drainMainQueue()
    XCTAssertFalse(vm.isMonitoring)
  }

  func testStaleStreamDisablesCalibrationAndSnoozeExpiresWithoutReadings() {
    let (vm, motion, _, clock, _) = trackingFixture()
    vm.startMonitoring()
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    vm.snoozeNudges(for: 60)
    clock.date = clock.date.addingTimeInterval(61)
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.canCalibrate)
    XCTAssertNil(vm.snoozedUntil)
    XCTAssertEqual(vm.postureState, .unknown)
    XCTAssertTrue(vm.statusText.contains("fresh"))
    vm.calibrate()
    XCTAssertNil(vm.lastCalibratedPitch)
  }

  func testGuidedCalibrationRequiresStableFreshSamples() {
    let (vm, motion, _, clock, _) = trackingFixture()
    vm.beginGuidedCalibration()
    let start = clock.date
    for index in 0...16 {
      clock.date = start.addingTimeInterval(Double(index) * 0.2)
      motion.emit(pitch: 20, roll: 5, at: clock.date)
      drainMainQueue()
    }
    XCTAssertFalse(vm.isCalibrating)
    XCTAssertEqual(vm.lastCalibratedPitch, 20)
    XCTAssertEqual(vm.settings.calibratedBaselineRoll, 5)
    XCTAssertTrue(vm.calibrationMessage.contains("complete"))
    vm.beginGuidedCalibration()
    let retry = clock.date
    for index in 0...16 {
      clock.date = retry.addingTimeInterval(Double(index) * 0.2)
      motion.emit(pitch: index % 2 == 0 ? 0 : 40, at: clock.date)
      drainMainQueue()
    }
    XCTAssertEqual(vm.lastCalibratedPitch, 20)
    XCTAssertTrue(vm.calibrationMessage.contains("movement"))
  }

  func testGuidedCalibrationTimesOutWithoutSamples() {
    let (vm, _, _, clock, _) = trackingFixture()
    vm.beginGuidedCalibration()
    clock.date = clock.date.addingTimeInterval(9)
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.isCalibrating)
    XCTAssertNil(vm.lastCalibratedPitch)
    XCTAssertTrue(vm.calibrationMessage.contains("Not enough"))
  }

  func testLiveMidnightScoreAndCSVUseOnlyMeasuredIntervals() throws {
    let (vm, motion, _, clock, _) = trackingFixture()
    let midnight = Calendar.current.startOfDay(for: clock.date)
    clock.date = midnight.addingTimeInterval(-1)
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    vm.calibrate()
    vm.startMonitoring()
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    clock.date = midnight.addingTimeInterval(1)
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    XCTAssertEqual(vm.dailyStats.map(\.goodSeconds), [1, 1])
    XCTAssertEqual(vm.todayUprightText, "Today: 100% upright · 0 slouches")
    XCTAssertNil(vm.todayGrade)
    XCTAssertFalse(vm.goalMetToday)
    XCTAssertEqual(vm.exportHistoryCSV().components(separatedBy: "\n").count, 3)
    vm.stopMonitoring()
    XCTAssertEqual(vm.dailyStats.map(\.goodSeconds), [1, 1])
  }

  func testProfilesPersistAndCanBeDeleted() throws {
    let (vm, motion, _, clock, defaults) = trackingFixture()
    motion.emit(pitch: 20, roll: 3, at: clock.date)
    drainMainQueue()
    vm.calibrate()
    vm.saveCalibrationProfile(named: "Sitting")
    let profile = try XCTUnwrap(vm.calibrationProfiles.first)
    XCTAssertEqual(profile.roll, 3)
    let data = try XCTUnwrap(defaults.data(forKey: AppSettings.Keys.calibrationProfiles))
    XCTAssertEqual(try JSONDecoder().decode([CalibrationProfile].self, from: data), [profile])
    vm.applyCalibrationProfile(profile)
    XCTAssertEqual(vm.lastCalibratedPitch, 20)
    vm.deleteCalibrationProfile(profile)
    XCTAssertTrue(vm.calibrationProfiles.isEmpty)
    XCTAssertEqual(
      try JSONDecoder().decode(
        [CalibrationProfile].self,
        from: XCTUnwrap(defaults.data(forKey: AppSettings.Keys.calibrationProfiles))), [])
  }

  func testCheckpointClearedWithActiveSession() {
    let (vm, motion, _, clock, defaults) = trackingFixture()
    motion.emit(pitch: 20, at: clock.date)
    drainMainQueue()
    vm.calibrate()
    vm.startMonitoring()
    for index in 0...16 {
      clock.date = clock.date.addingTimeInterval(index == 0 ? 0 : 1)
      motion.emit(pitch: 20, at: clock.date)
      drainMainQueue()
    }
    XCTAssertNotNil(defaults.data(forKey: PostureHistoryStore.snapshotKey))
    vm.clearHistory()
    XCTAssertFalse(vm.isMonitoring)
    XCTAssertNil(defaults.data(forKey: PostureHistoryStore.snapshotKey))
    XCTAssertTrue(PostureHistoryStore(defaults: defaults).stats.isEmpty)
  }
}

extension PostureViewModelTests {
  private func startupFixture(
    settings: AppSettings, motion: FakeHeadMotionProvider = FakeHeadMotionProvider(),
    output: FakeAudioOutputMonitor = FakeAudioOutputMonitor(isHeadphoneOutput: true),
    history: PostureHistoryStore? = nil
  ) -> PostureViewModel {
    let defaults = isolatedDefaults()
    return PostureViewModel(
      motionProvider: motion, audioOutputMonitor: output,
      microphoneMonitor: FakeMicrophoneMonitor(), activityMonitor: FakeActivityMonitor(),
      batteryMonitor: FakeAirPodsBatteryMonitor(), notifier: FakePostureNotifier(),
      historyStore: history ?? PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults, settings: settings, startHeartbeat: false)
  }

  func testStartupMonitoringRequiresOptInAndCompletedOnboarding() {
    let normal = startupFixture(settings: AppSettings(hasCompletedOnboarding: true))
    XCTAssertFalse(normal.isMonitoring)
    XCTAssertFalse(normal.isWaitingToStart)
    let optedIn = startupFixture(
      settings: AppSettings(startMonitoringAtLaunch: true, hasCompletedOnboarding: true))
    XCTAssertTrue(optedIn.isMonitoring)
    XCTAssertFalse(optedIn.isWaitingToStart)
    let onboarding = startupFixture(settings: AppSettings(startMonitoringAtLaunch: true))
    XCTAssertFalse(onboarding.isMonitoring)
    XCTAssertFalse(onboarding.isWaitingToStart)
    onboarding.completeOnboarding()
    XCTAssertTrue(onboarding.isMonitoring)
  }

  func testStartupWaitsForHeadphonesWithoutRequiringReconnectOptIn() {
    let output = FakeAudioOutputMonitor(isHeadphoneOutput: false)
    let motion = FakeHeadMotionProvider()
    motion.isDeviceMotionAvailable = false
    let vm = startupFixture(
      settings: AppSettings(startMonitoringAtLaunch: true, hasCompletedOnboarding: true),
      motion: motion, output: output)
    XCTAssertTrue(vm.isWaitingToStart)
    XCTAssertFalse(vm.isMonitoring)
    output.isHeadphoneOutput = true
    output.onChange?(true)
    drainMainQueue()
    XCTAssertFalse(vm.isMonitoring)
    motion.isDeviceMotionAvailable = true
    vm.refreshTrackingHealth()
    XCTAssertTrue(vm.isMonitoring)
    XCTAssertFalse(vm.isWaitingToStart)
    vm.stopMonitoring()
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.isMonitoring)
  }

  func testCancelOrDisablePendingStartupDoesNotStartLater() {
    let output = FakeAudioOutputMonitor(isHeadphoneOutput: false)
    let settings = AppSettings(startMonitoringAtLaunch: true, hasCompletedOnboarding: true)
    let canceled = startupFixture(settings: settings, output: output)
    canceled.stopMonitoring()
    output.isHeadphoneOutput = true
    canceled.refreshTrackingHealth()
    XCTAssertFalse(canceled.isMonitoring)
    XCTAssertFalse(canceled.isWaitingToStart)
    output.isHeadphoneOutput = false
    let disabled = startupFixture(settings: settings, output: output)
    disabled.updateStartMonitoringAtLaunch(false)
    output.isHeadphoneOutput = true
    disabled.refreshTrackingHealth()
    XCTAssertFalse(disabled.isMonitoring)
    XCTAssertFalse(disabled.isWaitingToStart)
  }

  func testDeniedMotionDoesNotBypassPermissionAndCanBeCanceled() {
    let motion = FakeHeadMotionProvider()
    motion.authorization = .denied
    let vm = startupFixture(
      settings: AppSettings(
        startMonitoringAtLaunch: true, resumeAfterInterruption: true, hasCompletedOnboarding: true),
      motion: motion)
    XCTAssertFalse(vm.isMonitoring)
    XCTAssertTrue(vm.isWaitingToStart)
    XCTAssertTrue(vm.statusText.contains("denied"))
    vm.updateStartMonitoringAtLaunch(false)
    motion.authorization = .authorized
    vm.refreshTrackingHealth()
    XCTAssertFalse(vm.isMonitoring)
  }

  func testDisablingStartupDoesNotStopActiveMonitoring() {
    let vm = startupFixture(
      settings: AppSettings(startMonitoringAtLaunch: true, hasCompletedOnboarding: true))
    vm.updateStartMonitoringAtLaunch(false)
    XCTAssertTrue(vm.isMonitoring)
  }

  func testTestNotificationRefreshesPermissionWithoutPromptingOrChangingTracking() {
    let (vm, _, notifier, _, _) = trackingFixture()
    vm.startMonitoring()
    let originalState = vm.postureState
    notifier.nextAuthorizationResult = false
    vm.sendTestNotification()
    drainMainQueue()
    XCTAssertEqual(notifier.testNotificationCount, 0)
    XCTAssertEqual(notifier.requestCount, 0)
    XCTAssertFalse(vm.isTestingNotification)
    XCTAssertTrue(vm.testNotificationMessage?.contains("disabled") == true)
    notifier.nextAuthorizationResult = true
    vm.updateSoundEnabled(false)
    vm.updateSpeechEnabled(true)
    vm.sendTestNotification()
    vm.sendTestNotification()
    drainMainQueue()
    XCTAssertEqual(notifier.testNotificationCount, 1)
    XCTAssertEqual(notifier.testNotificationSettings?.soundEnabled, false)
    XCTAssertEqual(notifier.testNotificationSettings?.speechEnabled, true)
    XCTAssertTrue(vm.testNotificationMessage?.contains("submitted") == true)
    XCTAssertTrue(vm.testNotificationMessage?.contains("Focus") == true)
    XCTAssertTrue(vm.isMonitoring)
    XCTAssertEqual(vm.postureState, originalState)
    XCTAssertEqual(vm.sessionSlouchEvents, 0)
    XCTAssertTrue(vm.dailyStats.isEmpty)
    XCTAssertEqual(notifier.nudgeCount, 0)
  }

  func testTestNotificationSurfacesSchedulingFailure() {
    let (vm, _, notifier, _, _) = trackingFixture()
    notifier.testNotificationError = NSError(
      domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scheduling unavailable"])
    vm.sendTestNotification()
    drainMainQueue()
    XCTAssertFalse(vm.isTestingNotification)
    XCTAssertTrue(vm.testNotificationMessage?.contains("Scheduling unavailable") == true)
    XCTAssertFalse(vm.testNotificationMessage?.contains("submitted") == true)
  }

  func testRecoveryNoticeCanBeDismissedWithoutDeletingHistory() {
    let defaults = isolatedDefaults()
    let start = Date()
    var session = SessionAccumulator()
    session.record(from: start, to: start.addingTimeInterval(1), state: .good)
    let original = PostureHistoryStore(defaults: defaults)
    original.checkpoint(session.hours)
    let recovered = PostureHistoryStore(defaults: defaults)
    let vm = startupFixture(settings: AppSettings(), history: recovered)
    XCTAssertNotNil(vm.recoveryMessage)
    vm.dismissRecoveryMessage()
    XCTAssertNil(vm.recoveryMessage)
    XCTAssertEqual(vm.dailyStats.first?.goodSeconds, 1)
    XCTAssertEqual(PostureHistoryStore(defaults: defaults).stats.first?.goodSeconds, 1)
    let second = startupFixture(settings: AppSettings(), history: recovered)
    XCTAssertNotNil(second.recoveryMessage)
    second.clearHistory()
    XCTAssertNil(second.recoveryMessage)
    XCTAssertTrue(PostureHistoryStore(defaults: defaults).stats.isEmpty)
  }
}
