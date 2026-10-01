import Foundation

/// Stores only measured intervals. Missing samples never become posture time.
struct SessionAccumulator {
  private(set) var hours: [HourPostureStat] = []
  private var countedSession = false
  let calendar: Calendar

  init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  mutating func record(from start: Date, to end: Date, state: SlouchState) {
    guard start < end, state != .unknown else { return }
    var cursor = start
    while cursor < end {
      guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { return }
      let stop = min(end, hour.end)
      let seconds = stop.timeIntervalSince(cursor)
      let index = bucket(hour.start)
      hours[index].totalSeconds += seconds
      hours[index].goodSeconds += state == .good ? seconds : 0
      hours[index].badSeconds += state == .bad ? seconds : 0
      if !countedSession {
        hours[index].sessionCount += 1
        countedSession = true
      }
      cursor = stop
    }
  }

  mutating func recordSlouch(at date: Date) {
    guard let hour = calendar.dateInterval(of: .hour, for: date) else { return }
    hours[bucket(hour.start)].slouchEvents += 1
  }

  private mutating func bucket(_ hour: Date) -> Int {
    if let index = hours.firstIndex(where: { $0.hour == hour }) { return index }
    hours.append(HourPostureStat(hour: hour, sessionCount: 0, totalSeconds: 0, badSeconds: 0))
    return hours.count - 1
  }
}
