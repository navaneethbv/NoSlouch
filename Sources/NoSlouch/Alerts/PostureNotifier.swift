import AVFoundation
import AppKit
import Foundation
import UserNotifications

protocol PostureNotifying: AnyObject {
  func refreshAuthorization(completion: @escaping (Bool) -> Void)
  func requestAuthorization(completion: @escaping (Bool) -> Void)
  func openNotificationSettings()
  func notifyPaused(until: Date, notificationsEnabled: Bool)
  func notifyLowBattery(percentage: Int, notificationsEnabled: Bool)
  func nudge(
    settings: AppSettings, notificationsEnabled: Bool, now: Date, drop: Double?, intensity: Int)
  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool)
  func previewSound(named name: String)
}

extension PostureNotifying {
  func nudge(settings: AppSettings, notificationsEnabled: Bool, drop: Double? = nil) {
    nudge(
      settings: settings, notificationsEnabled: notificationsEnabled, now: Date(), drop: drop,
      intensity: 1)
  }
}

final class PostureNotifier: NSObject, PostureNotifying {
  private let notificationCenter: UNUserNotificationCenter
  private let speechSynthesizer = AVSpeechSynthesizer()
  private var messageIndex = 0

  /// Chooses the nudge body: a user-supplied custom message (rotated) when any
  /// are set, otherwise the degree-drop message, otherwise a generic fallback.
  /// Pure and static so it can be unit-tested without posting a notification (I2).
  static func nudgeMessage(settings: AppSettings, drop: Double?, index: Int) -> String {
    let custom =
      settings.customNudgeMessages
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !custom.isEmpty {
      return custom[((index % custom.count) + custom.count) % custom.count]
    }
    if let drop, drop > 0 {
      return "Your head dropped \(Int(drop.rounded()))° below your baseline."
    }
    return "Sit up straight"
  }

  init(notificationCenter: UNUserNotificationCenter = .current()) {
    self.notificationCenter = notificationCenter
    super.init()
    notificationCenter.delegate = self
  }

  func refreshAuthorization(completion: @escaping (Bool) -> Void) {
    notificationCenter.getNotificationSettings { settings in
      completion(
        settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
    }
  }

  func requestAuthorization(completion: @escaping (Bool) -> Void) {
    notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
      completion(granted)
    }
  }

  func openNotificationSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      "x-apple.systempreferences:com.apple.preference.notifications",
    ]
    for string in candidates {
      if let url = URL(string: string), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  func notifyPaused(until: Date, notificationsEnabled: Bool) {
    guard notificationsEnabled else {
      return
    }

    let formatter = DateFormatter()
    formatter.timeStyle = .short

    let content = UNMutableNotificationContent()
    content.title = "NoSlouch paused"
    content.body = "Posture nudges are paused until \(formatter.string(from: until))."
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.paused.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    notificationCenter.add(request)
  }

  func nudge(
    settings: AppSettings, notificationsEnabled: Bool, now: Date = Date(), drop: Double? = nil,
    intensity: Int = 1
  ) {
    let message = Self.nudgeMessage(settings: settings, drop: drop, index: messageIndex)
    messageIndex += 1

    // Escalation forces sound at level ≥2 and speech at level ≥3 even if those
    // toggles are off, but only when the user enabled escalating nudges (I3).
    let forceSound = settings.escalatingNudges && intensity >= 2
    let forceSpeech = settings.escalatingNudges && intensity >= 3

    if settings.soundEnabled || forceSound {
      playSound(named: settings.soundName)
    }

    if settings.speechEnabled || forceSpeech {
      speechSynthesizer.speak(AVSpeechUtterance(string: message))
    }

    guard notificationsEnabled else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "NoSlouch"
    content.body = message
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.posture.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    notificationCenter.add(request)
  }

  func notifyLowBattery(percentage: Int, notificationsEnabled: Bool) {
    guard notificationsEnabled else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = "AirPods battery low"
    content.body = "AirPods at \(percentage)% — charge soon to keep posture tracking."
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.battery.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    notificationCenter.add(request)
  }

  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool) {
    let message = kind.body

    if settings.soundEnabled {
      playSound(named: settings.soundName)
    }

    if settings.speechEnabled {
      speechSynthesizer.speak(AVSpeechUtterance(string: message))
    }

    guard notificationsEnabled else {
      return
    }

    let content = UNMutableNotificationContent()
    content.title = kind.title
    content.body = message
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.reminder.\(kind.rawValue).\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    notificationCenter.add(request)
  }

  func previewSound(named name: String) {
    playSound(named: name)
  }

  private func playSound(named name: String) {
    if let sound = NSSound(named: NSSound.Name(name)) {
      sound.play()
    } else {
      NSSound.beep()
    }
  }
}

extension PostureNotifier: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
