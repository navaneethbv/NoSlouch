import AppKit
import CoreGraphics
import Foundation

protocol ActivityMonitoring: AnyObject {
  var isUserAway: Bool { get }
  var onChange: ((Bool) -> Void)? { get set }
  func start()
  func stop()
}

/// Tracks whether the user is away from the desk so posture accounting can pause
/// (H1). "Away" means the screen is locked / asleep, or there has been no HID
/// input for `idleThresholdSeconds`. Uses only public APIs and needs no
/// permissions. All state is read/written on the main thread (notifications and
/// the poll timer are scheduled on the main run loop).
final class ActivityMonitor: ActivityMonitoring {
  private(set) var isUserAway = false {
    didSet {
      if oldValue != isUserAway {
        onChange?(isUserAway)
      }
    }
  }
  var onChange: ((Bool) -> Void)?

  private let idleThresholdSeconds: TimeInterval
  private let pollInterval: TimeInterval = 15.0
  private var timer: Timer?
  private var screenLocked = false
  private var distributedObservers: [NSObjectProtocol] = []
  private var workspaceObservers: [NSObjectProtocol] = []

  init(idleThresholdSeconds: TimeInterval = 120.0) {
    self.idleThresholdSeconds = idleThresholdSeconds
  }

  func start() {
    let distributed = DistributedNotificationCenter.default()
    distributedObservers.append(
      distributed.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
      ) { [weak self] _ in
        self?.screenLocked = true
        self?.recompute()
      })
    distributedObservers.append(
      distributed.addObserver(
        forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
      ) { [weak self] _ in
        self?.screenLocked = false
        self?.recompute()
      })

    let workspace = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(
      workspace.addObserver(
        forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.screenLocked = true
        self?.recompute()
      })
    workspaceObservers.append(
      workspace.addObserver(
        forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.screenLocked = false
        self?.recompute()
      })

    timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      self?.recompute()
    }
    recompute()
  }

  func stop() {
    timer?.invalidate()
    timer = nil

    let distributed = DistributedNotificationCenter.default()
    for observer in distributedObservers {
      distributed.removeObserver(observer)
    }
    distributedObservers.removeAll()

    let workspace = NSWorkspace.shared.notificationCenter
    for observer in workspaceObservers {
      workspace.removeObserver(observer)
    }
    workspaceObservers.removeAll()
  }

  private func recompute() {
    isUserAway = screenLocked || (idleSeconds() >= idleThresholdSeconds)
  }

  private func idleSeconds() -> TimeInterval {
    // kCGAnyInputEventType (~0) — seconds since the last HID event of any kind.
    guard let anyInput = CGEventType(rawValue: ~0) else {
      return 0
    }
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
  }
}
