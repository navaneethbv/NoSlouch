import XCTest

@testable import NoSlouch

final class WeeklyDigestTests: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)
  private let base = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base))!
  }

  func testSummaryComputesWeekPercentAndSlouches() {
    let stats = [
      DayPostureStat(
        day: day(-2), sessionCount: 1, totalSeconds: 100, badSeconds: 20, goodSeconds: 80,
        slouchEvents: 2),
      DayPostureStat(
        day: day(-1), sessionCount: 1, totalSeconds: 100, badSeconds: 0, goodSeconds: 100,
        slouchEvents: 0),
    ]
    let summary = WeeklyDigest.summary(stats: stats, asOf: base, calendar: calendar)
    XCTAssertTrue(summary.contains("90% upright"), summary)
    XCTAssertTrue(summary.contains("2 slouches"), summary)
  }

  func testEmptyWeek() {
    XCTAssertEqual(
      WeeklyDigest.summary(stats: [], asOf: base, calendar: calendar), "No data this week yet.")
  }

  func testExcludesDaysOlderThanSevenDays() {
    let stats = [
      DayPostureStat(
        day: day(-10), sessionCount: 1, totalSeconds: 100, badSeconds: 0, goodSeconds: 100,
        slouchEvents: 0)
    ]
    XCTAssertEqual(
      WeeklyDigest.summary(stats: stats, asOf: base, calendar: calendar), "No data this week yet.")
  }
}
