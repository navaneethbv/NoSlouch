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

  func testRepeatedDaylightSavingHourKeepsDistinctBucketsAfterReload() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let formatter = ISO8601DateFormatter()
    let start = try XCTUnwrap(formatter.date(from: "2026-11-01T08:30:00Z"))
    let store = PostureHistoryStore(defaults: defaults, calendar: calendar)
    store.add(
      PostureSession(
        startedAt: start, endedAt: start.addingTimeInterval(7_200),
        badSeconds: 1_800, goodSeconds: 5_400, slouchEvents: 4))

    let reloaded = PostureHistoryStore(defaults: defaults, calendar: calendar)
    XCTAssertEqual(
      reloaded.hourlyStats.map(\.hour),
      [
        start.addingTimeInterval(-1_800), start.addingTimeInterval(1_800),
        start.addingTimeInterval(5_400),
      ])
    XCTAssertEqual(reloaded.hourlyStats.map(\.totalSeconds), [1_800, 3_600, 1_800])
    XCTAssertEqual(reloaded.stats.first?.goodSeconds, 5_400)
    XCTAssertEqual(reloaded.stats.first?.slouchEvents, 4)
  }

  func testClearHistoryRemovesDailyHourlyAndCorruptBackups() {
    let store = PostureHistoryStore(defaults: defaults)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    store.add(
      PostureSession(startedAt: start, endedAt: start.addingTimeInterval(60), badSeconds: 10))
    defaults.set(Data("backup".utf8), forKey: PostureHistoryStore.defaultsKey + ".corrupt")
    defaults.set(Data("backup".utf8), forKey: PostureHistoryStore.hourlyDefaultsKey + ".corrupt")
    defaults.set("keep", forKey: "unrelated.preference")

    store.removeAll()

    let reloaded = PostureHistoryStore(defaults: defaults)
    XCTAssertTrue(store.stats.isEmpty)
    XCTAssertTrue(store.hourlyStats.isEmpty)
    XCTAssertTrue(reloaded.stats.isEmpty)
    XCTAssertTrue(reloaded.hourlyStats.isEmpty)
    for key in [PostureHistoryStore.defaultsKey, PostureHistoryStore.hourlyDefaultsKey] {
      XCTAssertNil(defaults.object(forKey: key))
      XCTAssertNil(defaults.object(forKey: key + ".corrupt"))
    }
    XCTAssertEqual(defaults.string(forKey: "unrelated.preference"), "keep")
    XCTAssertEqual(store.exportCSV(), "Date,Sessions,Total Minutes,Upright %,Slouch Events")
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

  func testSessionSpanningHoursSplitsAcrossHourBuckets() throws {
    // NB-14: a 14:50–15:10 session books 10 minutes into each hour, not 20
    // minutes into 14:00.
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 14, minute: 50)))

    store.add(
      PostureSession(
        startedAt: start, endedAt: start.addingTimeInterval(1_200),
        badSeconds: 600, goodSeconds: 600, slouchEvents: 2))

    XCTAssertEqual(store.hourlyStats.count, 2)
    let hour14 = try XCTUnwrap(
      store.hourlyStats.first { calendar.component(.hour, from: $0.hour) == 14 })
    let hour15 = try XCTUnwrap(
      store.hourlyStats.first { calendar.component(.hour, from: $0.hour) == 15 })

    XCTAssertEqual(hour14.totalSeconds, 600, accuracy: 0.001)
    XCTAssertEqual(hour14.goodSeconds, 300, accuracy: 0.001)
    XCTAssertEqual(hour14.badSeconds, 300, accuracy: 0.001)
    XCTAssertEqual(hour14.sessionCount, 1)
    XCTAssertEqual(hour15.totalSeconds, 600, accuracy: 0.001)
    XCTAssertEqual(hour15.sessionCount, 0)
    XCTAssertEqual(hour14.slouchEvents + hour15.slouchEvents, 2)

    // Daily rollup still sees one session with the full totals.
    let daily = try XCTUnwrap(store.stats.first)
    XCTAssertEqual(daily.sessionCount, 1)
    XCTAssertEqual(daily.totalSeconds, 1_200, accuracy: 0.001)
  }

  func testSessionSpanningMidnightSplitsAcrossDays() throws {
    // NB-14: a 23:30–00:30 session must not book the after-midnight half into
    // yesterday's daily stats.
    let store = PostureHistoryStore(defaults: defaults)
    let calendar = Calendar(identifier: .gregorian)
    let start = try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 6, day: 29, hour: 23, minute: 30)))

    store.add(
      PostureSession(
        startedAt: start, endedAt: start.addingTimeInterval(3_600),
        badSeconds: 0, goodSeconds: 3_600, slouchEvents: 0))

    XCTAssertEqual(store.stats.count, 2)
    let day29 = try XCTUnwrap(store.stats.first)
    let day30 = try XCTUnwrap(store.stats.last)
    XCTAssertEqual(calendar.component(.day, from: day29.day), 29)
    XCTAssertEqual(calendar.component(.day, from: day30.day), 30)
    XCTAssertEqual(day29.goodSeconds, 1_800, accuracy: 0.001)
    XCTAssertEqual(day30.goodSeconds, 1_800, accuracy: 0.001)
  }

  func testCorruptHistoryBlobIsBackedUpBeforeReset() {
    // NB-29: an undecodable blob is preserved under "<key>.corrupt" instead of
    // being silently overwritten by the next save.
    defaults.set(Data("not json".utf8), forKey: PostureHistoryStore.hourlyDefaultsKey)

    let store = PostureHistoryStore(defaults: defaults)

    XCTAssertTrue(store.stats.isEmpty)
    XCTAssertEqual(
      defaults.data(forKey: PostureHistoryStore.hourlyDefaultsKey + ".corrupt"),
      Data("not json".utf8))
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
