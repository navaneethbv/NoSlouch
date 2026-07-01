import Foundation

public struct AppSettings: Equatable {
  public enum Keys {
    public static let thresholdDegrees = "settings.thresholdDegrees"
    public static let holdSeconds = "settings.holdSeconds"
    public static let recoverSeconds = "settings.recoverSeconds"
    public static let alertCooldownSeconds = "settings.alertCooldownSeconds"
    public static let soundEnabled = "settings.soundEnabled"
    public static let speechEnabled = "settings.speechEnabled"
    public static let invertedPitch = "settings.invertedPitch"
    public static let soundName = "settings.soundName"
    public static let calibratedBaselinePitch = "settings.calibratedBaselinePitch"
    public static let muteInMeetings = "settings.muteInMeetings"
    public static let breakRemindersEnabled = "settings.breakRemindersEnabled"
    public static let breakReminderMinutes = "settings.breakReminderMinutes"
    public static let autoDriftEnabled = "settings.autoDriftEnabled"
    public static let pauseWhenAwayEnabled = "settings.pauseWhenAwayEnabled"
    public static let escalatingNudges = "settings.escalatingNudges"
    public static let customNudgeMessages = "settings.customNudgeMessages"
    public static let dailyUprightGoalPercent = "settings.dailyUprightGoalPercent"
    public static let recalibrationReminderDays = "settings.recalibrationReminderDays"
    public static let lastCalibrationDate = "settings.lastCalibrationDate"
    public static let eyeRestEnabled = "settings.eyeRestEnabled"
    public static let eyeRestMinutes = "settings.eyeRestMinutes"
    public static let hydrationEnabled = "settings.hydrationEnabled"
    public static let hydrationMinutes = "settings.hydrationMinutes"
    public static let movementRemindersEnabled = "settings.movementRemindersEnabled"
    public static let movementMinutes = "settings.movementMinutes"
    public static let quietHoursEnabled = "settings.quietHoursEnabled"
    public static let quietStartMinutes = "settings.quietStartMinutes"
    public static let quietEndMinutes = "settings.quietEndMinutes"
    public static let tiltDetectionEnabled = "settings.tiltDetectionEnabled"
    public static let tiltThresholdDegrees = "settings.tiltThresholdDegrees"
    public static let lowBatteryWarningEnabled = "settings.lowBatteryWarningEnabled"
    public static let snoozePresetsMinutes = "settings.snoozePresetsMinutes"
    public static let weeklyDigestEnabled = "settings.weeklyDigestEnabled"
    public static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
  }

  public static let availableSoundNames: [String] = [
    "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
    "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
  ]

  public var thresholdDegrees: Double
  public var holdSeconds: TimeInterval
  public var recoverSeconds: TimeInterval
  public var alertCooldownSeconds: TimeInterval
  public var soundEnabled: Bool
  public var speechEnabled: Bool
  public var invertedPitch: Bool
  public var soundName: String
  public var calibratedBaselinePitch: Double?
  public var muteInMeetings: Bool
  public var breakRemindersEnabled: Bool
  public var breakReminderMinutes: Double
  public var autoDriftEnabled: Bool
  public var pauseWhenAwayEnabled: Bool
  public var escalatingNudges: Bool
  public var customNudgeMessages: [String]
  public var dailyUprightGoalPercent: Double
  public var recalibrationReminderDays: Double
  public var lastCalibrationDate: Date?
  public var eyeRestEnabled: Bool
  public var eyeRestMinutes: Double
  public var hydrationEnabled: Bool
  public var hydrationMinutes: Double
  public var movementRemindersEnabled: Bool
  public var movementMinutes: Double
  public var quietHoursEnabled: Bool
  public var quietStartMinutes: Int
  public var quietEndMinutes: Int
  public var tiltDetectionEnabled: Bool
  public var tiltThresholdDegrees: Double
  public var lowBatteryWarningEnabled: Bool
  public var snoozePresetsMinutes: [Int]
  public var weeklyDigestEnabled: Bool
  public var hasCompletedOnboarding: Bool

  public init(
    thresholdDegrees: Double = 12.0,
    holdSeconds: TimeInterval = 3.0,
    recoverSeconds: TimeInterval = 1.5,
    alertCooldownSeconds: TimeInterval = 60.0,
    soundEnabled: Bool = true,
    speechEnabled: Bool = false,
    invertedPitch: Bool = false,
    soundName: String = "Glass",
    calibratedBaselinePitch: Double? = nil,
    muteInMeetings: Bool = true,
    breakRemindersEnabled: Bool = false,
    breakReminderMinutes: Double = 50.0,
    autoDriftEnabled: Bool = false,
    pauseWhenAwayEnabled: Bool = false,
    escalatingNudges: Bool = false,
    customNudgeMessages: [String] = [],
    dailyUprightGoalPercent: Double = 80.0,
    recalibrationReminderDays: Double = 14.0,
    lastCalibrationDate: Date? = nil,
    eyeRestEnabled: Bool = false,
    eyeRestMinutes: Double = 20.0,
    hydrationEnabled: Bool = false,
    hydrationMinutes: Double = 45.0,
    movementRemindersEnabled: Bool = false,
    movementMinutes: Double = 50.0,
    quietHoursEnabled: Bool = false,
    quietStartMinutes: Int = 1_320,
    quietEndMinutes: Int = 420,
    tiltDetectionEnabled: Bool = false,
    tiltThresholdDegrees: Double = 15.0,
    lowBatteryWarningEnabled: Bool = true,
    snoozePresetsMinutes: [Int] = [15, 30, 60],
    weeklyDigestEnabled: Bool = false,
    hasCompletedOnboarding: Bool = false
  ) {
    self.thresholdDegrees = thresholdDegrees
    self.holdSeconds = holdSeconds
    self.recoverSeconds = recoverSeconds
    self.alertCooldownSeconds = alertCooldownSeconds
    self.soundEnabled = soundEnabled
    self.speechEnabled = speechEnabled
    self.invertedPitch = invertedPitch
    self.soundName = soundName
    self.calibratedBaselinePitch = calibratedBaselinePitch
    self.muteInMeetings = muteInMeetings
    self.breakRemindersEnabled = breakRemindersEnabled
    self.breakReminderMinutes = breakReminderMinutes
    self.autoDriftEnabled = autoDriftEnabled
    self.pauseWhenAwayEnabled = pauseWhenAwayEnabled
    self.escalatingNudges = escalatingNudges
    self.customNudgeMessages = customNudgeMessages
    self.dailyUprightGoalPercent = dailyUprightGoalPercent
    self.recalibrationReminderDays = recalibrationReminderDays
    self.lastCalibrationDate = lastCalibrationDate
    self.eyeRestEnabled = eyeRestEnabled
    self.eyeRestMinutes = eyeRestMinutes
    self.hydrationEnabled = hydrationEnabled
    self.hydrationMinutes = hydrationMinutes
    self.movementRemindersEnabled = movementRemindersEnabled
    self.movementMinutes = movementMinutes
    self.quietHoursEnabled = quietHoursEnabled
    self.quietStartMinutes = quietStartMinutes
    self.quietEndMinutes = quietEndMinutes
    self.tiltDetectionEnabled = tiltDetectionEnabled
    self.tiltThresholdDegrees = tiltThresholdDegrees
    self.lowBatteryWarningEnabled = lowBatteryWarningEnabled
    self.snoozePresetsMinutes = snoozePresetsMinutes
    self.weeklyDigestEnabled = weeklyDigestEnabled
    self.hasCompletedOnboarding = hasCompletedOnboarding
  }

  public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
    let rawPitch = defaults.object(forKey: Keys.calibratedBaselinePitch) as? Double
    let validatedPitch = (rawPitch?.isFinite == true) ? rawPitch : nil

    return AppSettings(
      thresholdDegrees: positiveDouble(
        forKey: Keys.thresholdDegrees,
        in: defaults,
        defaultValue: 12.0
      ),
      holdSeconds: positiveDouble(
        forKey: Keys.holdSeconds,
        in: defaults,
        defaultValue: 3.0
      ),
      recoverSeconds: positiveDouble(
        forKey: Keys.recoverSeconds,
        in: defaults,
        defaultValue: 1.5
      ),
      alertCooldownSeconds: positiveDouble(
        forKey: Keys.alertCooldownSeconds,
        in: defaults,
        defaultValue: 60.0
      ),
      soundEnabled: bool(forKey: Keys.soundEnabled, in: defaults, defaultValue: true),
      speechEnabled: bool(forKey: Keys.speechEnabled, in: defaults, defaultValue: false),
      invertedPitch: bool(forKey: Keys.invertedPitch, in: defaults, defaultValue: false),
      soundName: soundName(forKey: Keys.soundName, in: defaults, defaultValue: "Glass"),
      calibratedBaselinePitch: validatedPitch,
      muteInMeetings: bool(forKey: Keys.muteInMeetings, in: defaults, defaultValue: true),
      breakRemindersEnabled: bool(
        forKey: Keys.breakRemindersEnabled,
        in: defaults,
        defaultValue: false
      ),
      breakReminderMinutes: positiveDouble(
        forKey: Keys.breakReminderMinutes,
        in: defaults,
        defaultValue: 50.0
      ),
      autoDriftEnabled: bool(forKey: Keys.autoDriftEnabled, in: defaults, defaultValue: false),
      pauseWhenAwayEnabled: bool(
        forKey: Keys.pauseWhenAwayEnabled,
        in: defaults,
        defaultValue: false
      ),
      escalatingNudges: bool(forKey: Keys.escalatingNudges, in: defaults, defaultValue: false),
      customNudgeMessages: defaults.stringArray(forKey: Keys.customNudgeMessages) ?? [],
      dailyUprightGoalPercent: positiveDouble(
        forKey: Keys.dailyUprightGoalPercent,
        in: defaults,
        defaultValue: 80.0
      ),
      recalibrationReminderDays: positiveDouble(
        forKey: Keys.recalibrationReminderDays,
        in: defaults,
        defaultValue: 14.0
      ),
      lastCalibrationDate: date(forKey: Keys.lastCalibrationDate, in: defaults),
      eyeRestEnabled: bool(forKey: Keys.eyeRestEnabled, in: defaults, defaultValue: false),
      eyeRestMinutes: positiveDouble(forKey: Keys.eyeRestMinutes, in: defaults, defaultValue: 20.0),
      hydrationEnabled: bool(forKey: Keys.hydrationEnabled, in: defaults, defaultValue: false),
      hydrationMinutes: positiveDouble(
        forKey: Keys.hydrationMinutes, in: defaults, defaultValue: 45.0),
      movementRemindersEnabled: bool(
        forKey: Keys.movementRemindersEnabled, in: defaults, defaultValue: false),
      movementMinutes: positiveDouble(
        forKey: Keys.movementMinutes, in: defaults, defaultValue: 50.0),
      quietHoursEnabled: bool(forKey: Keys.quietHoursEnabled, in: defaults, defaultValue: false),
      quietStartMinutes: int(forKey: Keys.quietStartMinutes, in: defaults, defaultValue: 1_320),
      quietEndMinutes: int(forKey: Keys.quietEndMinutes, in: defaults, defaultValue: 420),
      tiltDetectionEnabled: bool(
        forKey: Keys.tiltDetectionEnabled, in: defaults, defaultValue: false),
      tiltThresholdDegrees: positiveDouble(
        forKey: Keys.tiltThresholdDegrees, in: defaults, defaultValue: 15.0),
      lowBatteryWarningEnabled: bool(
        forKey: Keys.lowBatteryWarningEnabled, in: defaults, defaultValue: true),
      snoozePresetsMinutes: (defaults.array(forKey: Keys.snoozePresetsMinutes) as? [Int])
        ?? [15, 30, 60],
      weeklyDigestEnabled: bool(
        forKey: Keys.weeklyDigestEnabled, in: defaults, defaultValue: false),
      hasCompletedOnboarding: bool(
        forKey: Keys.hasCompletedOnboarding, in: defaults, defaultValue: false)
    )
  }

  public func save(to defaults: UserDefaults = .standard) {
    defaults.set(thresholdDegrees, forKey: Keys.thresholdDegrees)
    defaults.set(holdSeconds, forKey: Keys.holdSeconds)
    defaults.set(recoverSeconds, forKey: Keys.recoverSeconds)
    defaults.set(alertCooldownSeconds, forKey: Keys.alertCooldownSeconds)
    defaults.set(soundEnabled, forKey: Keys.soundEnabled)
    defaults.set(speechEnabled, forKey: Keys.speechEnabled)
    defaults.set(invertedPitch, forKey: Keys.invertedPitch)
    defaults.set(soundName, forKey: Keys.soundName)
    if let calibratedBaselinePitch {
      defaults.set(calibratedBaselinePitch, forKey: Keys.calibratedBaselinePitch)
    } else {
      defaults.removeObject(forKey: Keys.calibratedBaselinePitch)
    }
    defaults.set(muteInMeetings, forKey: Keys.muteInMeetings)
    defaults.set(breakRemindersEnabled, forKey: Keys.breakRemindersEnabled)
    defaults.set(breakReminderMinutes, forKey: Keys.breakReminderMinutes)
    defaults.set(autoDriftEnabled, forKey: Keys.autoDriftEnabled)
    defaults.set(pauseWhenAwayEnabled, forKey: Keys.pauseWhenAwayEnabled)
    defaults.set(escalatingNudges, forKey: Keys.escalatingNudges)
    defaults.set(customNudgeMessages, forKey: Keys.customNudgeMessages)
    defaults.set(dailyUprightGoalPercent, forKey: Keys.dailyUprightGoalPercent)
    defaults.set(recalibrationReminderDays, forKey: Keys.recalibrationReminderDays)
    defaults.set(eyeRestEnabled, forKey: Keys.eyeRestEnabled)
    defaults.set(eyeRestMinutes, forKey: Keys.eyeRestMinutes)
    defaults.set(hydrationEnabled, forKey: Keys.hydrationEnabled)
    defaults.set(hydrationMinutes, forKey: Keys.hydrationMinutes)
    defaults.set(movementRemindersEnabled, forKey: Keys.movementRemindersEnabled)
    defaults.set(movementMinutes, forKey: Keys.movementMinutes)
    defaults.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled)
    defaults.set(quietStartMinutes, forKey: Keys.quietStartMinutes)
    defaults.set(quietEndMinutes, forKey: Keys.quietEndMinutes)
    defaults.set(tiltDetectionEnabled, forKey: Keys.tiltDetectionEnabled)
    defaults.set(tiltThresholdDegrees, forKey: Keys.tiltThresholdDegrees)
    defaults.set(lowBatteryWarningEnabled, forKey: Keys.lowBatteryWarningEnabled)
    defaults.set(snoozePresetsMinutes, forKey: Keys.snoozePresetsMinutes)
    defaults.set(weeklyDigestEnabled, forKey: Keys.weeklyDigestEnabled)
    defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
    if let lastCalibrationDate {
      defaults.set(
        lastCalibrationDate.timeIntervalSinceReferenceDate, forKey: Keys.lastCalibrationDate)
    } else {
      defaults.removeObject(forKey: Keys.lastCalibrationDate)
    }
  }

  private static func positiveDouble(
    forKey key: String,
    in defaults: UserDefaults,
    defaultValue: Double
  ) -> Double {
    guard let value = defaults.object(forKey: key) as? Double,
      value.isFinite,
      value > 0
    else {
      return defaultValue
    }

    return value
  }

  private static func soundName(
    forKey key: String,
    in defaults: UserDefaults,
    defaultValue: String
  ) -> String {
    guard let value = defaults.string(forKey: key),
      availableSoundNames.contains(value)
    else {
      return defaultValue
    }

    return value
  }

  private static func bool(
    forKey key: String,
    in defaults: UserDefaults,
    defaultValue: Bool
  ) -> Bool {
    defaults.object(forKey: key) as? Bool ?? defaultValue
  }

  private static func date(forKey key: String, in defaults: UserDefaults) -> Date? {
    guard let raw = defaults.object(forKey: key) as? Double, raw.isFinite else {
      return nil
    }
    return Date(timeIntervalSinceReferenceDate: raw)
  }

  private static func int(forKey key: String, in defaults: UserDefaults, defaultValue: Int) -> Int {
    defaults.object(forKey: key) as? Int ?? defaultValue
  }
}
