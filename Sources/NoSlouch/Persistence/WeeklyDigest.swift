import Foundation

/// Pure weekly-summary builder over daily history (J2). Deterministically testable.
public enum WeeklyDigest {
  public static func summary(stats: [DayPostureStat], asOf: Date, calendar: Calendar) -> String {
    let today = calendar.startOfDay(for: asOf)
    guard let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) else {
      return "No data this week yet."
    }

    let week = stats.filter { $0.day >= weekAgo && $0.day <= today }
    let good = week.reduce(0) { $0 + $1.goodSeconds }
    let bad = week.reduce(0) { $0 + $1.badSeconds }
    let measured = good + bad
    guard measured > 0 else {
      return "No data this week yet."
    }

    let percent = Int((good / measured * 100.0).rounded())
    let slouches = week.reduce(0) { $0 + $1.slouchEvents }
    var summary = "This week: \(percent)% upright · \(slouches) slouches"

    if let best = week.max(by: { $0.uprightFraction < $1.uprightFraction }) {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "EEE"
      summary += " · best day \(formatter.string(from: best.day))"
    }

    return summary
  }
}
