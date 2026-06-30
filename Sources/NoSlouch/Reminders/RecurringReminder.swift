import Foundation

/// Identifies one category of recurring wellness reminder.
/// Each kind carries its own notification copy and persistence key prefix.
enum ReminderKind: String, CaseIterable {
  case breakStretch
  case eyeRest
  case hydration

  var identifier: String {
    switch self {
    case .breakStretch: return "break"
    case .eyeRest: return "eyerest"
    case .hydration: return "hydration"
    }
  }

  var notificationContent: (title: String, body: String) {
    switch self {
    case .breakStretch:
      return ("Break Reminder", "Time to take a break and stretch! 🧘")
    case .eyeRest:
      return ("Eye Rest Reminder", "Look 20 ft away for 20 seconds to rest your eyes. 👁️")
    case .hydration:
      return ("Hydration Reminder", "Time for a sip of water! 💧")
    }
  }
}

/// Tracks state for a single recurring reminder within the reminder engine.
struct RecurringReminder {
  let kind: ReminderKind
  /// How many monitored-seconds must elapse before this reminder fires.
  var intervalSeconds: TimeInterval
  /// Whether this reminder is currently active.
  var enabled: Bool
  /// The value of (goodSeconds + badSeconds) at the last time this reminder fired.
  var lastFiredMonitoredSeconds: TimeInterval
}
