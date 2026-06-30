import Foundation
import XCTest
@testable import NoSlouch

final class FakeHeadMotionProvider: HeadMotionProvider {
  var isAvailable = true
  var onReading: ((HeadMotionReading) -> Void)?
  var onConnectionChanged: ((Bool) -> Void)?
  var onError: ((String) -> Void)?

  func start() {}
  func stop() {}

  func emit(pitch: Double, at timestamp: Date) {
    onReading?(HeadMotionReading(pitch: pitch, roll: 0, yaw: 0, timestamp: timestamp))
  }
  
  func emit(pitch: Double, roll: Double, yaw: Double, at timestamp: Date) {
    onReading?(HeadMotionReading(pitch: pitch, roll: roll, yaw: yaw, timestamp: timestamp))
  }
}

final class FakeAudioOutputMonitor: AudioOutputMonitoring {
  var headphonesActive: Bool
  var deviceName: String
  var onChange: ((Bool) -> Void)?

  init(airPodsActive: Bool, deviceName: String = "") {
    self.headphonesActive = airPodsActive
    self.deviceName = deviceName
  }

  func start() {}
}

final class FakePostureNotifier: PostureNotifying {
  private(set) var nudgeCount = 0
  private(set) var requestCount = 0
  private(set) var refreshCount = 0
  private(set) var openSettingsCount = 0
  private(set) var pauseNoticeCount = 0
  private(set) var lastDrop: Double?
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

  func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date, drop: Double?) {
    nudgeCount += 1
    lastDrop = drop
  }

  private(set) var breakNudgeCount = 0
  func nudgeBreak(settings: AppSettings, notificationsEnabled: Bool) {
    breakNudgeCount += 1
  }

  private(set) var reminderNudgeCounts: [ReminderKind: Int] = [:]
  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool) {
    reminderNudgeCounts[kind, default: 0] += 1
  }

  func previewSound(named name: String) {
    previewCount += 1
    lastPreviewName = name
  }
}

final class FakeMicrophoneMonitor: MicrophoneMonitoring {
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

final class FakeAirPodsBatteryMonitor: AirPodsBatteryMonitoring {
  var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)?
  var startCalled = false
  var stopCalled = false
  var lastDeviceName: String?

  func start(deviceName: String) {
    startCalled = true
    lastDeviceName = deviceName
  }

  func stop() {
    stopCalled = true
  }

  func emit(info: AirPodsBatteryInfo) {
    onBatteryUpdate?(info)
  }
}
