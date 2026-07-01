import AppKit
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: settings
    )

    viewModel.updateRecoverSeconds(2.5)

    XCTAssertEqual(AppSettings.load(from: defaults).recoverSeconds, 2.5)
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
    historyStore.add(
      PostureSession(
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
    XCTAssertEqual(notifier.requestCount, 1)
    XCTAssertEqual(notifier.refreshCount, 1)
  }

  func testDidBecomeActiveRefreshesNotificationStatus() {
    let notifier = FakePostureNotifier()
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults())
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: micMonitor,
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: micMonitor,
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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

    XCTAssertEqual(notifier.nudgeCount, 1)
    XCTAssertNotNil(notifier.lastDrop)
    XCTAssertGreaterThan(notifier.lastDrop ?? 0, 0)
  }

  func testConnectedDeviceNameShownWhenNotMonitoring() {
    let audioMonitor = FakeAudioOutputMonitor(airPodsActive: true, deviceName: "AirPods Pro")
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: audioMonitor,
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults())
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(isMicActive: false),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(isMicActive: false),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: store
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: store
    )

    XCTAssertEqual(viewModel.todayUprightText, "Today: 75% upright · 3 slouches")
  }

  func testTerminationNotificationStopsMonitoring() {
    let viewModel = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults())
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
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

  private func drainMainQueue() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  }

  func testAutoDriftAdjustsBaselineWhenEnabledWithoutPersisting() {
    let defaults = isolatedDefaults()
    let store = PostureHistoryStore(defaults: defaults)
    let fakeMotion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: fakeMotion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: store,
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: AppSettings()
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
    let viewModel = PostureViewModel(
      motionProvider: fakeMotion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
    )

    let t0 = Date(timeIntervalSince1970: 0)
    fakeMotion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    // Accumulate ~10 minutes of good monitored time (< the 50-minute interval).
    fakeMotion.emit(pitch: 20, at: t0)
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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      activityMonitor: activity,
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
    )

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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
    )

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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: AppSettings()
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
      thresholdDegrees: 10,
      holdSeconds: 0,
      recoverSeconds: 1,
      dailyUprightGoalPercent: 80
    )
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings
    )

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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: AppSettings(recalibrationReminderDays: 14, lastCalibrationDate: Date())
    )
    XCTAssertFalse(recent.needsRecalibration)

    let stale = PostureViewModel(
      motionProvider: FakeHeadMotionProvider(),
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: AppSettings(
        recalibrationReminderDays: 14,
        lastCalibrationDate: Date(timeIntervalSinceNow: -15 * 86_400))
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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()
    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 20 * 60))
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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1_200))
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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings)

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
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: settings)

    let t0 = Date(timeIntervalSince1970: 0)
    motion.emit(pitch: 20, at: t0)
    drainMainQueue()
    viewModel.calibrate()
    viewModel.startMonitoring()

    motion.emit(pitch: 20, at: t0)
    motion.emit(pitch: 20, at: Date(timeIntervalSince1970: 1_200))
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      microphoneMonitor: FakeMicrophoneMonitor(),
      batteryMonitor: battery,
      notifier: notifier,
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: AppSettings()
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
  }

  func testCalibrateAveragedUsesRecentAverage() {
    let motion = FakeHeadMotionProvider()
    let viewModel = PostureViewModel(
      motionProvider: motion,
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: isolatedDefaults()),
      settings: AppSettings()
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
      audioOutputMonitor: FakeAudioOutputMonitor(airPodsActive: true),
      notifier: FakePostureNotifier(),
      historyStore: PostureHistoryStore(defaults: defaults),
      settingsDefaults: defaults,
      settings: AppSettings()
    )

    XCTAssertTrue(viewModel.needsOnboarding)
    viewModel.completeOnboarding()
    XCTAssertFalse(viewModel.needsOnboarding)
    XCTAssertTrue(AppSettings.load(from: defaults).hasCompletedOnboarding)
  }
}

private final class FakeHeadMotionProvider: HeadMotionProvider {
  var isDeviceMotionAvailable = true
  var onReading: ((HeadMotionReading) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onError: ((String) -> Void)?

  func start() {}
  func stop() {}

  func emit(pitch: Double, at timestamp: Date) {
    onReading?(HeadMotionReading(pitch: pitch, roll: 0, yaw: 0, timestamp: timestamp))
  }
}

private final class FakeAudioOutputMonitor: AudioOutputMonitoring {
  var airPodsActive: Bool
  var deviceName: String
  var onChange: ((Bool) -> Void)?

  init(airPodsActive: Bool, deviceName: String = "") {
    self.airPodsActive = airPodsActive
    self.deviceName = deviceName
  }

  func start() {}
}

private final class FakePostureNotifier: PostureNotifying {
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
