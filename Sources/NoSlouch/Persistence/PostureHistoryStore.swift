import Foundation

public struct DayPostureStat: Codable, Equatable, Identifiable {
  public var id: Date { day }
  public var day: Date
  public var sessionCount: Int
  public var totalSeconds: TimeInterval
  public var badSeconds: TimeInterval
  public var goodSeconds: TimeInterval
  public var slouchEvents: Int

  /// Fraction of measured time spent upright (0...1). Returns 0 when neither
  /// good nor bad seconds were recorded.
  public var uprightFraction: Double {
    let measured = goodSeconds + badSeconds
    guard measured > 0 else {
      return 0
    }

    return goodSeconds / measured
  }

  public init(
    day: Date,
    sessionCount: Int,
    totalSeconds: TimeInterval,
    badSeconds: TimeInterval,
    goodSeconds: TimeInterval = 0,
    slouchEvents: Int = 0
  ) {
    self.day = day
    self.sessionCount = sessionCount
    self.totalSeconds = totalSeconds
    self.badSeconds = badSeconds
    self.goodSeconds = goodSeconds
    self.slouchEvents = slouchEvents
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    day = try container.decode(Date.self, forKey: .day)
    sessionCount = try container.decode(Int.self, forKey: .sessionCount)
    totalSeconds = try container.decode(TimeInterval.self, forKey: .totalSeconds)
    badSeconds = try container.decode(TimeInterval.self, forKey: .badSeconds)
    goodSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .goodSeconds) ?? 0
    slouchEvents = try container.decodeIfPresent(Int.self, forKey: .slouchEvents) ?? 0
  }
}

public struct HourPostureStat: Codable, Equatable, Identifiable {
  public var id: Date { hour }
  public var hour: Date
  public var sessionCount: Int
  public var totalSeconds: TimeInterval
  public var badSeconds: TimeInterval
  public var goodSeconds: TimeInterval
  public var slouchEvents: Int

  public init(
    hour: Date,
    sessionCount: Int,
    totalSeconds: TimeInterval,
    badSeconds: TimeInterval,
    goodSeconds: TimeInterval = 0,
    slouchEvents: Int = 0
  ) {
    self.hour = hour
    self.sessionCount = sessionCount
    self.totalSeconds = totalSeconds
    self.badSeconds = badSeconds
    self.goodSeconds = goodSeconds
    self.slouchEvents = slouchEvents
  }
}

public final class PostureHistoryStore {
  public static let defaultsKey = "posture.history.dailyStats"
  public static let hourlyDefaultsKey = "posture.history.hourlyStats"

  public private(set) var stats: [DayPostureStat]
  public private(set) var hourlyStats: [HourPostureStat]

  private let defaults: UserDefaults
  private let key: String
  private let hourlyKey: String
  private let calendar: Calendar

  public init(
    defaults: UserDefaults = .standard,
    key: String = PostureHistoryStore.defaultsKey,
    hourlyKey: String = PostureHistoryStore.hourlyDefaultsKey,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) {
    self.defaults = defaults
    self.key = key
    self.hourlyKey = hourlyKey
    self.calendar = calendar

    if let hourlyData = defaults.data(forKey: hourlyKey),
      let decodedHourly = try? JSONDecoder().decode([HourPostureStat].self, from: hourlyData)
    {
      self.hourlyStats = decodedHourly.sorted { $0.hour < $1.hour }
    } else if let dailyData = defaults.data(forKey: key),
      let decodedDaily = try? JSONDecoder().decode([DayPostureStat].self, from: dailyData)
    {
      let sortedDaily = decodedDaily.sorted { $0.day < $1.day }
      self.hourlyStats = sortedDaily.map { dailyStat in
        HourPostureStat(
          hour: calendar.startOfDay(for: dailyStat.day),
          sessionCount: dailyStat.sessionCount,
          totalSeconds: dailyStat.totalSeconds,
          badSeconds: dailyStat.badSeconds,
          goodSeconds: dailyStat.goodSeconds,
          slouchEvents: dailyStat.slouchEvents
        )
      }
    } else {
      self.hourlyStats = []
    }

    self.stats = []
    evictOldestHourlyEntries()
    updateDailyStats()
  }

  public func add(_ session: PostureSession) {
    guard session.duration >= 5.0 else {
      return
    }

    // Truncate to the top of the hour. Guarded (no force-unwrap) per STANDARDS §2
    // (NB-8); falls back to the start of day if the calendar can't reconstruct it.
    let hour =
      calendar.date(
        from: calendar.dateComponents([.year, .month, .day, .hour], from: session.startedAt))
      ?? calendar.startOfDay(for: session.startedAt)
    let duration = max(0, session.duration)
    let badSeconds = min(max(0, session.badSeconds), duration)
    let goodSeconds = min(max(0, session.goodSeconds), duration)
    let slouchEvents = max(0, session.slouchEvents)

    if let index = hourlyStats.firstIndex(where: { $0.hour == hour }) {
      hourlyStats[index].sessionCount += 1
      hourlyStats[index].totalSeconds += duration
      hourlyStats[index].badSeconds += badSeconds
      hourlyStats[index].goodSeconds += goodSeconds
      hourlyStats[index].slouchEvents += slouchEvents
    } else {
      hourlyStats.append(
        HourPostureStat(
          hour: hour,
          sessionCount: 1,
          totalSeconds: duration,
          badSeconds: badSeconds,
          goodSeconds: goodSeconds,
          slouchEvents: slouchEvents
        ))
    }

    hourlyStats.sort { $0.hour < $1.hour }
    evictOldestHourlyEntries()
    updateDailyStats()
    save()
  }

  private func evictOldestHourlyEntries() {
    let days = Array(Set(hourlyStats.map { calendar.startOfDay(for: $0.hour) })).sorted()
    guard days.count > 90 else {
      return
    }

    let cutoff = days[days.count - 90]
    hourlyStats.removeAll { $0.hour < cutoff }
  }

  private func updateDailyStats() {
    var dailyMap: [Date: DayPostureStat] = [:]
    for hourStat in hourlyStats {
      let day = calendar.startOfDay(for: hourStat.hour)
      if var existing = dailyMap[day] {
        existing.sessionCount += hourStat.sessionCount
        existing.totalSeconds += hourStat.totalSeconds
        existing.badSeconds += hourStat.badSeconds
        existing.goodSeconds += hourStat.goodSeconds
        existing.slouchEvents += hourStat.slouchEvents
        dailyMap[day] = existing
      } else {
        dailyMap[day] = DayPostureStat(
          day: day,
          sessionCount: hourStat.sessionCount,
          totalSeconds: hourStat.totalSeconds,
          badSeconds: hourStat.badSeconds,
          goodSeconds: hourStat.goodSeconds,
          slouchEvents: hourStat.slouchEvents
        )
      }
    }
    stats = dailyMap.values.sorted { $0.day < $1.day }
  }

  /// A CSV of the daily history (oldest → newest), one row per day (C3).
  public func exportCSV() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"

    var lines = ["Date,Sessions,Total Minutes,Upright %,Slouch Events"]
    for stat in stats {
      let date = formatter.string(from: stat.day)
      let minutes = Int((max(0, stat.totalSeconds) / 60).rounded())
      let percent = Int((stat.uprightFraction * 100).rounded())
      lines.append("\(date),\(stat.sessionCount),\(minutes),\(percent),\(stat.slouchEvents)")
    }
    return lines.joined(separator: "\n")
  }

  private func save() {
    guard let hourlyData = try? JSONEncoder().encode(hourlyStats) else {
      return
    }
    defaults.set(hourlyData, forKey: hourlyKey)

    guard let dailyData = try? JSONEncoder().encode(stats) else {
      return
    }
    defaults.set(dailyData, forKey: key)
  }
}
