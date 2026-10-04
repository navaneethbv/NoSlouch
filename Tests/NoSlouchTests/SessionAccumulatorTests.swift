import XCTest

@testable import NoSlouch

final class SessionAccumulatorTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  func testMeasuredIntervalsDoNotSpreadAcrossAwayTime() throws {
    let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T09:00:00Z"))
    var accumulator = SessionAccumulator(calendar: calendar)
    accumulator.record(from: start, to: start.addingTimeInterval(60), state: .good)
    accumulator.record(
      from: start.addingTimeInterval(7_200), to: start.addingTimeInterval(7_260), state: .bad)
    accumulator.recordSlouch(at: start.addingTimeInterval(7_200))
    XCTAssertEqual(accumulator.hours.map(\.totalSeconds), [60, 60])
    XCTAssertEqual(accumulator.hours.map(\.goodSeconds), [60, 0])
    XCTAssertEqual(accumulator.hours.map(\.badSeconds), [0, 60])
    XCTAssertEqual(accumulator.hours.map(\.slouchEvents), [0, 1])
    XCTAssertEqual(accumulator.hours.map(\.sessionCount), [1, 0])
  }

  func testIntervalSplitsAtMidnightAndUnknownIsUnmeasured() throws {
    let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T23:59:59Z"))
    var accumulator = SessionAccumulator(calendar: calendar)
    accumulator.record(from: start, to: start.addingTimeInterval(2), state: .good)
    accumulator.record(
      from: start.addingTimeInterval(2), to: start.addingTimeInterval(4), state: .unknown)
    XCTAssertEqual(accumulator.hours.map(\.goodSeconds), [1, 1])
    XCTAssertEqual(accumulator.hours.map(\.totalSeconds), [1, 1])
  }

  func testRepeatedDSTHoursRemainDistinct() throws {
    var local = calendar
    local.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T08:59:59Z"))
    var accumulator = SessionAccumulator(calendar: local)
    accumulator.record(from: start, to: start.addingTimeInterval(2), state: .bad)
    XCTAssertEqual(accumulator.hours.count, 2)
    XCTAssertEqual(accumulator.hours[1].hour.timeIntervalSince(accumulator.hours[0].hour), 3_600)
    XCTAssertEqual(accumulator.hours.map(\.badSeconds), [1, 1])
  }

  func testRecoveryIsIdempotentAfterCheckpointAndCommit() throws {
    let name = "NoSlouch.Recovery.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("history.json")
    let start = Date()
    var active = SessionAccumulator(calendar: calendar)
    active.record(from: start, to: start.addingTimeInterval(1), state: .good)
    let first = PostureHistoryStore(
      defaults: defaults, calendar: calendar, now: { start }, storageURL: file)
    first.checkpoint(active.hours)
    let recovered = PostureHistoryStore(
      defaults: defaults, calendar: calendar, now: { start }, storageURL: file)
    XCTAssertTrue(recovered.recoveredSession)
    XCTAssertEqual(recovered.stats.first?.goodSeconds, 1)
    let reloaded = PostureHistoryStore(
      defaults: defaults, calendar: calendar, now: { start }, storageURL: file)
    XCTAssertFalse(reloaded.recoveredSession)
    XCTAssertEqual(reloaded.stats.first?.goodSeconds, 1)
    var second = SessionAccumulator(calendar: calendar)
    second.record(from: start.addingTimeInterval(1), to: start.addingTimeInterval(3), state: .bad)
    reloaded.checkpoint(second.hours)
    reloaded.commit(second.hours)
    let committed = PostureHistoryStore(
      defaults: defaults, calendar: calendar, now: { start }, storageURL: file)
    XCTAssertEqual(committed.stats.first?.goodSeconds, 1)
    XCTAssertEqual(committed.stats.first?.badSeconds, 2)
    XCTAssertEqual(committed.stats.first?.sessionCount, 2)
    let json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    XCTAssertEqual(json["version"] as? Int, 2)
    XCTAssertEqual((json["pending"] as? [Any])?.count, 0)
    committed.removeAll()
    XCTAssertTrue(PostureHistoryStore(defaults: defaults, storageURL: file).stats.isEmpty)
  }

  func testCalendarRetentionPrunesSparseHistoryOnReload() throws {
    let name = "NoSlouch.Retention.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let today = calendar.startOfDay(for: Date())
    let cutoff = try XCTUnwrap(calendar.date(byAdding: .day, value: -89, to: today))
    let expired = cutoff.addingTimeInterval(-86_400)
    let store = PostureHistoryStore(defaults: defaults, calendar: calendar, now: { expired })
    store.add(
      PostureSession(
        startedAt: expired, endedAt: expired.addingTimeInterval(60), badSeconds: 0, goodSeconds: 60)
    )
    store.add(
      PostureSession(
        startedAt: cutoff, endedAt: cutoff.addingTimeInterval(60), badSeconds: 0, goodSeconds: 60))
    let reloaded = PostureHistoryStore(defaults: defaults, calendar: calendar, now: { today })
    XCTAssertEqual(reloaded.stats.map(\.day), [cutoff])
    XCTAssertEqual(
      PostureHistoryStore(defaults: defaults, calendar: calendar, now: { today }).stats.count, 1)
  }

  func testCheckpointFailurePreservesPreviousFile() throws {
    let name = "NoSlouch.WriteFailure.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PostureHistoryStore(defaults: defaults, storageURL: directory)
    store.checkpoint([])
    XCTAssertNotNil(store.lastError)
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
    XCTAssertTrue(isDirectory.boolValue)
  }
}
