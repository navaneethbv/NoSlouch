import XCTest

@testable import NoSlouch

final class PostureHistoryStoreTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "NoSlouch.PostureHistoryStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testExportCSVProducesHeaderAndRow() {
    let store = PostureHistoryStore(defaults: defaults)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.add(
      PostureSession(
        startedAt: start, endedAt: start.addingTimeInterval(600),
        badSeconds: 120, goodSeconds: 480, slouchEvents: 3))

    let lines = store.exportCSV().components(separatedBy: "\n")
    XCTAssertEqual(lines.first, "Date,Sessions,Total Minutes,Upright %,Slouch Events")
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[1].hasSuffix(",1,10,80,3"), lines[1])
  }

  func testHistoryAggregatesSessionsByDay() throws {
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))

    store.add(PostureSession(startedAt: day, endedAt: day.addingTimeInterval(60), badSeconds: 12))
    store.add(
      PostureSession(
        startedAt: day.addingTimeInterval(3_600), endedAt: day.addingTimeInterval(3_660),
        badSeconds: 20))

    XCTAssertEqual(
      store.stats,
      [
        DayPostureStat(day: day, sessionCount: 2, totalSeconds: 120, badSeconds: 32)
      ])
  }

  func testHistoryIgnoresShortSessions() throws {
    let store = PostureHistoryStore(defaults: defaults)
    let start = try XCTUnwrap(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 29)))

    store.add(
      PostureSession(startedAt: start, endedAt: start.addingTimeInterval(4.99), badSeconds: 4))

    XCTAssertTrue(store.stats.isEmpty)
  }

  func testHistoryEvictsEntriesOlderThanNinetyDays() throws {
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)))

    for offset in 0..<91 {
      let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstDay))
      store.add(PostureSession(startedAt: day, endedAt: day.addingTimeInterval(10), badSeconds: 1))
    }

    XCTAssertEqual(store.stats.count, 90)
    XCTAssertEqual(
      store.stats.first?.day, try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay)))
    XCTAssertEqual(
      store.stats.last?.day, try XCTUnwrap(calendar.date(byAdding: .day, value: 90, to: firstDay)))
  }

  func testHistoryFallsBackWhenStoredDataIsMalformed() {
    defaults.set(Data("not json".utf8), forKey: PostureHistoryStore.defaultsKey)

    let store = PostureHistoryStore(defaults: defaults)

    XCTAssertTrue(store.stats.isEmpty)
  }

  func testHistoryAggregatesGoodSecondsAndSlouchEvents() throws {
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))

    store.add(
      PostureSession(
        startedAt: day,
        endedAt: day.addingTimeInterval(60),
        badSeconds: 12,
        goodSeconds: 40,
        slouchEvents: 3))
    store.add(
      PostureSession(
        startedAt: day.addingTimeInterval(3_600),
        endedAt: day.addingTimeInterval(3_660),
        badSeconds: 20,
        goodSeconds: 1_000,
        slouchEvents: 2))

    let stat = try XCTUnwrap(store.stats.first)
    XCTAssertEqual(stat.goodSeconds, 100)
    XCTAssertEqual(stat.slouchEvents, 5)
  }

  func testUprightFractionIsGoodOverMeasured() {
    let stat = DayPostureStat(
      day: Date(),
      sessionCount: 1,
      totalSeconds: 100,
      badSeconds: 25,
      goodSeconds: 75)

    XCTAssertEqual(stat.uprightFraction, 0.75, accuracy: 0.0001)
  }

  func testUprightFractionIsZeroWhenNoMeasuredTime() {
    let stat = DayPostureStat(
      day: Date(),
      sessionCount: 1,
      totalSeconds: 0,
      badSeconds: 0,
      goodSeconds: 0)

    XCTAssertEqual(stat.uprightFraction, 0)
  }

  func testHistoryDecodesLegacyStatsWithoutNewFields() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))
    let legacy: [[String: Any]] = [
      [
        "day": day.timeIntervalSinceReferenceDate,
        "sessionCount": 2,
        "totalSeconds": 120.0,
        "badSeconds": 32.0,
      ]
    ]
    let data = try JSONSerialization.data(withJSONObject: legacy)
    defaults.set(data, forKey: PostureHistoryStore.defaultsKey)

    let store = PostureHistoryStore(defaults: defaults)

    let stat = try XCTUnwrap(store.stats.first)
    XCTAssertEqual(stat.sessionCount, 2)
    XCTAssertEqual(stat.totalSeconds, 120)
    XCTAssertEqual(stat.badSeconds, 32)
    XCTAssertEqual(stat.goodSeconds, 0)
    XCTAssertEqual(stat.slouchEvents, 0)
  }

  func testHistoryAggregatesSessionsByHour() throws {
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let baseTime = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 10)))

    // Session 1: 10:00 AM
    store.add(
      PostureSession(
        startedAt: baseTime, endedAt: baseTime.addingTimeInterval(60), badSeconds: 12,
        goodSeconds: 48, slouchEvents: 2))
    // Session 2: 10:30 AM (same hour)
    store.add(
      PostureSession(
        startedAt: baseTime.addingTimeInterval(1800), endedAt: baseTime.addingTimeInterval(1860),
        badSeconds: 20, goodSeconds: 40, slouchEvents: 3))
    // Session 3: 11:15 AM (different hour)
    store.add(
      PostureSession(
        startedAt: baseTime.addingTimeInterval(4500), endedAt: baseTime.addingTimeInterval(4560),
        badSeconds: 5, goodSeconds: 55, slouchEvents: 1))

    XCTAssertEqual(store.hourlyStats.count, 2)

    let hour10 = store.hourlyStats.first { calendar.component(.hour, from: $0.hour) == 10 }
    let hour11 = store.hourlyStats.first { calendar.component(.hour, from: $0.hour) == 11 }

    let unwrapped10 = try XCTUnwrap(hour10)
    XCTAssertEqual(unwrapped10.sessionCount, 2)
    XCTAssertEqual(unwrapped10.totalSeconds, 120)
    XCTAssertEqual(unwrapped10.badSeconds, 32)
    XCTAssertEqual(unwrapped10.goodSeconds, 88)
    XCTAssertEqual(unwrapped10.slouchEvents, 5)

    let unwrapped11 = try XCTUnwrap(hour11)
    XCTAssertEqual(unwrapped11.sessionCount, 1)
    XCTAssertEqual(unwrapped11.totalSeconds, 60)
    XCTAssertEqual(unwrapped11.badSeconds, 5)
    XCTAssertEqual(unwrapped11.goodSeconds, 55)
    XCTAssertEqual(unwrapped11.slouchEvents, 1)

    // Check that stats (daily summary) has aggregated both
    XCTAssertEqual(store.stats.count, 1)
    let dailyStat = try XCTUnwrap(store.stats.first)
    XCTAssertEqual(dailyStat.sessionCount, 3)
    XCTAssertEqual(dailyStat.totalSeconds, 180)
    XCTAssertEqual(dailyStat.badSeconds, 37)
    XCTAssertEqual(dailyStat.goodSeconds, 143)
    XCTAssertEqual(dailyStat.slouchEvents, 6)
  }

  func testHistoryMigratesLegacyDailyStats() throws {
    let calendar = Calendar(identifier: .gregorian)
    let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 29)))

    let legacyStats = [
      DayPostureStat(
        day: day, sessionCount: 2, totalSeconds: 120, badSeconds: 32, goodSeconds: 88,
        slouchEvents: 5)
    ]
    let data = try JSONEncoder().encode(legacyStats)
    defaults.set(data, forKey: PostureHistoryStore.defaultsKey)

    // Load store without hourlyStats key
    let store = PostureHistoryStore(defaults: defaults)

    // Check that daily stats migrated to hourlyStats at start of day
    XCTAssertEqual(store.hourlyStats.count, 1)
    let hourStat = try XCTUnwrap(store.hourlyStats.first)
    XCTAssertEqual(hourStat.hour, calendar.startOfDay(for: day))
    XCTAssertEqual(hourStat.sessionCount, 2)
    XCTAssertEqual(hourStat.totalSeconds, 120)
    XCTAssertEqual(hourStat.badSeconds, 32)
    XCTAssertEqual(hourStat.goodSeconds, 88)
    XCTAssertEqual(hourStat.slouchEvents, 5)

    // Daily stats should also be populated
    XCTAssertEqual(store.stats.count, 1)
    XCTAssertEqual(store.stats.first?.slouchEvents, 5)
  }
}
