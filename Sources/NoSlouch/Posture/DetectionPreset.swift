import Foundation

/// A named bundle of the three analyzer-affecting detection knobs, so users can
/// pick a sensitivity without tuning threshold/hold/recover individually (A3).
public enum DetectionPreset: String, CaseIterable, Identifiable {
  case gentle
  case standard
  case strict

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .gentle: return "Gentle"
    case .standard: return "Standard"
    case .strict: return "Strict"
    }
  }

  public var thresholdDegrees: Double {
    switch self {
    case .gentle: return 18.0
    case .standard: return 12.0
    case .strict: return 8.0
    }
  }

  public var holdSeconds: TimeInterval {
    switch self {
    case .gentle: return 5.0
    case .standard: return 3.0
    case .strict: return 2.0
    }
  }

  public var recoverSeconds: TimeInterval {
    switch self {
    case .gentle: return 2.5
    case .standard: return 1.5
    case .strict: return 1.0
    }
  }

  /// The preset whose values exactly match the given settings, or `nil` ("Custom")
  /// when the user has hand-tuned values that don't match any preset.
  public static func matching(_ settings: AppSettings) -> DetectionPreset? {
    allCases.first {
      $0.thresholdDegrees == settings.thresholdDegrees
        && $0.holdSeconds == settings.holdSeconds
        && $0.recoverSeconds == settings.recoverSeconds
    }
  }
}
