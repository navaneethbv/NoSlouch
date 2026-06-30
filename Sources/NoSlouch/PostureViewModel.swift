import AppKit
import Combine
import Foundation
import ServiceManagement

final class PostureViewModel: ObservableObject {
  @Published private(set) var postureState: SlouchState = .unknown
  @Published private(set) var statusText = "Ready"
  @Published private(set) var isMonitoring = false
  @Published private(set) var canCalibrate = false
  @Published private(set) var currentPitch: Double?
  @Published private(set) var lastCalibratedPitch: Double?
  @Published private(set) var notificationsEnabled = false
  @Published private(set) var disconnected = false
  @Published private(set) var motionError: String?
  @Published private(set) var launchAtLogin: Bool
  @Published private(set) var sessionGoodSeconds: TimeInterval = 0
  @Published private(set) var sessionBadSeconds: TimeInterval = 0
  @Published private(set) var sessionSlouchEvents: Int = 0
  @Published private(set) var deviationSamples: [DeviationSample] = []
  @Published private(set) var dailyStats: [DayPostureStat] = []
  @Published private(set) var hourlyStats: [HourPostureStat] = []
  @Published private(set) var batteryInfo: AirPodsBatteryInfo? = nil
  @Published private(set) var snoozedUntil: Date?
  @Published private(set) var isMicActive = false
  @Published private(set) var isBaselineRestored = false
  @Published var settings: AppSettings

  private let motionProvider: HeadMotionProvider
  private let audioOutputMonitor: AudioOutputMonitoring
  private let microphoneMonitor: MicrophoneMonitoring
  private let batteryMonitor: AirPodsBatteryMonitoring
  private let notifier: PostureNotifying
  private let historyStore: PostureHistoryStore
  private let settingsDefaults: UserDefaults
  private var analyzer: SlouchEngine
  private var sessionStartedAt: Date?
  private var lastReadingAt: Date?
  private var latestPitch: Double?
  private var lastPitchDisplayUpdateAt: Date?
  private var lastBadNudgeAt: Date?
  private var consecutiveBadNudgeCount = 0
  private var nudgesPausedUntil: Date?
  private var badSeconds: TimeInterval = 0
  private var goodSeconds: TimeInterval = 0
  private var slouchEvents: Int = 0
  private var lastDeviationSampleAt: Date?
  private let deviationSampleInterval: TimeInterval = 0.2
  private let deviationWindowSeconds: TimeInterval = 60
  private let pitchDisplayUpdateInterval: TimeInterval
  private let ignoredNudgeLimit = 3
  private let nudgePauseDuration: TimeInterval = 600
  private var terminationObserver: NSObjectProtocol?
  private var didBecomeActiveObserver: NSObjectProtocol?
  private var lastBreakNudgeMonitoredSeconds: TimeInterval = 0
  private var originalCalibratedPitch: Double?

  init(
    motionProvider: HeadMotionProvider = AirPodsMotionProvider(),
    audioOutputMonitor: AudioOutputMonitoring = AudioOutputMonitor(),
    microphoneMonitor: MicrophoneMonitoring = MicrophoneMonitor(),
    batteryMonitor: AirPodsBatteryMonitoring = AirPodsBatteryMonitor(),
    notifier: PostureNotifying = PostureNotifier(),
    historyStore: PostureHistoryStore = PostureHistoryStore(),
    settingsDefaults: UserDefaults = .standard,
    settings: AppSettings? = nil,
    pitchDisplayUpdateInterval: TimeInterval = 0.5
  ) {
    self.motionProvider = motionProvider
    self.audioOutputMonitor = audioOutputMonitor
    self.microphoneMonitor = microphoneMonitor
    self.batteryMonitor = batteryMonitor
    self.notifier = notifier
    self.historyStore = historyStore
    self.settingsDefaults = settingsDefaults
    let loadedSettings = settings ?? AppSettings.load(from: settingsDefaults)
    self.settings = loadedSettings
    var analyzer = PostureViewModel.makeAnalyzer(settings: loadedSettings)
    if let savedPitch = loadedSettings.calibratedBaselinePitch {
      analyzer.calibrate(pitch: savedPitch)
      self.lastCalibratedPitch = savedPitch
      self.isBaselineRestored = true
      self.originalCalibratedPitch = savedPitch
    }
    self.analyzer = analyzer
    self.pitchDisplayUpdateInterval = pitchDisplayUpdateInterval
    self.launchAtLogin = SMAppService.mainApp.status == .enabled

    self.dailyStats = historyStore.stats
    self.hourlyStats = historyStore.hourlyStats

    bindProviders()
    audioOutputMonitor.start()
    microphoneMonitor.start()
    if audioOutputMonitor.airPodsActive {
      batteryMonitor.start()
    }
    refreshStatus()
    refreshNotificationAuthorization()

    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.stopMonitoring()
      self?.batteryMonitor.stop()
    }

    didBecomeActiveObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshNotificationAuthorization()
    }
  }

  deinit {
    batteryMonitor.stop()
    if let terminationObserver {
      NotificationCenter.default.removeObserver(terminationObserver)
    }
    if let didBecomeActiveObserver {
      NotificationCenter.default.removeObserver(didBecomeActiveObserver)
    }
  }

  func refreshNotificationAuthorization() {
    notifier.refreshAuthorization { [weak self] granted in
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
    resetSessionAccumulators()
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
    motionError = nil
    snoozedUntil = nil
    canCalibrate = latestPitch != nil
    refreshStatus()
  }

  func snoozeNudges(for duration: TimeInterval) {
    let base = lastReadingAt ?? Date()
    snoozedUntil = base.addingTimeInterval(duration)
    refreshStatus()
  }

  func resumeNudges() {
    snoozedUntil = nil
    refreshStatus()
  }

  var menuBarSymbolName: String {
    guard isMonitoring else {
      return "figure.stand"
    }

    if snoozedUntil != nil || nudgesPausedUntil != nil {
      return "moon.zzz"
    }

    switch postureState {
    case .bad:
      return "figure.seated.side"
    case .good, .unknown:
      return "figure.stand"
    }
  }

  var todayUprightText: String {
    let today = Calendar.current.startOfDay(for: Date())
    let stored = dailyStats.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0) + sessionGoodSeconds
    let bad = (stored?.badSeconds ?? 0) + sessionBadSeconds
    let slouches = (stored?.slouchEvents ?? 0) + sessionSlouchEvents
    let measured = good + bad

    guard measured > 0 else {
      return "Today: no data yet"
    }

    let percent = Int((good / measured * 100).rounded())
    return "Today: \(percent)% upright · \(slouches) slouches"
  }

  func calibrate() {
    guard let pitch = latestPitch ?? currentPitch else {
      return
    }

    finalizeSession(endedAt: Date())
    settings.calibratedBaselinePitch = pitch
    settings.save(to: settingsDefaults)
    originalCalibratedPitch = pitch

    analyzer = Self.makeAnalyzer(settings: settings)
    analyzer.calibrate(pitch: pitch)
    postureState = analyzer.state
    lastCalibratedPitch = pitch
    isBaselineRestored = false
    resetBadNudgeTracking()

    if isMonitoring {
      sessionStartedAt = Date()
      lastReadingAt = nil
      resetSessionAccumulators()
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

  func updateSoundName(_ name: String) {
    settings.soundName = name
    settings.save(to: settingsDefaults)
  }

  func previewSound() {
    notifier.previewSound(named: settings.soundName)
  }

  func updateInvertedPitch(_ enabled: Bool) {
    settings.invertedPitch = enabled
    saveSettingsAndResetAnalyzer()
  }

  func updateAlertCooldown(_ cooldown: Double) {
    settings.alertCooldownSeconds = cooldown
    settings.save(to: settingsDefaults)
  }

  func updateSpeechEnabled(_ enabled: Bool) {
    settings.speechEnabled = enabled
    settings.save(to: settingsDefaults)
  }

  func updateHoldSeconds(_ seconds: TimeInterval) {
    settings.holdSeconds = seconds
    saveSettingsAndResetAnalyzer()
  }

  func updateRecoverSeconds(_ seconds: TimeInterval) {
    settings.recoverSeconds = seconds
    saveSettingsAndResetAnalyzer()
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      // Leave launchAtLogin reflecting the real state below.
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled
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
          self?.batteryMonitor.start()
        } else {
          self?.handleAirPodsUnavailable()
          self?.batteryMonitor.stop()
          self?.batteryInfo = nil
        }
        self?.refreshStatus()
      }
    }

    motionProvider.onError = { [weak self] error in
      DispatchQueue.main.async {
        self?.motionError = error
        self?.refreshStatus()
      }
    }

    audioOutputMonitor.onChange = { [weak self] active in
      DispatchQueue.main.async {
        if active {
          self?.disconnected = false
          self?.batteryMonitor.start()
        } else {
          self?.handleAirPodsUnavailable()
          self?.batteryMonitor.stop()
          self?.batteryInfo = nil
        }
        self?.refreshStatus()
      }
    }

    microphoneMonitor.onChange = { [weak self] active in
      DispatchQueue.main.async {
        self?.isMicActive = active
        self?.refreshStatus()
      }
    }

    batteryMonitor.onBatteryUpdate = { [weak self] info in
      DispatchQueue.main.async {
        self?.batteryInfo = info
      }
    }
  }

  private func handle(_ reading: HeadMotionReading) {
    motionError = nil
    latestPitch = reading.pitch
    updateDisplayedPitchIfNeeded(reading)
    canCalibrate = true

    guard isMonitoring else {
      refreshStatus()
      return
    }

    if let snoozedUntil, reading.timestamp >= snoozedUntil {
      self.snoozedUntil = nil
    }

    if let lastReadingAt {
      let delta = max(0, reading.timestamp.timeIntervalSince(lastReadingAt))
      if postureState == .bad {
        badSeconds += delta
      } else if postureState == .good {
        goodSeconds += delta
      }
    }
    lastReadingAt = reading.timestamp

    let previousState = postureState
    postureState = analyzer.update(pitch: reading.pitch, at: reading.timestamp)
    if postureState == .bad && previousState != .bad {
      slouchEvents += 1
    }

    // Auto-drift baseline pitch adjustment (Phase 05)
    if postureState == .good,
      let original = originalCalibratedPitch,
      let currentBaseline = settings.calibratedBaselinePitch
    {
      // Extremely slow exponential moving average: newBaseline = currentBaseline * 0.9995 + reading.pitch * 0.0005
      // With sample rate at ~10Hz, a coefficient of 0.0005 corresponds to ~200s time constant (about 3 minutes).
      let alpha = 0.0005
      let candidate = currentBaseline * (1.0 - alpha) + reading.pitch * alpha

      // Keep it within ±2.0 degrees of the original calibrated baseline
      let minBound = original - 2.0
      let maxBound = original + 2.0
      let newBaseline = max(minBound, min(maxBound, candidate))

      if newBaseline != currentBaseline {
        settings.calibratedBaselinePitch = newBaseline
        analyzer.updateBaselinePitch(newBaseline)
      }
    }
    sessionGoodSeconds = goodSeconds
    sessionBadSeconds = badSeconds
    sessionSlouchEvents = slouchEvents
    recordDeviationSample(at: reading.timestamp)

    if settings.breakRemindersEnabled {
      let currentMonitoredSeconds = goodSeconds + badSeconds
      let intervalSeconds = settings.breakReminderMinutes * 60.0
      let isDue = currentMonitoredSeconds - lastBreakNudgeMonitoredSeconds >= intervalSeconds
      let mutedByMeeting = settings.muteInMeetings && isMicActive
      // When muted by an active meeting, defer the break reminder (do not advance
      // the marker) so it fires on the next reading once the mic frees up.
      if isDue && !mutedByMeeting {
        notifier.nudgeBreak(settings: settings, notificationsEnabled: notificationsEnabled)
        lastBreakNudgeMonitoredSeconds = currentMonitoredSeconds
      }
    }

    if postureState == .bad {
      maybeNudgeForBadPosture(at: reading.timestamp)
    } else {
      resetBadNudgeTracking()
    }

    refreshStatus()
  }

  private func maybeNudgeForBadPosture(at timestamp: Date) {
    if settings.muteInMeetings && isMicActive {
      return
    }

    if let snoozedUntil {
      if timestamp < snoozedUntil {
        return
      }

      self.snoozedUntil = nil
    }

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

    notifier.nudge(
      settings: settings,
      notificationsEnabled: notificationsEnabled,
      now: timestamp,
      drop: analyzer.currentDrop
    )
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
      badSeconds: badSeconds,
      goodSeconds: goodSeconds,
      slouchEvents: slouchEvents
    )
    historyStore.add(session)
    dailyStats = historyStore.stats
    hourlyStats = historyStore.hourlyStats
    self.sessionStartedAt = nil
    lastReadingAt = nil
    resetSessionAccumulators()
  }

  private func resetSessionAccumulators() {
    badSeconds = 0
    goodSeconds = 0
    slouchEvents = 0
    sessionBadSeconds = 0
    sessionGoodSeconds = 0
    sessionSlouchEvents = 0
    deviationSamples = []
    lastDeviationSampleAt = nil
    lastBreakNudgeMonitoredSeconds = 0
  }

  private func recordDeviationSample(at timestamp: Date) {
    guard let drop = analyzer.currentDrop else {
      return
    }

    if let lastDeviationSampleAt,
      timestamp.timeIntervalSince(lastDeviationSampleAt) < deviationSampleInterval
    {
      return
    }

    deviationSamples.append(DeviationSample(timestamp: timestamp, deviation: drop))
    lastDeviationSampleAt = timestamp

    let cutoff = timestamp.addingTimeInterval(-deviationWindowSeconds)
    deviationSamples.removeAll { $0.timestamp < cutoff }
  }

  private func saveSettingsAndResetAnalyzer() {
    settings.calibratedBaselinePitch = nil
    settings.save(to: settingsDefaults)
    analyzer = Self.makeAnalyzer(settings: settings)
    postureState = analyzer.state
    lastCalibratedPitch = nil
    originalCalibratedPitch = nil
    isBaselineRestored = false
    canCalibrate = latestPitch != nil
    refreshStatus()
  }

  private func refreshStatus() {
    let notificationSuffix = notificationsEnabled ? "" : " (notifications off)"

    if let motionError {
      statusText = motionError
      return
    }

    if disconnected {
      statusText = "AirPods disconnected\(notificationSuffix)"
    } else if !audioOutputMonitor.airPodsActive {
      statusText = "Set AirPods as output\(notificationSuffix)"
    } else if settings.muteInMeetings && isMicActive {
      statusText = "Nudges paused (mic active)"
    } else if let snoozedUntil {
      statusText = "Nudges snoozed · \(minutesLeft(until: snoozedUntil)) min left"
    } else if let nudgesPausedUntil {
      statusText = "Nudges paused · \(minutesLeft(until: nudgesPausedUntil)) min left"
    } else if !isMonitoring {
      let deviceName = audioOutputMonitor.deviceName
      if deviceName.isEmpty {
        statusText = "Ready\(notificationSuffix)"
      } else {
        statusText = "\(deviceName) connected\(notificationSuffix)"
      }
    } else {
      switch postureState {
      case .unknown:
        statusText = "Monitoring, calibrate upright\(notificationSuffix)"
      case .good:
        if isBaselineRestored {
          statusText = "Calibrated (restored), posture looks good\(notificationSuffix)"
        } else {
          statusText = "Calibrated, posture looks good\(notificationSuffix)"
        }
      case .bad:
        statusText = "Sit up straight\(notificationSuffix)"
      }
    }
  }

  private func minutesLeft(until deadline: Date) -> Int {
    let remaining = deadline.timeIntervalSince(lastReadingAt ?? Date())
    return Int((max(0, remaining) / 60).rounded(.up))
  }

  func updateMuteInMeetings(_ enabled: Bool) {
    settings.muteInMeetings = enabled
    settings.save(to: settingsDefaults)
    refreshStatus()
  }

  func updateBreakRemindersEnabled(_ enabled: Bool) {
    settings.breakRemindersEnabled = enabled
    settings.save(to: settingsDefaults)
    if enabled {
      lastBreakNudgeMonitoredSeconds = goodSeconds + badSeconds
    }
  }

  func updateBreakReminderMinutes(_ minutes: Double) {
    settings.breakReminderMinutes = minutes
    settings.save(to: settingsDefaults)
  }

  private static func makeAnalyzer(settings: AppSettings) -> SlouchEngine {
    SlouchEngine(
      thresholdDegrees: settings.thresholdDegrees,
      holdSeconds: settings.holdSeconds,
      recoverSeconds: settings.recoverSeconds,
      invertedPitch: settings.invertedPitch
    )
  }
}
