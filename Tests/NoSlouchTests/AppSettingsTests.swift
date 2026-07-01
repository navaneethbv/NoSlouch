import XCTest

@testable import NoSlouch

final class AppSettingsTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "NoSlouch.AppSettingsTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testSettingsLoadDefaults() {
    let settings = AppSettings.load(from: defaults)

    XCTAssertEqual(settings.thresholdDegrees, 12.0)
    XCTAssertEqual(settings.holdSeconds, 3.0)
    XCTAssertEqual(settings.recoverSeconds, 1.5)
    XCTAssertEqual(settings.alertCooldownSeconds, 60.0)
    XCTAssertTrue(settings.soundEnabled)
    XCTAssertFalse(settings.speechEnabled)
    XCTAssertFalse(settings.invertedPitch)
  }

  func testSettingsPersistChangedValues() {
    let changed = AppSettings(
      thresholdDegrees: 18.5,
      holdSeconds: 4.25,
      recoverSeconds: 2.0,
      alertCooldownSeconds: 90.0,
      soundEnabled: false,
      speechEnabled: true,
      invertedPitch: true
    )

    changed.save(to: defaults)

    XCTAssertEqual(AppSettings.load(from: defaults), changed)
  }

  func testAutoDriftDefaultsOffAndRoundTrips() {
    XCTAssertFalse(AppSettings.load(from: defaults).autoDriftEnabled)

    var settings = AppSettings.load(from: defaults)
    settings.autoDriftEnabled = true
    settings.save(to: defaults)

    XCTAssertTrue(AppSettings.load(from: defaults).autoDriftEnabled)
  }

  func testAwayEscalationAndCustomMessagesRoundTrip() {
    XCTAssertFalse(AppSettings.load(from: defaults).pauseWhenAwayEnabled)
    XCTAssertFalse(AppSettings.load(from: defaults).escalatingNudges)
    XCTAssertEqual(AppSettings.load(from: defaults).customNudgeMessages, [])

    var settings = AppSettings.load(from: defaults)
    settings.pauseWhenAwayEnabled = true
    settings.escalatingNudges = true
    settings.customNudgeMessages = ["Sit up", "Chin up"]
    settings.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertTrue(loaded.pauseWhenAwayEnabled)
    XCTAssertTrue(loaded.escalatingNudges)
    XCTAssertEqual(loaded.customNudgeMessages, ["Sit up", "Chin up"])
  }

  func testGoalRecalibrationAndCalibrationDateRoundTrip() {
    XCTAssertEqual(AppSettings.load(from: defaults).dailyUprightGoalPercent, 80)
    XCTAssertEqual(AppSettings.load(from: defaults).recalibrationReminderDays, 14)
    XCTAssertNil(AppSettings.load(from: defaults).lastCalibrationDate)

    var settings = AppSettings.load(from: defaults)
    settings.dailyUprightGoalPercent = 90
    settings.recalibrationReminderDays = 7
    settings.lastCalibrationDate = Date(timeIntervalSince1970: 1_700_000_000)
    settings.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertEqual(loaded.dailyUprightGoalPercent, 90)
    XCTAssertEqual(loaded.recalibrationReminderDays, 7)
    XCTAssertEqual(
      loaded.lastCalibrationDate?.timeIntervalSince1970 ?? 0, 1_700_000_000, accuracy: 0.001)
  }

  func testRemindersAndQuietHoursRoundTrip() {
    let initial = AppSettings.load(from: defaults)
    XCTAssertFalse(initial.eyeRestEnabled)
    XCTAssertFalse(initial.quietHoursEnabled)
    XCTAssertEqual(initial.quietStartMinutes, 1_320)
    XCTAssertEqual(initial.quietEndMinutes, 420)

    var settings = AppSettings.load(from: defaults)
    settings.eyeRestEnabled = true
    settings.eyeRestMinutes = 25
    settings.hydrationEnabled = true
    settings.hydrationMinutes = 40
    settings.movementRemindersEnabled = true
    settings.movementMinutes = 55
    settings.quietHoursEnabled = true
    settings.quietStartMinutes = 1_290
    settings.quietEndMinutes = 400
    settings.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertTrue(loaded.eyeRestEnabled)
    XCTAssertEqual(loaded.eyeRestMinutes, 25)
    XCTAssertTrue(loaded.hydrationEnabled)
    XCTAssertEqual(loaded.hydrationMinutes, 40)
    XCTAssertTrue(loaded.movementRemindersEnabled)
    XCTAssertEqual(loaded.movementMinutes, 55)
    XCTAssertTrue(loaded.quietHoursEnabled)
    XCTAssertEqual(loaded.quietStartMinutes, 1_290)
    XCTAssertEqual(loaded.quietEndMinutes, 400)
  }

  func testTiltBatteryAndSnoozeRoundTrip() {
    XCTAssertFalse(AppSettings.load(from: defaults).tiltDetectionEnabled)
    XCTAssertTrue(AppSettings.load(from: defaults).lowBatteryWarningEnabled)
    XCTAssertEqual(AppSettings.load(from: defaults).snoozePresetsMinutes, [15, 30, 60])

    var settings = AppSettings.load(from: defaults)
    settings.tiltDetectionEnabled = true
    settings.tiltThresholdDegrees = 12
    settings.lowBatteryWarningEnabled = false
    settings.snoozePresetsMinutes = [5, 10, 20]
    settings.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertTrue(loaded.tiltDetectionEnabled)
    XCTAssertEqual(loaded.tiltThresholdDegrees, 12)
    XCTAssertFalse(loaded.lowBatteryWarningEnabled)
    XCTAssertEqual(loaded.snoozePresetsMinutes, [5, 10, 20])
  }

  func testWeeklyDigestAndOnboardingRoundTrip() {
    XCTAssertFalse(AppSettings.load(from: defaults).weeklyDigestEnabled)
    XCTAssertFalse(AppSettings.load(from: defaults).hasCompletedOnboarding)

    var settings = AppSettings.load(from: defaults)
    settings.weeklyDigestEnabled = true
    settings.hasCompletedOnboarding = true
    settings.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertTrue(loaded.weeklyDigestEnabled)
    XCTAssertTrue(loaded.hasCompletedOnboarding)
  }

  func testSettingsIgnoreInvalidStoredValues() {
    defaults.set(-1.0, forKey: AppSettings.Keys.thresholdDegrees)
    defaults.set(0.0, forKey: AppSettings.Keys.holdSeconds)
    defaults.set(Double.nan, forKey: AppSettings.Keys.recoverSeconds)
    defaults.set(-60.0, forKey: AppSettings.Keys.alertCooldownSeconds)
    defaults.set(false, forKey: AppSettings.Keys.soundEnabled)
    defaults.set(true, forKey: AppSettings.Keys.speechEnabled)
    defaults.set(true, forKey: AppSettings.Keys.invertedPitch)

    let settings = AppSettings.load(from: defaults)

    XCTAssertEqual(settings.thresholdDegrees, 12.0)
    XCTAssertEqual(settings.holdSeconds, 3.0)
    XCTAssertEqual(settings.recoverSeconds, 1.5)
    XCTAssertEqual(settings.alertCooldownSeconds, 60.0)
    XCTAssertFalse(settings.soundEnabled)
    XCTAssertTrue(settings.speechEnabled)
    XCTAssertTrue(settings.invertedPitch)
  }

  func testSettingsLoadDefaultsSoundName() {
    let settings = AppSettings.load(from: defaults)

    XCTAssertEqual(settings.soundName, "Glass")
  }

  func testSettingsPersistSoundName() {
    var changed = AppSettings()
    changed.soundName = "Ping"

    changed.save(to: defaults)

    XCTAssertEqual(AppSettings.load(from: defaults).soundName, "Ping")
  }

  func testSettingsIgnoreInvalidSoundName() {
    defaults.set("", forKey: AppSettings.Keys.soundName)
    XCTAssertEqual(AppSettings.load(from: defaults).soundName, "Glass")

    defaults.set("NotARealSound", forKey: AppSettings.Keys.soundName)
    XCTAssertEqual(AppSettings.load(from: defaults).soundName, "Glass")
  }

  func testSettingsIgnoreInvalidStoredBooleans() {
    defaults.set("disabled", forKey: AppSettings.Keys.soundEnabled)
    defaults.set("enabled", forKey: AppSettings.Keys.speechEnabled)
    defaults.set("yes", forKey: AppSettings.Keys.invertedPitch)

    let settings = AppSettings.load(from: defaults)

    XCTAssertTrue(settings.soundEnabled)
    XCTAssertFalse(settings.speechEnabled)
    XCTAssertFalse(settings.invertedPitch)
  }

  func testSettingsPersistCalibratedBaselinePitch() {
    var changed = AppSettings()
    changed.calibratedBaselinePitch = 14.5

    changed.save(to: defaults)

    XCTAssertEqual(AppSettings.load(from: defaults).calibratedBaselinePitch, 14.5)
  }

  func testSettingsIgnoreInvalidCalibratedBaselinePitch() {
    defaults.set(Double.nan, forKey: AppSettings.Keys.calibratedBaselinePitch)
    XCTAssertNil(AppSettings.load(from: defaults).calibratedBaselinePitch)

    defaults.set(Double.infinity, forKey: AppSettings.Keys.calibratedBaselinePitch)
    XCTAssertNil(AppSettings.load(from: defaults).calibratedBaselinePitch)
  }
  func testSettingsLoadDefaultsForNewFeatures() {
    let settings = AppSettings.load(from: defaults)

    XCTAssertTrue(settings.muteInMeetings)
    XCTAssertFalse(settings.breakRemindersEnabled)
    XCTAssertEqual(settings.breakReminderMinutes, 50.0)
  }

  func testSettingsPersistNewFeatures() {
    var changed = AppSettings()
    changed.muteInMeetings = false
    changed.breakRemindersEnabled = true
    changed.breakReminderMinutes = 35.0

    changed.save(to: defaults)

    let loaded = AppSettings.load(from: defaults)
    XCTAssertFalse(loaded.muteInMeetings)
    XCTAssertTrue(loaded.breakRemindersEnabled)
    XCTAssertEqual(loaded.breakReminderMinutes, 35.0)
  }
}
