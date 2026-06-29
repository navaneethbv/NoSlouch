import Combine
import Foundation

final class PostureViewModel: ObservableObject {
  @Published private(set) var postureState: PostureState = .unknown
  @Published private(set) var statusText = "Ready"
  @Published private(set) var isMonitoring = false
  @Published private(set) var canCalibrate = false
  @Published private(set) var currentPitch: Double?
  @Published private(set) var lastCalibratedPitch: Double?
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var disconnected = false
  @Published var settings: AppSettings

  private let motionProvider: HeadMotionProvider
  private let audioOutputMonitor: AudioOutputMonitoring
  private let notifier: PostureNotifying
  private let historyStore: PostureHistoryStore
  private let settingsDefaults: UserDefaults
  private var analyzer: PostureAnalyzer
  private var sessionStartedAt: Date?
  private var lastReadingAt: Date?
  private var latestPitch: Double?
  private var lastPitchDisplayUpdateAt: Date?
  private var lastBadNudgeAt: Date?
  private var consecutiveBadNudgeCount = 0
  private var nudgesPausedUntil: Date?
  private var badSeconds: TimeInterval = 0
  private let pitchDisplayUpdateInterval: TimeInterval
  private let ignoredNudgeLimit = 3
  private let nudgePauseDuration: TimeInterval = 600

  init(
    motionProvider: HeadMotionProvider = AirPodsMotionProvider(),
    audioOutputMonitor: AudioOutputMonitoring = AudioOutputMonitor(),
    notifier: PostureNotifying = PostureNotifier(),
    historyStore: PostureHistoryStore = PostureHistoryStore(),
    settingsDefaults: UserDefaults = .standard,
    settings: AppSettings? = nil,
    pitchDisplayUpdateInterval: TimeInterval = 0.5
  ) {
    self.motionProvider = motionProvider
    self.audioOutputMonitor = audioOutputMonitor
    self.notifier = notifier
    self.historyStore = historyStore
    self.settingsDefaults = settingsDefaults
    let loadedSettings = settings ?? AppSettings.load(from: settingsDefaults)
    self.settings = loadedSettings
    self.analyzer = PostureViewModel.makeAnalyzer(settings: loadedSettings)
    self.pitchDisplayUpdateInterval = pitchDisplayUpdateInterval

    bindProviders()
    audioOutputMonitor.start()
    refreshStatus()
    notifier.requestAuthorization { [weak self] granted in
      DispatchQueue.main.async {
        self?.notificationsEnabled = granted
        self?.refreshStatus()
      }
    }
  }

  var sessionSummary: String {
    let today = Calendar.current.startOfDay(for: Date())
    let sessionCount =
      historyStore.stats.first { stat in
        Calendar.current.isDate(stat.day, inSameDayAs: today)
      }?.sessionCount ?? 0
    return "Sessions today: \(sessionCount)"
  }

  func toggleMonitoring() {
    isMonitoring ? stopMonitoring() : startMonitoring()
  }

  func startMonitoring() {
    guard !isMonitoring else {
      return
    }

    guard audioOutputMonitor.airPodsActive else {
      disconnected = false
      statusText = "Set AirPods as output"
      return
    }

    disconnected = false
    isMonitoring = true
    sessionStartedAt = Date()
    lastReadingAt = nil
    badSeconds = 0
    postureState = analyzer.state
    motionProvider.start()
    refreshStatus()
  }

  func stopMonitoring() {
    guard isMonitoring else {
      return
    }

    motionProvider.stop()
    finalizeSession(endedAt: Date())
    isMonitoring = false
    canCalibrate = latestPitch != nil
    refreshStatus()
  }

  func calibrate() {
    guard let pitch = latestPitch ?? currentPitch else {
      return
    }

    finalizeSession(endedAt: Date())
    analyzer = Self.makeAnalyzer(settings: settings)
    analyzer.calibrate(pitch: pitch)
    postureState = analyzer.state
    lastCalibratedPitch = pitch
    resetBadNudgeTracking()

    if isMonitoring {
      sessionStartedAt = Date()
      lastReadingAt = nil
      badSeconds = 0
    }

    refreshStatus()
  }

  func updateThreshold(_ threshold: Double) {
    settings.thresholdDegrees = threshold
    saveSettingsAndResetAnalyzer()
  }

  func updateSoundEnabled(_ enabled: Bool) {
    settings.soundEnabled = enabled
    settings.save(to: settingsDefaults)
  }

  func updateInvertedPitch(_ enabled: Bool) {
    settings.invertedPitch = enabled
    saveSettingsAndResetAnalyzer()
  }

  func updateAlertCooldown(_ cooldown: Double) {
    settings.alertCooldownSeconds = cooldown
    settings.save(to: settingsDefaults)
  }

  func requestNotifications() {
    notifier.requestAuthorization { [weak self] granted in
      DispatchQueue.main.async {
        self?.notificationsEnabled = granted
        self?.refreshStatus()

        if !granted {
          self?.notifier.openNotificationSettings()
        }
      }
    }
  }

  private func bindProviders() {
    motionProvider.onReading = { [weak self] reading in
      DispatchQueue.main.async {
        self?.handle(reading)
      }
    }

    motionProvider.onConnectionChanged = { [weak self] connected in
      DispatchQueue.main.async {
        if connected {
          self?.disconnected = false
        } else {
          self?.handleAirPodsUnavailable()
        }
        self?.refreshStatus()
      }
    }

    audioOutputMonitor.onChange = { [weak self] active in
      DispatchQueue.main.async {
        if active {
          self?.disconnected = false
        } else {
          self?.handleAirPodsUnavailable()
        }
        self?.refreshStatus()
      }
    }
  }

  private func handle(_ reading: HeadMotionReading) {
    latestPitch = reading.pitch
    updateDisplayedPitchIfNeeded(reading)
    canCalibrate = true

    guard isMonitoring else {
      refreshStatus()
      return
    }

    if let lastReadingAt, postureState == .bad {
      badSeconds += max(0, reading.timestamp.timeIntervalSince(lastReadingAt))
    }
    lastReadingAt = reading.timestamp

    postureState = analyzer.update(pitch: reading.pitch, at: reading.timestamp)

    if postureState == .bad {
      maybeNudgeForBadPosture(at: reading.timestamp)
    } else {
      resetBadNudgeTracking()
    }

    refreshStatus()
  }

  private func maybeNudgeForBadPosture(at timestamp: Date) {
    if let nudgesPausedUntil {
      if timestamp < nudgesPausedUntil {
        return
      }

      self.nudgesPausedUntil = nil
      consecutiveBadNudgeCount = 0
      lastBadNudgeAt = nil
    }

    if let lastBadNudgeAt,
      timestamp.timeIntervalSince(lastBadNudgeAt) < settings.alertCooldownSeconds
    {
      return
    }

    notifier.nudge(settings: settings, notificationsEnabled: notificationsEnabled, now: timestamp)
    lastBadNudgeAt = timestamp
    consecutiveBadNudgeCount += 1

    if consecutiveBadNudgeCount >= ignoredNudgeLimit {
      let pausedUntil = timestamp.addingTimeInterval(nudgePauseDuration)
      nudgesPausedUntil = pausedUntil
      notifier.notifyPaused(until: pausedUntil, notificationsEnabled: notificationsEnabled)
    }
  }

  private func resetBadNudgeTracking() {
    lastBadNudgeAt = nil
    consecutiveBadNudgeCount = 0
    nudgesPausedUntil = nil
  }

  private func updateDisplayedPitchIfNeeded(_ reading: HeadMotionReading) {
    guard let lastPitchDisplayUpdateAt else {
      currentPitch = reading.pitch
      self.lastPitchDisplayUpdateAt = reading.timestamp
      return
    }

    if reading.timestamp.timeIntervalSince(lastPitchDisplayUpdateAt) >= pitchDisplayUpdateInterval {
      currentPitch = reading.pitch
      self.lastPitchDisplayUpdateAt = reading.timestamp
    }
  }

  private func handleAirPodsUnavailable() {
    if isMonitoring {
      motionProvider.stop()
      finalizeSession(endedAt: Date())
      isMonitoring = false
    }
    disconnected = true
  }

  private func finalizeSession(endedAt: Date) {
    guard let sessionStartedAt else {
      return
    }

    let session = PostureSession(
      startedAt: sessionStartedAt,
      endedAt: endedAt,
      badSeconds: badSeconds
    )
    historyStore.add(session)
    self.sessionStartedAt = nil
    lastReadingAt = nil
    badSeconds = 0
  }

  private func saveSettingsAndResetAnalyzer() {
    settings.save(to: settingsDefaults)
    analyzer = Self.makeAnalyzer(settings: settings)
    postureState = analyzer.state
    lastCalibratedPitch = nil
    canCalibrate = latestPitch != nil
    refreshStatus()
  }

  private func refreshStatus() {
    let notificationSuffix = notificationsEnabled ? "" : " (notifications off)"

    if disconnected {
      statusText = "AirPods disconnected\(notificationSuffix)"
    } else if !audioOutputMonitor.airPodsActive {
      statusText = "Set AirPods as output\(notificationSuffix)"
    } else if nudgesPausedUntil != nil {
      statusText = "Nudges paused for 10 min"
    } else if !isMonitoring {
      statusText = "Ready\(notificationSuffix)"
    } else {
      switch postureState {
      case .unknown:
        statusText = "Monitoring, calibrate upright\(notificationSuffix)"
      case .good:
        statusText = "Calibrated, posture looks good\(notificationSuffix)"
      case .bad:
        statusText = "Sit up straight\(notificationSuffix)"
      }
    }
  }

  private static func makeAnalyzer(settings: AppSettings) -> PostureAnalyzer {
    PostureAnalyzer(
      thresholdDegrees: settings.thresholdDegrees,
      holdSeconds: settings.holdSeconds,
      recoverSeconds: settings.recoverSeconds,
      invertedPitch: settings.invertedPitch
    )
  }
}
