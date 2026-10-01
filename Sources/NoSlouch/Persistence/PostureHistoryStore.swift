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
  public static let snapshotKey = defaultsKey + ".snapshot.v2"
  public static var defaultStorageURL: URL {
    URL.applicationSupportDirectory.appendingPathComponent("NoSlouch/history-v2.json")
  }

  public static let hourlyDefaultsKey = "posture.history.hourlyStats"

  public private(set) var stats: [DayPostureStat]
  public private(set) var hourlyStats: [HourPostureStat]

  private let defaults: UserDefaults
  private let key: String
  private let hourlyKey: String
  private let calendar: Calendar
  private let now: () -> Date
  private let storageURL: URL?
  private var pending: [HourPostureStat] = []
  public private(set) var lastError: String?
  public private(set) var recoveredSession = false

  private struct Snapshot: Codable {
    var version = 2
    var hours: [HourPostureStat]
    var pending: [HourPostureStat]
  }

  public init(
    defaults: UserDefaults = .standard,
    key: String = PostureHistoryStore.defaultsKey,
    hourlyKey: String = PostureHistoryStore.hourlyDefaultsKey,
    calendar: Calendar = .current,
    now: @escaping () -> Date = Date.init,
    storageURL: URL? = nil
  ) {
    self.defaults = defaults
    self.key = key
    self.hourlyKey = hourlyKey
    self.calendar = calendar
    self.now = now
    self.storageURL = storageURL

    // A corrupt blob is moved to a "<key>.corrupt" backup instead of being
    // silently overwritten by the next save ; up to 90 days of history stays
    // recoverable (NB-29).
    let hourlyData = defaults.data(forKey: hourlyKey)
    let dailyData = defaults.data(forKey: key)
    let decodedHourly = hourlyData.flatMap {
      try? JSONDecoder().decode([HourPostureStat].self, from: $0)
    }
    let decodedDaily = dailyData.flatMap {
      try? JSONDecoder().decode([DayPostureStat].self, from: $0)
    }
    if let hourlyData, decodedHourly == nil {
      defaults.set(hourlyData, forKey: hourlyKey + ".corrupt")
    }
    if let dailyData, decodedDaily == nil {
      defaults.set(dailyData, forKey: key + ".corrupt")
    }

    if let decodedHourly {
      self.hourlyStats = decodedHourly.sorted { $0.hour < $1.hour }
    } else if let decodedDaily {
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
    do {
      let data: Data?
      if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
        data = try Data(contentsOf: storageURL)
      } else {
        data = defaults.data(forKey: key + ".snapshot.v2")
      }
      if let data {
        do {
          let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
          guard snapshot.version == 2 else {
            throw CocoaError(.fileReadCorruptFile)
          }
          self.hourlyStats = Self.combined(snapshot.hours, snapshot.pending)
          recoveredSession = !snapshot.pending.isEmpty
        } catch {
          if let storageURL {
            try data.write(to: storageURL.appendingPathExtension("corrupt"), options: .atomic)
          } else {
            defaults.set(data, forKey: key + ".snapshot.v2.corrupt")
          }
          lastError =
            "Could not read history. A recovery backup was preserved: \(error.localizedDescription)"
        }
      }
    } catch {
      lastError = "Could not load history: \(error.localizedDescription)"
    }
    evictOldestHourlyEntries()
    updateDailyStats()
    if lastError == nil
      && (!hourlyStats.isEmpty || dailyData != nil || hourlyData != nil
        || defaults.data(forKey: key + ".snapshot.v2") != nil
        || (storageURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false))
    {
      save()
    }
  }

  public func add(_ session: PostureSession) {
    guard session.duration >= 5.0 else {
      return
    }

    let duration = session.duration
    let badSeconds = min(max(0, session.badSeconds), duration)
    let goodSeconds = min(max(0, session.goodSeconds), duration)
    let slouchEvents = max(0, session.slouchEvents)

    // Split the session across the hours it actually spanned, pro rata by
    // overlap (NB-14): a 9:50–13:00 session lands in the 9–12 buckets instead of
    // booking 190 minutes into 9:00, and a session spanning midnight books each
    // day's share to the correct day. Seconds split fractionally; slouch events
    // split by rounded share with the remainder on the final slice so the total
    // is preserved. The session itself counts once, in its starting hour.
    var remainingEvents = slouchEvents
    var isFirstSlice = true
    var cursor = session.startedAt
    let end = session.startedAt.addingTimeInterval(duration)

    while cursor < end {
      let hour = hourBucket(for: cursor)
      let sliceEnd: Date
      if let nextHour = calendar.date(byAdding: .hour, value: 1, to: hour), nextHour > cursor {
        sliceEnd = min(end, nextHour)
      } else {
        sliceEnd = end
      }
      let sliceSeconds = sliceEnd.timeIntervalSince(cursor)
      let fraction = sliceSeconds / duration
      let sliceEvents =
        sliceEnd >= end
        ? remainingEvents
        : min(remainingEvents, Int((Double(slouchEvents) * fraction).rounded()))
      remainingEvents -= sliceEvents

      merge(
        hour: hour,
        sessionCount: isFirstSlice ? 1 : 0,
        totalSeconds: sliceSeconds,
        badSeconds: badSeconds * fraction,
        goodSeconds: goodSeconds * fraction,
        slouchEvents: sliceEvents
      )
      isFirstSlice = false
      cursor = sliceEnd
    }

    hourlyStats.sort { $0.hour < $1.hour }
    evictOldestHourlyEntries()
    updateDailyStats()
    save()
  }

  public func removeAll() {
    hourlyStats = []
    stats = []
    pending = []
    recoveredSession = false
    for storageKey in [key, hourlyKey, key + ".snapshot.v2"] {
      defaults.removeObject(forKey: storageKey)
      defaults.removeObject(forKey: storageKey + ".corrupt")
    }
    do {
      if let storageURL {
        // Replace the canonical file first so a failed backup deletion cannot restore history.
        let data = try JSONEncoder().encode(Snapshot(hours: [], pending: []))
        try FileManager.default.createDirectory(
          at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        let backup = storageURL.appendingPathExtension("corrupt")
        if FileManager.default.fileExists(atPath: backup.path) {
          try FileManager.default.removeItem(at: backup)
        }
      }
      lastError = nil
    } catch {
      lastError = "Could not completely clear saved history: \(error.localizedDescription)"
    }
  }

  private func hourBucket(for date: Date) -> Date {
    // Reconstructing wall-clock components loses the offset of a repeated DST hour.
    calendar.dateInterval(of: .hour, for: date)?.start
      ?? calendar.startOfDay(for: date)
  }

  private func merge(
    hour: Date,
    sessionCount: Int,
    totalSeconds: TimeInterval,
    badSeconds: TimeInterval,
    goodSeconds: TimeInterval,
    slouchEvents: Int
  ) {
    if let index = hourlyStats.firstIndex(where: { $0.hour == hour }) {
      hourlyStats[index].sessionCount += sessionCount
      hourlyStats[index].totalSeconds += totalSeconds
      hourlyStats[index].badSeconds += badSeconds
      hourlyStats[index].goodSeconds += goodSeconds
      hourlyStats[index].slouchEvents += slouchEvents
    } else {
      hourlyStats.append(
        HourPostureStat(
          hour: hour,
          sessionCount: sessionCount,
          totalSeconds: totalSeconds,
          badSeconds: badSeconds,
          goodSeconds: goodSeconds,
          slouchEvents: slouchEvents
        ))
    }
  }

  private func evictOldestHourlyEntries() {
    hourlyStats = retained(hourlyStats)
  }

  private func retained(_ hours: [HourPostureStat]) -> [HourPostureStat] {
    guard
      let cutoff = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now()))
    else { return hours }
    return hours.filter { $0.hour >= cutoff }
  }

  func retrySave() { save() }

  func pruneExpiredHistory() {
    let kept = retained(hourlyStats)
    let keptPending = retained(pending)
    guard kept != hourlyStats || keptPending != pending else { return }
    hourlyStats = kept
    pending = keptPending
    updateDailyStats()
    save()
  }

  func preview(_ active: [HourPostureStat]) -> (days: [DayPostureStat], hours: [HourPostureStat]) {
    let hours = retained(Self.combined(hourlyStats, active))
    return (Self.daily(hours, calendar: calendar), hours)
  }

  func checkpoint(_ active: [HourPostureStat]) {
    pending = retained(active)
    evictOldestHourlyEntries()
    updateDailyStats()
    save()
  }

  func commit(_ active: [HourPostureStat]) {
    hourlyStats = retained(Self.combined(hourlyStats, active))
    pending = []
    updateDailyStats()
    save()
  }

  private static func combined(_ stored: [HourPostureStat], _ active: [HourPostureStat])
    -> [HourPostureStat]
  {
    var map: [Date: HourPostureStat] = [:]
    for entry in stored + active {
      if var previous = map[entry.hour] {
        previous.sessionCount += entry.sessionCount
        previous.totalSeconds += entry.totalSeconds
        previous.goodSeconds += entry.goodSeconds
        previous.badSeconds += entry.badSeconds
        previous.slouchEvents += entry.slouchEvents
        map[entry.hour] = previous
      } else {
        map[entry.hour] = entry
      }
    }
    return map.values.sorted { $0.hour < $1.hour }
  }

  private func updateDailyStats() {
    stats = Self.daily(hourlyStats, calendar: calendar)
  }

  private static func daily(_ hours: [HourPostureStat], calendar: Calendar) -> [DayPostureStat] {
    var dailyMap: [Date: DayPostureStat] = [:]
    for hourStat in hours {
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
    return dailyMap.values.sorted { $0.day < $1.day }
  }

  /// A CSV of the daily history (oldest → newest), one row per day (C3).
  public func exportCSV(stats exportedStats: [DayPostureStat]? = nil) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"

    var lines = ["Date,Sessions,Total Minutes,Upright %,Slouch Events"]
    for stat in exportedStats ?? stats {
      let date = formatter.string(from: stat.day)
      let minutes = Int((max(0, stat.totalSeconds) / 60).rounded())
      let percent = Int((stat.uprightFraction * 100).rounded())
      lines.append("\(date),\(stat.sessionCount),\(minutes),\(percent),\(stat.slouchEvents)")
    }
    return lines.joined(separator: "\n")
  }

  private func save() {
    do {
      let data = try JSONEncoder().encode(Snapshot(hours: hourlyStats, pending: pending))
      if let storageURL {
        try FileManager.default.createDirectory(
          at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: storageURL, options: .atomic)
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
      } else {
        defaults.set(data, forKey: key + ".snapshot.v2")
      }
      // The canonical snapshot controls recovery; compatibility mirrors let an
      // older version read the measured totals if the user rolls back.
      let visible = retained(Self.combined(hourlyStats, pending))
      defaults.set(try JSONEncoder().encode(visible), forKey: hourlyKey)
      defaults.set(try JSONEncoder().encode(Self.daily(visible, calendar: calendar)), forKey: key)
      lastError = nil
    } catch {
      lastError = "Could not save history: \(error.localizedDescription)"
    }
  }
}
