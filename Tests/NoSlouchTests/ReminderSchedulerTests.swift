import XCTest

@testable import NoSlouch

final class ReminderSchedulerTests: XCTestCase {
  func testSuppressedRemindersRemainDueAndDoNotStack() {
    var scheduler = ReminderScheduler()
    let configs: [(kind: ReminderKind, enabled: Bool, interval: TimeInterval)] = [
      (.breakTime, true, 600), (.eyeRest, true, 600),
    ]
    XCTAssertEqual(scheduler.due(configs: configs, monitoredSeconds: 900, suppressed: true), [])
    XCTAssertEqual(
      scheduler.due(configs: configs, monitoredSeconds: 901, suppressed: false), [.breakTime])
    XCTAssertEqual(scheduler.due(configs: configs, monitoredSeconds: 902, suppressed: false), [])
    XCTAssertEqual(
      scheduler.due(configs: configs, monitoredSeconds: 1_021, suppressed: false), [.eyeRest])
  }

  func testChangingIntervalReanchorsInsteadOfImmediatelyFiring() {
    var scheduler = ReminderScheduler()
    scheduler.anchor(.hydration, at: 1_000)
    let configs: [(kind: ReminderKind, enabled: Bool, interval: TimeInterval)] = [
      (.hydration, true, 300)
    ]
    XCTAssertEqual(scheduler.due(configs: configs, monitoredSeconds: 1_001, suppressed: false), [])
    XCTAssertEqual(
      scheduler.due(configs: configs, monitoredSeconds: 1_300, suppressed: false), [.hydration])
  }
}
