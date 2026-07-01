import Foundation

/// The recurring, monitored-time-based reminders NoSlouch can fire (G2). Break,
/// eye-rest (20-20-20), hydration, and movement all share one scheduling engine
/// in `PostureViewModel`; each carries its own notification copy.
public enum ReminderKind: String, CaseIterable, Identifiable {
  case breakTime
  case eyeRest
  case hydration
  case movement

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .breakTime: return "Break Reminder"
    case .eyeRest: return "Eye Rest"
    case .hydration: return "Hydration"
    case .movement: return "Move"
    }
  }

  public var body: String {
    switch self {
    case .breakTime: return "Time to take a break and stretch!"
    case .eyeRest: return "Look ~20 feet away for 20 seconds (20-20-20)."
    case .hydration: return "Time for a sip of water 💧"
    case .movement: return "You've been still a while — stand up and move."
    }
  }
}
