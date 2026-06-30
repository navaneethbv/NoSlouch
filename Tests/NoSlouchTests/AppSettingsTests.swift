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
