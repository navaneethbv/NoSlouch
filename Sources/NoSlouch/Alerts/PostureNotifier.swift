import AppKit
import AVFoundation
import Foundation
import UserNotifications

protocol PostureNotifying: AnyObject {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date)
}

extension PostureNotifying {
    func nudge(settings: AppSettings, notificationsEnabled: Bool) {
        nudge(settings: settings, notificationsEnabled: notificationsEnabled, now: Date())
    }
}

final class PostureNotifier: PostureNotifying {
    private let notificationCenter: UNUserNotificationCenter
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastNudgeAt: Date?

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }

    func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date = Date()) {
        if let lastNudgeAt,
           now.timeIntervalSince(lastNudgeAt) < settings.alertCooldownSeconds {
            return
        }

        lastNudgeAt = now

        if settings.soundEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }

        if settings.speechEnabled {
            speechSynthesizer.speak(AVSpeechUtterance(string: "Sit up straight"))
        }

        guard notificationsEnabled else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "NoSlouch"
        content.body = "Sit up straight"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "noslouch.posture.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        notificationCenter.add(request)
    }
}
