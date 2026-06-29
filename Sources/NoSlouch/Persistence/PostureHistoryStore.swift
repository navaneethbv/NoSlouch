import Foundation

public struct DayPostureStat: Codable, Equatable, Identifiable {
  public var id: Date { day }
  public var day: Date
  public var sessionCount: Int
  public var totalSeconds: TimeInterval
  public var badSeconds: TimeInterval
  public var goodSeconds: TimeInterval
  public var slouchEvents: Int

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

public final class PostureHistoryStore {
  public static let defaultsKey = "posture.history.dailyStats"

  public private(set) var stats: [DayPostureStat]

  private let defaults: UserDefaults
  private let key: String
  private let calendar: Calendar

  public init(
    defaults: UserDefaults = .standard,
    key: String = PostureHistoryStore.defaultsKey,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) {
    self.defaults = defaults
    self.key = key
    self.calendar = calendar

    guard let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode([DayPostureStat].self, from: data)
    else {
      stats = []
      return
    }

    stats = decoded.sorted { $0.day < $1.day }
    evictOldestEntries()
  }

  public func add(_ session: PostureSession) {
    guard session.duration >= 5.0 else {
      return
    }

    let day = calendar.startOfDay(for: session.startedAt)
    let duration = max(0, session.duration)
    let badSeconds = min(max(0, session.badSeconds), duration)
    let goodSeconds = min(max(0, session.goodSeconds), duration)
    let slouchEvents = max(0, session.slouchEvents)

    if let index = stats.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: day) }) {
      stats[index].sessionCount += 1
      stats[index].totalSeconds += duration
      stats[index].badSeconds += badSeconds
      stats[index].goodSeconds += goodSeconds
      stats[index].slouchEvents += slouchEvents
    } else {
      stats.append(
        DayPostureStat(
          day: day,
          sessionCount: 1,
          totalSeconds: duration,
          badSeconds: badSeconds,
          goodSeconds: goodSeconds,
          slouchEvents: slouchEvents
        ))
    }

    stats.sort { $0.day < $1.day }
    evictOldestEntries()
    save()
  }

  private func evictOldestEntries() {
    guard stats.count > 90 else {
      return
    }

    stats = Array(stats.suffix(90))
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(stats) else {
      return
    }

    defaults.set(data, forKey: key)
  }
}
