import AppKit
import AVFoundation
import Foundation
import UserNotifications

protocol PostureNotifying: AnyObject {
    func refreshAuthorization(completion: @escaping (Bool) -> Void)
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func openNotificationSettings()
    func notifyPaused(until: Date, notificationsEnabled: Bool)
    func nudge(settings: AppSettings, notificationsEnabled: Bool, now: Date)
}

extension PostureNotifying {
    func nudge(settings: AppSettings, notificationsEnabled: Bool) {
        nudge(settings: settings, notificationsEnabled: notificationsEnabled, now: Date())
    }
}

final class PostureNotifier: NSObject, PostureNotifying {
    private let notificationCenter: UNUserNotificationCenter
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastNudgeAt: Date?

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.delegate = self
    }

    func refreshAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            completion(granted)
        }
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }

        NSWorkspace.shared.open(url)
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

extension PostureNotifier: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
