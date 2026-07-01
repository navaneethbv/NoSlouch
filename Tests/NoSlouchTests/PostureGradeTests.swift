import XCTest

@testable import NoSlouch

final class PostureGradeTests: XCTestCase {
  func testGradeBoundaries() {
    XCTAssertEqual(PostureGrade.forFraction(0.95), .a)
    XCTAssertEqual(PostureGrade.forFraction(0.90), .a)
    XCTAssertEqual(PostureGrade.forFraction(0.85), .b)
    XCTAssertEqual(PostureGrade.forFraction(0.75), .c)
    XCTAssertEqual(PostureGrade.forFraction(0.65), .d)
    XCTAssertEqual(PostureGrade.forFraction(0.50), .f)
  }

  func testAchievementsUnlockFromHistory() {
    let calendar = Calendar(identifier: .gregorian)
    let base = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
    let stats = [
      DayPostureStat(
        day: base, sessionCount: 1, totalSeconds: 100, badSeconds: 0, goodSeconds: 100,
        slouchEvents: 0)
    ]

    let unlocked = Achievements.unlocked(stats: stats, goalPercent: 80, calendar: calendar)

    XCTAssertTrue(unlocked.contains { $0.id == "first-steps" })
    XCTAssertTrue(unlocked.contains { $0.id == "flawless" })
    XCTAssertFalse(unlocked.contains { $0.id == "marathon" })
  }

  func testEmptyHistoryUnlocksNothing() {
    let unlocked = Achievements.unlocked(
      stats: [], goalPercent: 80, calendar: Calendar(identifier: .gregorian))
    XCTAssertTrue(unlocked.isEmpty)
  }
}
