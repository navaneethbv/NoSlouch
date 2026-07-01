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
  @Published private(set) var isUserAway = false
  @Published private(set) var isBaselineRestored = false
  @Published var settings: AppSettings

  private let motionProvider: HeadMotionProvider
  private let audioOutputMonitor: AudioOutputMonitoring
  private let microphoneMonitor: MicrophoneMonitoring
  private let activityMonitor: ActivityMonitoring
  private let batteryMonitor: AirPodsBatteryMonitoring
  private let notifier: PostureNotifying
  private let historyStore: PostureHistoryStore
  private let settingsDefaults: UserDefaults
  private var analyzer: SlouchEngine
  private var sessionStartedAt: Date?
  private var lastReadingAt: Date?
  private var latestPitch: Double?
  private var latestRoll: Double?
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
  private var lastReminderFiredMonitoredSeconds: [ReminderKind: TimeInterval] = [:]
  private var lastAnyReminderMonitoredSeconds: TimeInterval = 0
  private let minReminderGapSeconds: TimeInterval = 120
  private var lowBatteryWarned = false
  private let lowBatteryThreshold = 15
  private var recentReadings: [(pitch: Double, roll: Double)] = []
  private let recentReadingsCapacity = 20
  private var originalCalibratedPitch: Double?

  init(
    motionProvider: HeadMotionProvider = AirPodsMotionProvider(),
    audioOutputMonitor: AudioOutputMonitoring = AudioOutputMonitor(),
    microphoneMonitor: MicrophoneMonitoring = MicrophoneMonitor(),
    activityMonitor: ActivityMonitoring = ActivityMonitor(),
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
    self.activityMonitor = activityMonitor
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
    activityMonitor.start()
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
    activityMonitor.stop()
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

    guard motionProvider.isDeviceMotionAvailable else {
      disconnected = false
      statusText = "AirPods motion unavailable (need AirPods Pro/3/Max or Beats Fit Pro)"
      return
    }

    disconnected = false
    isMonitoring = true
    sessionStartedAt = Date()
    lastReadingAt = nil
    resetSessionAccumulators()
    analyzer.resetForNewSession()
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
    performCalibration(pitch: pitch, roll: latestRoll ?? 0)
  }

  /// Guided calibration: averages the most recent readings so a single noisy
  /// instant doesn't set a bad baseline (F2). Falls back to `calibrate()` if no
  /// samples are buffered yet.
  func calibrateAveraged() {
    guard !recentReadings.isEmpty else {
      calibrate()
      return
    }
    let count = Double(recentReadings.count)
    let avgPitch = recentReadings.reduce(0) { $0 + $1.pitch } / count
    let avgRoll = recentReadings.reduce(0) { $0 + $1.roll } / count
    performCalibration(pitch: avgPitch, roll: avgRoll)
  }

  private func performCalibration(pitch: Double, roll: Double) {
    finalizeSession(endedAt: Date())
    settings.calibratedBaselinePitch = pitch
    settings.lastCalibrationDate = Date()
    settings.save(to: settingsDefaults)
    originalCalibratedPitch = pitch

    analyzer = Self.makeAnalyzer(settings: settings)
    analyzer.calibrate(pitch: pitch, roll: roll)
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

  /// Applies a sensitivity preset's three analyzer knobs in one shot (A3).
  func applyPreset(_ preset: DetectionPreset) {
    settings.thresholdDegrees = preset.thresholdDegrees
    settings.holdSeconds = preset.holdSeconds
    settings.recoverSeconds = preset.recoverSeconds
    saveSettingsAndResetAnalyzer()
  }

  var currentPreset: DetectionPreset? {
    DetectionPreset.matching(settings)
  }

  var currentStreak: Int {
    StreakCalculator(goalPercent: settings.dailyUprightGoalPercent)
      .currentStreak(stats: dailyStats, asOf: Date(), calendar: .current)
  }

  var longestStreak: Int {
    StreakCalculator(goalPercent: settings.dailyUprightGoalPercent)
      .longestStreak(stats: dailyStats, calendar: .current)
  }

  var goalMetToday: Bool {
    let today = Calendar.current.startOfDay(for: Date())
    let stored = dailyStats.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0) + sessionGoodSeconds
    let bad = (stored?.badSeconds ?? 0) + sessionBadSeconds
    let measured = good + bad
    guard measured > 0 else {
      return false
    }
    return (good / measured * 100.0) >= settings.dailyUprightGoalPercent
  }

  var todayGrade: PostureGrade? {
    let today = Calendar.current.startOfDay(for: Date())
    let stored = dailyStats.first { Calendar.current.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0) + sessionGoodSeconds
    let bad = (stored?.badSeconds ?? 0) + sessionBadSeconds
    let measured = good + bad
    guard measured > 0 else {
      return nil
    }
    return PostureGrade.forFraction(good / measured)
  }

  var unlockedAchievements: [Achievement] {
    Achievements.unlocked(
      stats: dailyStats, goalPercent: settings.dailyUprightGoalPercent, calendar: .current)
  }

  /// True once it has been at least `recalibrationReminderDays` since the last
  /// calibration, so the UI can suggest re-calibrating for accuracy (K2).
  var needsRecalibration: Bool {
    guard let last = settings.lastCalibrationDate else {
      return false
    }
    return Date().timeIntervalSince(last) >= settings.recalibrationReminderDays * 86_400
  }

  func exportHistoryCSV() -> String {
    historyStore.exportCSV()
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

  func updateTiltDetectionEnabled(_ enabled: Bool) {
    settings.tiltDetectionEnabled = enabled
    saveSettingsAndResetAnalyzer()
  }

  func updateTiltThreshold(_ degrees: Double) {
    settings.tiltThresholdDegrees = degrees
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
        self?.checkLowBattery(info)
      }
    }

    activityMonitor.onChange = { [weak self] away in
      DispatchQueue.main.async {
        self?.isUserAway = away
        self?.refreshStatus()
      }
    }
  }

  private func handle(_ reading: HeadMotionReading) {
    motionError = nil
    latestPitch = reading.pitch
    latestRoll = reading.roll
    recentReadings.append((pitch: reading.pitch, roll: reading.roll))
    if recentReadings.count > recentReadingsCapacity {
      recentReadings.removeFirst(recentReadings.count - recentReadingsCapacity)
    }
    updateDisplayedPitchIfNeeded(reading)
    canCalibrate = true

    guard isMonitoring else {
      refreshStatus()
      return
    }

    // Freeze all posture accounting while the user is away from the desk so idle
    // time doesn't pollute stats, break timers, or trigger nudges (H1). We still
    // advance lastReadingAt so returning doesn't book a huge time delta.
    if settings.pauseWhenAwayEnabled && isUserAway {
      lastReadingAt = reading.timestamp
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
    postureState = analyzer.update(pitch: reading.pitch, roll: reading.roll, at: reading.timestamp)
    if postureState == .bad && previousState != .bad {
      slouchEvents += 1
    }

    applyAutoDriftIfNeeded(currentPitch: reading.pitch)
    sessionGoodSeconds = goodSeconds
    sessionBadSeconds = badSeconds
    sessionSlouchEvents = slouchEvents
    recordDeviationSample(at: reading.timestamp)

    processReminders(monitoredSeconds: goodSeconds + badSeconds, at: reading.timestamp)

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

    if isWithinQuietHours(at: timestamp) {
      return
    }

    // Snooze expiry is cleared in handle(); here we only suppress while active (BUG-9).
    if let snoozedUntil, timestamp < snoozedUntil {
      return
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

    // Escalate intensity with each consecutive un-corrected nudge (I3): 1 = the
    // configured banner/sound, 2 = force sound, 3 = force speech. Off unless
    // settings.escalatingNudges. Escalation still stops at the auto-pause boundary.
    let intensity = settings.escalatingNudges ? min(3, consecutiveBadNudgeCount + 1) : 1
    notifier.nudge(
      settings: settings,
      notificationsEnabled: notificationsEnabled,
      now: timestamp,
      drop: analyzer.currentDrop,
      intensity: intensity
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

  /// Opt-in (`settings.autoDriftEnabled`), in-memory-only baseline
  /// self-calibration. Nudges the analyzer baseline toward the user's sustained
  /// good-posture pitch via a very slow EMA, bounded to ±2° of the originally
  /// calibrated baseline. It deliberately does NOT mutate
  /// `settings.calibratedBaselinePitch` (so an unrelated `settings.save()` cannot
  /// silently persist the drift — NB-1), and keeps `lastCalibratedPitch` in sync
  /// with the analyzer so the UI baseline matches what classification uses (NB-3).
  private func applyAutoDriftIfNeeded(currentPitch: Double) {
    guard settings.autoDriftEnabled,
      postureState == .good,
      let original = originalCalibratedPitch,
      let currentBaseline = analyzer.calibration?.baselinePitch
    else {
      return
    }

    let alpha = 0.0005
    let candidate = currentBaseline * (1.0 - alpha) + currentPitch * alpha
    let newBaseline = max(original - 2.0, min(original + 2.0, candidate))

    guard newBaseline != currentBaseline else {
      return
    }

    analyzer.updateBaselinePitch(newBaseline)
    lastCalibratedPitch = newBaseline
  }

  private func reminderConfigs() -> [(kind: ReminderKind, enabled: Bool, interval: TimeInterval)] {
    [
      (.breakTime, settings.breakRemindersEnabled, settings.breakReminderMinutes * 60.0),
      (.eyeRest, settings.eyeRestEnabled, settings.eyeRestMinutes * 60.0),
      (.hydration, settings.hydrationEnabled, settings.hydrationMinutes * 60.0),
      (.movement, settings.movementRemindersEnabled, settings.movementMinutes * 60.0),
    ]
  }

  /// Fires any due recurring reminders (G2). Deferred (markers not advanced) while
  /// muted by a meeting or during quiet hours, and rate-limited by a global
  /// min-gap so multiple due reminders don't stack in one moment.
  private func processReminders(monitoredSeconds: TimeInterval, at timestamp: Date) {
    let mutedByMeeting = settings.muteInMeetings && isMicActive
    let inQuietHours = isWithinQuietHours(at: timestamp)

    for config in reminderConfigs() where config.enabled {
      let last = lastReminderFiredMonitoredSeconds[config.kind] ?? 0
      guard monitoredSeconds - last >= config.interval else {
        continue
      }
      if mutedByMeeting || inQuietHours {
        continue
      }
      guard monitoredSeconds - lastAnyReminderMonitoredSeconds >= minReminderGapSeconds else {
        continue
      }

      notifier.nudgeReminder(
        kind: config.kind, settings: settings, notificationsEnabled: notificationsEnabled)
      lastReminderFiredMonitoredSeconds[config.kind] = monitoredSeconds
      lastAnyReminderMonitoredSeconds = monitoredSeconds
    }
  }

  /// True when `timestamp`'s local time-of-day falls inside the configured quiet
  /// window (B2), handling windows that span midnight.
  func isWithinQuietHours(at timestamp: Date) -> Bool {
    guard settings.quietHoursEnabled else {
      return false
    }
    let components = Calendar.current.dateComponents([.hour, .minute], from: timestamp)
    let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    let start = settings.quietStartMinutes
    let end = settings.quietEndMinutes
    guard start != end else {
      return false
    }
    if start < end {
      return minutes >= start && minutes < end
    }
    return minutes >= start || minutes < end
  }

  private func anchorReminder(_ kind: ReminderKind) {
    lastReminderFiredMonitoredSeconds[kind] = goodSeconds + badSeconds
  }

  /// Fires a single low-battery warning per low episode; re-arms once the battery
  /// recovers above the threshold (H3).
  private func checkLowBattery(_ info: AirPodsBatteryInfo) {
    guard settings.lowBatteryWarningEnabled else {
      return
    }
    let levels = [info.leftPercentage, info.rightPercentage, info.casePercentage].compactMap { $0 }
    guard let lowest = levels.min() else {
      return
    }

    if lowest <= lowBatteryThreshold {
      if !lowBatteryWarned {
        notifier.notifyLowBattery(percentage: lowest, notificationsEnabled: notificationsEnabled)
        lowBatteryWarned = true
      }
    } else {
      lowBatteryWarned = false
    }
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
    lastReminderFiredMonitoredSeconds = [:]
    lastAnyReminderMonitoredSeconds = 0
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
    settings.lastCalibrationDate = nil
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
    } else if isMonitoring && settings.pauseWhenAwayEnabled && isUserAway {
      statusText = "Paused — away from desk\(notificationSuffix)"
    } else if isMonitoring && isWithinQuietHours(at: Date()) {
      statusText = "Quiet hours\(notificationSuffix)"
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
      anchorReminder(.breakTime)
    }
  }

  func updateBreakReminderMinutes(_ minutes: Double) {
    settings.breakReminderMinutes = minutes
    settings.save(to: settingsDefaults)
    // Re-anchor so shortening the interval mid-session doesn't immediately fire a
    // reminder against already-accumulated time (BUG-7).
    anchorReminder(.breakTime)
  }

  func updateEyeRestEnabled(_ enabled: Bool) {
    settings.eyeRestEnabled = enabled
    settings.save(to: settingsDefaults)
    if enabled {
      anchorReminder(.eyeRest)
    }
  }

  func updateEyeRestMinutes(_ minutes: Double) {
    settings.eyeRestMinutes = minutes
    settings.save(to: settingsDefaults)
    anchorReminder(.eyeRest)
  }

  func updateHydrationEnabled(_ enabled: Bool) {
    settings.hydrationEnabled = enabled
    settings.save(to: settingsDefaults)
    if enabled {
      anchorReminder(.hydration)
    }
  }

  func updateHydrationMinutes(_ minutes: Double) {
    settings.hydrationMinutes = minutes
    settings.save(to: settingsDefaults)
    anchorReminder(.hydration)
  }

  func updateMovementRemindersEnabled(_ enabled: Bool) {
    settings.movementRemindersEnabled = enabled
    settings.save(to: settingsDefaults)
    if enabled {
      anchorReminder(.movement)
    }
  }

  func updateMovementMinutes(_ minutes: Double) {
    settings.movementMinutes = minutes
    settings.save(to: settingsDefaults)
    anchorReminder(.movement)
  }

  func updateQuietHoursEnabled(_ enabled: Bool) {
    settings.quietHoursEnabled = enabled
    settings.save(to: settingsDefaults)
    refreshStatus()
  }

  func updateQuietStartMinutes(_ minutes: Int) {
    settings.quietStartMinutes = minutes
    settings.save(to: settingsDefaults)
    refreshStatus()
  }

  func updateQuietEndMinutes(_ minutes: Int) {
    settings.quietEndMinutes = minutes
    settings.save(to: settingsDefaults)
    refreshStatus()
  }

  func updateAutoDriftEnabled(_ enabled: Bool) {
    settings.autoDriftEnabled = enabled
    settings.save(to: settingsDefaults)
  }

  func updatePauseWhenAwayEnabled(_ enabled: Bool) {
    settings.pauseWhenAwayEnabled = enabled
    settings.save(to: settingsDefaults)
    refreshStatus()
  }

  func updateEscalatingNudges(_ enabled: Bool) {
    settings.escalatingNudges = enabled
    settings.save(to: settingsDefaults)
  }

  func updateCustomNudgeMessages(_ messages: [String]) {
    settings.customNudgeMessages = messages
    settings.save(to: settingsDefaults)
  }

  func updateDailyUprightGoal(_ percent: Double) {
    settings.dailyUprightGoalPercent = percent
    settings.save(to: settingsDefaults)
  }

  func updateRecalibrationReminderDays(_ days: Double) {
    settings.recalibrationReminderDays = days
    settings.save(to: settingsDefaults)
  }

  func updateLowBatteryWarningEnabled(_ enabled: Bool) {
    settings.lowBatteryWarningEnabled = enabled
    settings.save(to: settingsDefaults)
  }

  func updateSnoozePresets(_ minutes: [Int]) {
    settings.snoozePresetsMinutes = minutes
    settings.save(to: settingsDefaults)
  }

  func updateWeeklyDigestEnabled(_ enabled: Bool) {
    settings.weeklyDigestEnabled = enabled
    settings.save(to: settingsDefaults)
  }

  var needsOnboarding: Bool {
    !settings.hasCompletedOnboarding
  }

  func completeOnboarding() {
    settings.hasCompletedOnboarding = true
    settings.save(to: settingsDefaults)
  }

  var weeklyDigestText: String {
    WeeklyDigest.summary(stats: dailyStats, asOf: Date(), calendar: .current)
  }

  private static func makeAnalyzer(settings: AppSettings) -> SlouchEngine {
    SlouchEngine(
      thresholdDegrees: settings.thresholdDegrees,
      holdSeconds: settings.holdSeconds,
      recoverSeconds: settings.recoverSeconds,
      invertedPitch: settings.invertedPitch,
      tiltEnabled: settings.tiltDetectionEnabled,
      tiltThresholdDegrees: settings.tiltThresholdDegrees
    )
  }
}
