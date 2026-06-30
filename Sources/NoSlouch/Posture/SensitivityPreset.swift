import Foundation

/// Named sensitivity presets for posture detection.
/// Each preset adjusts thresholdDegrees, holdSeconds, and recoverSeconds.
public enum SensitivityPreset: String, CaseIterable {
  case gentle = "Gentle"
  case standard = "Standard"
  case strict = "Strict"

  public var thresholdDegrees: Double {
    switch self {
    case .gentle: return 18.0
    case .standard: return 12.0
    case .strict: return 7.0
    }
  }

  public var holdSeconds: TimeInterval {
    switch self {
    case .gentle: return 5.0
    case .standard: return 3.0
    case .strict: return 1.5
    }
  }

  public var recoverSeconds: TimeInterval {
    switch self {
    case .gentle: return 2.0
    case .standard: return 1.5
    case .strict: return 1.0
    }
  }
}
