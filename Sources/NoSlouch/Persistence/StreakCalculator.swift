import Foundation

/// Pure calculator for daily-goal streaks over `DayPostureStat` history (C2).
/// No imports beyond Foundation, so it is deterministically unit-testable.
public struct StreakCalculator {
  public let goalPercent: Double

  public init(goalPercent: Double) {
    self.goalPercent = goalPercent
  }

  public func isMet(_ stat: DayPostureStat) -> Bool {
    stat.uprightFraction * 100.0 >= goalPercent
  }

  /// Consecutive calendar days meeting the goal, ending at the most recent day.
  /// If `asOf`'s day has no data yet, the count starts from the previous day so a
  /// not-yet-finished today doesn't zero out an existing streak.
  public func currentStreak(stats: [DayPostureStat], asOf: Date, calendar: Calendar) -> Int {
    let metDays = Set(stats.filter(isMet).map { calendar.startOfDay(for: $0.day) })
    let allDays = Set(stats.map { calendar.startOfDay(for: $0.day) })

    var day = calendar.startOfDay(for: asOf)
    if !allDays.contains(day) {
      guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
        return 0
      }
      day = previous
    }

    var streak = 0
    while metDays.contains(day) {
      streak += 1
      guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else {
        break
      }
      day = previous
    }
    return streak
  }

  /// The longest run of consecutive goal-meeting days anywhere in the history.
  public func longestStreak(stats: [DayPostureStat], calendar: Calendar) -> Int {
    let metDays = Array(Set(stats.filter(isMet).map { calendar.startOfDay(for: $0.day) })).sorted()

    var longest = 0
    var run = 0
    var previous: Date?
    for day in metDays {
      if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
        run += 1
      } else {
        run = 1
      }
      longest = max(longest, run)
      previous = day
    }
    return longest
  }
}
