import XCTest

@testable import NoSlouch

final class TrendAggregatorTests: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)

  private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  private func stat(_ date: Date, good: TimeInterval, bad: TimeInterval, slouches: Int = 0)
    -> DayPostureStat
  {
    DayPostureStat(
      day: date,
      sessionCount: 1,
      totalSeconds: good + bad,
      badSeconds: bad,
      goodSeconds: good,
      slouchEvents: slouches
    )
  }

  func testDayGranularityPassesDaysThrough() {
    let stats = [
      stat(day(2026, 6, 29), good: 90, bad: 10),
      stat(day(2026, 6, 30), good: 50, bad: 50),
    ]
    let points = TrendAggregator.points(stats: stats, granularity: .day, calendar: calendar)

    XCTAssertEqual(points.count, 2)
    XCTAssertEqual(points[0].uprightPercent, 90, accuracy: 0.001)
    XCTAssertEqual(points[1].uprightPercent, 50, accuracy: 0.001)
  }

  func testWeekGranularityBucketsByWeek() {
    // Mon Jun 29 and Tue Jun 30 share a week; Mon Jul 6 starts the next.
    let stats = [
      stat(day(2026, 6, 29), good: 100, bad: 0, slouches: 1),
      stat(day(2026, 6, 30), good: 0, bad: 100, slouches: 2),
      stat(day(2026, 7, 6), good: 80, bad: 20, slouches: 3),
    ]
    let points = TrendAggregator.points(stats: stats, granularity: .week, calendar: calendar)

    XCTAssertEqual(points.count, 2)
    XCTAssertEqual(points[0].uprightPercent, 50, accuracy: 0.001)
    XCTAssertEqual(points[0].slouchEvents, 3)
    XCTAssertEqual(points[0].totalSeconds, 200, accuracy: 0.001)
    XCTAssertEqual(points[1].uprightPercent, 80, accuracy: 0.001)
  }

  func testMonthGranularityBucketsByMonth() {
    let stats = [
      stat(day(2026, 6, 1), good: 60, bad: 40),
      stat(day(2026, 6, 30), good: 40, bad: 60),
      stat(day(2026, 7, 1), good: 100, bad: 0),
    ]
    let points = TrendAggregator.points(stats: stats, granularity: .month, calendar: calendar)

    XCTAssertEqual(points.count, 2)
    XCTAssertEqual(points[0].periodStart, day(2026, 6, 1))
    XCTAssertEqual(points[0].uprightPercent, 50, accuracy: 0.001)
    XCTAssertEqual(points[1].periodStart, day(2026, 7, 1))
    XCTAssertEqual(points[1].uprightPercent, 100, accuracy: 0.001)
  }

  func testEmptyStatsYieldNoPoints() {
    XCTAssertTrue(
      TrendAggregator.points(stats: [], granularity: .week, calendar: calendar).isEmpty)
  }

  func testZeroMeasuredTimeYieldsZeroPercent() {
    let points = TrendAggregator.points(
      stats: [stat(day(2026, 6, 29), good: 0, bad: 0)], granularity: .day, calendar: calendar)
    XCTAssertEqual(points.first?.uprightPercent, 0)
  }
}
