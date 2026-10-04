import Foundation

struct ReminderScheduler {
  private var lastFired: [ReminderKind: TimeInterval] = [:]
  private var lastAny: TimeInterval = 0
  let minimumGap: TimeInterval = 120

  mutating func anchor(_ kind: ReminderKind, at monitoredSeconds: TimeInterval) {
    lastFired[kind] = monitoredSeconds
  }

  mutating func due(
    configs: [(kind: ReminderKind, enabled: Bool, interval: TimeInterval)],
    monitoredSeconds: TimeInterval, suppressed: Bool
  ) -> [ReminderKind] {
    guard !suppressed, monitoredSeconds - lastAny >= minimumGap else { return [] }
    guard
      let config = configs.first(where: {
        $0.enabled && monitoredSeconds - (lastFired[$0.kind] ?? 0) >= $0.interval
      })
    else { return [] }
    lastFired[config.kind] = monitoredSeconds
    lastAny = monitoredSeconds
    return [config.kind]
  }
}
