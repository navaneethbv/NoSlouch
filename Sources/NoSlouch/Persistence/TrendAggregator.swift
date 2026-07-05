import Foundation

/// The rollup granularities the history chart can display (C4).
public enum TrendGranularity: String, CaseIterable, Identifiable {
  case day = "Day"
  case week = "Week"
  case month = "Month"

  public var id: String { rawValue }
}

/// One aggregated bar of the history trend chart.
public struct TrendPoint: Equatable, Identifiable {
  public var id: Date { periodStart }
  public let periodStart: Date
  public let goodSeconds: TimeInterval
  public let badSeconds: TimeInterval
  public let slouchEvents: Int
  public let totalSeconds: TimeInterval

  public init(
    periodStart: Date,
    goodSeconds: TimeInterval,
    badSeconds: TimeInterval,
    slouchEvents: Int,
    totalSeconds: TimeInterval
  ) {
    self.periodStart = periodStart
    self.goodSeconds = goodSeconds
    self.badSeconds = badSeconds
    self.slouchEvents = slouchEvents
    self.totalSeconds = totalSeconds
  }

  public var uprightPercent: Double {
    let measured = goodSeconds + badSeconds
    guard measured > 0 else {
      return 0
    }
    return goodSeconds / measured * 100.0
  }
}

/// Pure day/week/month rollups over daily history (C4). No imports beyond
/// Foundation — same unit-test tier as `SlouchEngine`.
public struct TrendAggregator {
  public static func points(
    stats: [DayPostureStat],
    granularity: TrendGranularity,
    calendar: Calendar
  ) -> [TrendPoint] {
    var buckets: [Date: TrendPoint] = [:]
    for stat in stats {
      let start = periodStart(for: stat.day, granularity: granularity, calendar: calendar)
      if let existing = buckets[start] {
        buckets[start] = TrendPoint(
          periodStart: start,
          goodSeconds: existing.goodSeconds + stat.goodSeconds,
          badSeconds: existing.badSeconds + stat.badSeconds,
          slouchEvents: existing.slouchEvents + stat.slouchEvents,
          totalSeconds: existing.totalSeconds + stat.totalSeconds
        )
      } else {
        buckets[start] = TrendPoint(
          periodStart: start,
          goodSeconds: stat.goodSeconds,
          badSeconds: stat.badSeconds,
          slouchEvents: stat.slouchEvents,
          totalSeconds: stat.totalSeconds
        )
      }
    }
    return buckets.values.sorted { $0.periodStart < $1.periodStart }
  }

  private static func periodStart(
    for day: Date,
    granularity: TrendGranularity,
    calendar: Calendar
  ) -> Date {
    switch granularity {
    case .day:
      return calendar.startOfDay(for: day)
    case .week:
      return calendar.dateInterval(of: .weekOfYear, for: day)?.start
        ?? calendar.startOfDay(for: day)
    case .month:
      return calendar.dateInterval(of: .month, for: day)?.start
        ?? calendar.startOfDay(for: day)
    }
  }
}
