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
}
