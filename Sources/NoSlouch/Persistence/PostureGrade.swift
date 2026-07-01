import Foundation

/// A letter grade for a day's upright fraction (J1).
public enum PostureGrade: String {
  case a = "A"
  case b = "B"
  case c = "C"
  case d = "D"
  case f = "F"

  public static func forFraction(_ fraction: Double) -> PostureGrade {
    let percent = fraction * 100.0
    switch percent {
    case 90...: return .a
    case 80..<90: return .b
    case 70..<80: return .c
    case 60..<70: return .d
    default: return .f
    }
  }
}

public struct Achievement: Equatable, Identifiable {
  public let id: String
  public let title: String
  public let detail: String
}

/// Pure evaluator that derives unlocked achievements from history (J1). No stored
/// unlock state — achievements are recomputed from `DayPostureStat`s each time.
public enum Achievements {
  public static func unlocked(
    stats: [DayPostureStat],
    goalPercent: Double,
    calendar: Calendar
  ) -> [Achievement] {
    var result: [Achievement] = []

    if stats.contains(where: { $0.sessionCount > 0 }) {
      result.append(
        Achievement(id: "first-steps", title: "First Steps", detail: "Ran your first session"))
    }

    if stats.contains(where: { $0.goodSeconds >= 8 * 3_600 }) {
      result.append(
        Achievement(id: "marathon", title: "Marathon", detail: "8 upright hours in a day"))
    }

    if stats.contains(where: { ($0.goodSeconds + $0.badSeconds) > 0 && $0.slouchEvents == 0 }) {
      result.append(
        Achievement(id: "flawless", title: "Flawless", detail: "A day with zero slouches"))
    }

    let longest = StreakCalculator(goalPercent: goalPercent).longestStreak(
      stats: stats, calendar: calendar)
    if longest >= 7 {
      result.append(
        Achievement(id: "week-strong", title: "Week Strong", detail: "7-day goal streak"))
    }

    return result
  }
}
