import XCTest

@testable import NoSlouch

final class StreakCalculatorTests: XCTestCase {
  private let calendar = Calendar(identifier: .gregorian)
  private let base = Date(timeIntervalSince1970: 1_700_000_000)

  private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base))!
  }

  private func stat(_ offset: Int, met: Bool) -> DayPostureStat {
    DayPostureStat(
      day: day(offset),
      sessionCount: 1,
      totalSeconds: 100,
      badSeconds: met ? 10 : 50,
      goodSeconds: met ? 90 : 50,
      slouchEvents: 0
    )
  }

  func testCurrentStreakCountsConsecutiveMetDaysEndingToday() {
    let stats = [stat(-2, met: true), stat(-1, met: true), stat(0, met: true)]
    let calc = StreakCalculator(goalPercent: 80)
    XCTAssertEqual(calc.currentStreak(stats: stats, asOf: base, calendar: calendar), 3)
  }

  func testCurrentStreakBrokenByUnmetDay() {
    let stats = [stat(-2, met: true), stat(-1, met: false), stat(0, met: true)]
    let calc = StreakCalculator(goalPercent: 80)
    XCTAssertEqual(calc.currentStreak(stats: stats, asOf: base, calendar: calendar), 1)
  }

  func testCurrentStreakGraceWhenTodayHasNoData() {
    let stats = [stat(-2, met: true), stat(-1, met: true)]
    let calc = StreakCalculator(goalPercent: 80)
    XCTAssertEqual(calc.currentStreak(stats: stats, asOf: base, calendar: calendar), 2)
  }

  func testLongestStreakFindsBestRun() {
    let stats = [
      stat(-6, met: true), stat(-5, met: true), stat(-4, met: false),
      stat(-3, met: true), stat(-2, met: true), stat(-1, met: true),
    ]
    let calc = StreakCalculator(goalPercent: 80)
    XCTAssertEqual(calc.longestStreak(stats: stats, calendar: calendar), 3)
  }
}
