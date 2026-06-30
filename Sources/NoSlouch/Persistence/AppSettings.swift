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

  public init(
    thresholdDegrees: Double = 12.0,
    holdSeconds: TimeInterval = 3.0,
    recoverSeconds: TimeInterval = 1.5,
    alertCooldownSeconds: TimeInterval = 60.0,
    soundEnabled: Bool = true,
    speechEnabled: Bool = false,
    invertedPitch: Bool = false,
    soundName: String = "Glass",
    calibratedBaselinePitch: Double? = nil
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
      calibratedBaselinePitch: validatedPitch
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
}
