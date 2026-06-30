import AVFoundation
import AppKit
import Foundation
import UserNotifications

protocol PostureNotifying: AnyObject {
  func refreshAuthorization(completion: @escaping (Bool) -> Void)
  func requestAuthorization(completion: @escaping (Bool) -> Void)
  func openNotificationSettings()
  func notifyPaused(until: Date, notificationsEnabled: Bool)
  func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date, drop: Double?)
  func nudgeBreak(settings: AppSettings, notificationsEnabled: Bool)
  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool)
  func previewSound(named name: String)
}

extension PostureNotifying {
  func nudge(settings: AppSettings, notificationsEnabled: Bool, drop: Double? = nil) {
    nudge(settings: settings, notificationsEnabled: notificationsEnabled, now: Date(), drop: drop)
  }
}

final class PostureNotifier: NSObject, PostureNotifying {
  private let notificationCenter: UNUserNotificationCenter
  private let speechSynthesizer = AVSpeechSynthesizer()

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
    settings: AppSettings, notificationsEnabled: Bool, now: Date = Date(), drop: Double? = nil
  ) {
    let message: String
    if let drop, drop > 0 {
      message = "Your head dropped \(Int(drop.rounded()))° below your baseline."
    } else {
      message = "Sit up straight"
    }

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

  func nudgeBreak(settings: AppSettings, notificationsEnabled: Bool) {
    let message = "Time to take a break and stretch!"

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
    content.title = "Break Reminder"
    content.body = message
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.break.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    notificationCenter.add(request)
  }

  func nudgeReminder(kind: ReminderKind, settings: AppSettings, notificationsEnabled: Bool) {
    let (title, message) = kind.notificationContent

    if settings.soundEnabled {
      playSound(named: settings.soundName)
    }

    if settings.speechEnabled {
      speechSynthesizer.speak(AVSpeechUtterance(string: message))
    }

    guard notificationsEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = title
    content.body = message
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: "noslouch.\(kind.identifier).\(UUID().uuidString)",
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
