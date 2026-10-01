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
  // private(set) so every mutation goes through the tier-aware update methods
  // (saveSettings vs saveSettingsAndResetAnalyzer) ; see CLAUDE.md.
  @Published private(set) var settings: AppSettings

  @Published private(set) var isWaitingToStart = false
  @Published private(set) var testNotificationMessage: String?
  @Published private(set) var isTestingNotification = false
  @Published private(set) var recoveryMessage: String?
  @Published private(set) var calibrationMessage = "Sit upright and hold still for calibration."
  @Published private(set) var isCalibrating = false
  @Published private(set) var diagnosticsText = "No motion samples yet"
  @Published private(set) var persistenceError: String?
  @Published private(set) var calibrationProfiles: [CalibrationProfile] = []
  @Published private(set) var systemError: String?
  private let now: () -> Date
  private let calendar: Calendar
  private var heartbeatTimer: Timer?
  private var lastReceivedAt: Date?
  private var lastSensorTimestamp: Date?
  private var sessionAccumulator: SessionAccumulator
  private var lastCheckpointAt: Date?
  private var wantsMonitoring = false
  private var isSystemSleeping = false
  private var calibrationStartedAt: Date?
  private var stableCalibrationStartedAt: Date?
  private var lastCalibrationSampleAt: Date?
  private var calibrationSamples: [(pitch: Double, roll: Double)] = []
  private var workspaceObservers: [NSObjectProtocol] = []
  private var reminderScheduler = ReminderScheduler()
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
  private var monitoredSeconds: TimeInterval = 0
  private let maxReadingGapSeconds: TimeInterval
  private var slouchEvents: Int = 0
  private var lastDeviationSampleAt: Date?
  private let deviationSampleInterval: TimeInterval = 0.2
  private let deviationWindowSeconds: TimeInterval = 60
  private let pitchDisplayUpdateInterval: TimeInterval
  private let ignoredNudgeLimit = 3
  private let nudgePauseDuration: TimeInterval = 600
  private var terminationObserver: NSObjectProtocol?
  private var didBecomeActiveObserver: NSObjectProtocol?
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
    historyStore: PostureHistoryStore = PostureHistoryStore(
      storageURL: PostureHistoryStore.defaultStorageURL),
    settingsDefaults: UserDefaults = .standard,
    settings: AppSettings? = nil,
    pitchDisplayUpdateInterval: TimeInterval = 0.5,
    maxReadingGapSeconds: TimeInterval = 2,
    now: @escaping () -> Date = Date.init,
    calendar: Calendar = .current,
    startHeartbeat: Bool = true
  ) {
    self.now = now
    self.calendar = calendar
    self.maxReadingGapSeconds = maxReadingGapSeconds
    self.sessionAccumulator = SessionAccumulator(calendar: calendar)
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
      // Restore the roll baseline too (NB-16): restoring with roll = 0 makes tilt
      // detection classify a user whose natural sensor roll exceeds the tilt
      // threshold as permanently .bad after every relaunch.
      analyzer.calibrate(pitch: savedPitch, roll: loadedSettings.calibratedBaselineRoll ?? 0)
      self.lastCalibratedPitch = savedPitch
      self.isBaselineRestored = true
      self.originalCalibratedPitch = savedPitch
    }
    self.analyzer = analyzer
    self.pitchDisplayUpdateInterval = pitchDisplayUpdateInterval
    self.launchAtLogin = SMAppService.mainApp.status == .enabled

    self.dailyStats = historyStore.stats
    self.hourlyStats = historyStore.hourlyStats
    self.persistenceError = historyStore.lastError
    if historyStore.recoveredSession {
      self.recoveryMessage =
        "Recovered measured posture time from your last interrupted session. Up to 15 seconds since the last successful save may be missing."
    }
    if let data = settingsDefaults.data(forKey: AppSettings.Keys.calibrationProfiles) {
      do {
        calibrationProfiles = try JSONDecoder().decode([CalibrationProfile].self, from: data)
          .filter(\.isValid)
      } catch {
        systemError = "Could not load calibration profiles: \(error.localizedDescription)"
      }
    }

    bindProviders()
    audioOutputMonitor.start()
    microphoneMonitor.start()
    isMicActive = microphoneMonitor.isMicActive
    activityMonitor.start()
    isUserAway = activityMonitor.isUserAway
    if audioOutputMonitor.isHeadphoneOutput {
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
    if startHeartbeat {
      heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        self?.refreshTrackingHealth()
      }
    }
    let workspace = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(
      workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.handleSystemSleep()
      })
    workspaceObservers.append(
      workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
        [weak self] _ in
        self?.handleSystemWake()
      })

    queueStartupMonitoringIfNeeded()

  }

  deinit {
    heartbeatTimer?.invalidate()
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }

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
        self?.maybeSendWeeklyDigest()
      }
    }
  }

  var sessionSummary: String {
    let today = calendar.startOfDay(for: now())
    let sessionCount =
      dailyStats.first { stat in
        calendar.isDate(stat.day, inSameDayAs: today)
      }?.sessionCount ?? 0
    return "Sessions today: \(sessionCount)"
  }

  func toggleMonitoring() {
    isMonitoring ? stopMonitoring() : startMonitoring()
  }

  func startMonitoring() {
    wantsMonitoring = true
    guard motionProvider.authorization != .denied && motionProvider.authorization != .restricted
    else {
      statusText = "Motion access denied. Open Motion Settings to allow NoSlouch."
      return
    }
    guard !isMonitoring else {
      return
    }

    guard audioOutputMonitor.isHeadphoneOutput else {
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
    isWaitingToStart = false
    isMonitoring = true
    sessionStartedAt = now()
    lastReadingAt = nil
    lastSensorTimestamp = nil
    resetSessionAccumulators()
    analyzer.resetForNewSession()
    postureState = analyzer.state
    motionProvider.start()
    refreshStatus()
  }

  func stopMonitoring() {
    isWaitingToStart = false
    wantsMonitoring = false
    cancelCalibration()
    guard isMonitoring else {
      invalidateReadings()
      refreshStatus()
      return
    }

    motionProvider.stop()
    finalizeSession()
    isMonitoring = false
    motionError = nil
    snoozedUntil = nil
    // The 3-strikes auto-pause must not survive the session (NB-24), and stale
    // readings must not feed the next guided calibration (NB-25).
    resetBadNudgeTracking()
    recentReadings.removeAll()
    invalidateReadings()
    refreshStatus()
  }

  func snoozeNudges(for duration: TimeInterval) {
    let base = now()
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
    let today = calendar.startOfDay(for: now())
    let stored = dailyStats.first { calendar.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0)
    let bad = (stored?.badSeconds ?? 0)
    let slouches = (stored?.slouchEvents ?? 0)
    let measured = good + bad

    guard measured > 0 else {
      return "Today: no data yet"
    }

    let percent = Int((good / measured * 100).rounded())
    return "Today: \(percent)% upright · \(slouches) slouches"
  }

  func calibrate() {
    guard hasFreshReading else { return }
    guard let pitch = latestPitch ?? currentPitch else {
      return
    }
    performCalibration(pitch: pitch, roll: latestRoll ?? 0)
  }

  /// Guided calibration: averages the most recent readings so a single noisy
  /// instant doesn't set a bad baseline (F2). Falls back to `calibrate()` if no
  /// samples are buffered yet.
  func calibrateAveraged() {
    guard hasFreshReading else { return }
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
    finalizeSession()
    settings.calibratedBaselinePitch = pitch
    settings.calibratedBaselineRoll = roll
    settings.lastCalibrationDate = now()
    settings.save(to: settingsDefaults)
    originalCalibratedPitch = pitch

    analyzer = Self.makeAnalyzer(settings: settings)
    analyzer.calibrate(pitch: pitch, roll: roll)
    postureState = analyzer.state
    lastCalibratedPitch = pitch
    isBaselineRestored = false
    resetBadNudgeTracking()

    if isMonitoring {
      sessionStartedAt = now()
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
    StreakCalculator(
      goalPercent: settings.dailyUprightGoalPercent,
      minimumMeasuredSeconds: settings.minimumDailyMinutes * 60
    )
    .currentStreak(stats: dailyStats, asOf: now(), calendar: calendar)
  }

  var longestStreak: Int {
    StreakCalculator(
      goalPercent: settings.dailyUprightGoalPercent,
      minimumMeasuredSeconds: settings.minimumDailyMinutes * 60
    )
    .longestStreak(stats: dailyStats, calendar: calendar)
  }

  var goalMetToday: Bool {
    let today = calendar.startOfDay(for: now())
    let stored = dailyStats.first { calendar.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0)
    let bad = (stored?.badSeconds ?? 0)
    let measured = good + bad
    guard measured >= settings.minimumDailyMinutes * 60 else {
      return false
    }
    return (good / measured * 100.0) >= settings.dailyUprightGoalPercent
  }

  var todayGrade: PostureGrade? {
    let today = calendar.startOfDay(for: now())
    let stored = dailyStats.first { calendar.isDate($0.day, inSameDayAs: today) }
    let good = (stored?.goodSeconds ?? 0)
    let bad = (stored?.badSeconds ?? 0)
    let measured = good + bad
    guard measured >= settings.minimumDailyMinutes * 60 else {
      return nil
    }
    return PostureGrade.forFraction(good / measured)
  }

  var unlockedAchievements: [Achievement] {
    Achievements.unlocked(
      stats: dailyStats, goalPercent: settings.dailyUprightGoalPercent, calendar: calendar,
      minimumMeasuredSeconds: settings.minimumDailyMinutes * 60)
  }

  /// True once it has been at least `recalibrationReminderDays` since the last
  /// calibration, so the UI can suggest re-calibrating for accuracy (K2).
  var needsRecalibration: Bool {
    guard let last = settings.lastCalibrationDate else {
      return false
    }
    return now().timeIntervalSince(last) >= settings.recalibrationReminderDays * 86_400
  }

  func exportHistoryCSV() -> String {
    historyStore.exportCSV(stats: dailyStats)
  }

  func clearHistory() {
    // Discard instead of finalizing, which could deliver a digest of deleted data.
    sessionStartedAt = nil
    stopMonitoring()
    lastReadingAt = nil
    resetSessionAccumulators()
    historyStore.removeAll()
    recoveryMessage = nil
    dailyStats = []
    hourlyStats = []
    persistenceError = historyStore.lastError
    settings.lastWeeklyDigestDate = nil
    settings.save(to: settingsDefaults)
    refreshStatus()
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
    systemError = nil
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      systemError = "Could not change launch at login: \(error.localizedDescription)"
    }

    launchAtLogin = SMAppService.mainApp.status == .enabled
    if SMAppService.mainApp.status == .requiresApproval {
      systemError = "Allow NoSlouch in System Settings > General > Login Items."
    }
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
      // The real provider already delivers on main and checks its generation.
      // Avoid re-queuing a validated reading past a subsequent Stop action.
      if Thread.isMainThread {
        self?.handle(reading)
      } else {
        DispatchQueue.main.async { self?.handle(reading) }
      }
    }

    motionProvider.onConnectionChanged = { [weak self] connected in
      DispatchQueue.main.async {
        if connected {
          self?.disconnected = false
          self?.batteryMonitor.start()
          self?.resumeAfterInterruptionIfNeeded()
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
          self?.resumeAfterInterruptionIfNeeded()
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
        guard let self else { return }
        if self.isUserAway != away && self.settings.pauseWhenAwayEnabled {
          self.resetAfterAwayTransition()
        }
        self.isUserAway = away
        if !away { self.resumeAfterInterruptionIfNeeded() }
        self.refreshStatus()
      }
    }

    notifier.onAction = { [weak self] action in
      DispatchQueue.main.async {
        switch action {
        case .snooze15:
          self?.snoozeNudges(for: 15 * 60)
        case .recalibrate:
          self?.beginGuidedCalibration()
        }
      }
    }
  }

  private func handle(_ reading: HeadMotionReading) {
    guard reading.pitch.isFinite, reading.roll.isFinite,
      abs(reading.pitch) <= 180, abs(reading.roll) <= 180,
      reading.timestamp.timeIntervalSinceReferenceDate.isFinite
    else {
      return
    }
    if let lastSensorTimestamp, reading.timestamp <= lastSensorTimestamp {
      return
    }
    motionError = nil
    lastReceivedAt = now()
    lastSensorTimestamp = reading.timestamp
    disconnected = false
    latestPitch = reading.pitch
    latestRoll = reading.roll
    recentReadings.append((pitch: reading.pitch, roll: reading.roll))
    if recentReadings.count > recentReadingsCapacity {
      recentReadings.removeFirst(recentReadings.count - recentReadingsCapacity)
    }
    updateDisplayedPitchIfNeeded(reading)
    canCalibrate = true
    let wasCalibrating = isCalibrating
    collectCalibration(reading)
    if wasCalibrating { refreshStatus(); return }

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

    var acceptedDelta: TimeInterval = 0
    if let lastReadingAt {
      let delta = reading.timestamp.timeIntervalSince(lastReadingAt)
      // A gap this long means motion delivery stalled (Mac sleep, Bluetooth
      // dropout, a re-seated bud) ; we weren't measuring, so book nothing rather
      // than pollute stats and instantly fire every overdue reminder (NB-15).
      if delta > 0 && delta <= maxReadingGapSeconds {
        acceptedDelta = delta
        sessionAccumulator.record(from: lastReadingAt, to: reading.timestamp, state: postureState)
        if postureState == .bad {
          badSeconds += delta
        } else if postureState == .good {
          goodSeconds += delta
        }
        // Reminders run on total monitored time, which unlike good/bad seconds
        // keeps advancing while the analyzer is uncalibrated (.unknown) ; an
        // analyzer-affecting settings change mid-session must not silently
        // freeze every reminder (NB-23).
        monitoredSeconds += delta
      } else if delta > maxReadingGapSeconds {
        analyzer.resetForNewSession()
        postureState = analyzer.state
        recentReadings = [(reading.pitch, reading.roll)]
      }
    }
    lastReadingAt = reading.timestamp

    let previousState = postureState
    postureState = analyzer.update(pitch: reading.pitch, roll: reading.roll, at: reading.timestamp)
    if postureState == .bad && previousState != .bad {
      slouchEvents += 1
      sessionAccumulator.recordSlouch(at: reading.timestamp)
    }

    applyAutoDriftIfNeeded(currentPitch: reading.pitch, dt: acceptedDelta)
    sessionGoodSeconds = goodSeconds
    sessionBadSeconds = badSeconds
    sessionSlouchEvents = slouchEvents
    recordDeviationSample(at: reading.timestamp)
    refreshHistorySnapshot()
    checkpointIfNeeded()

    processReminders(monitoredSeconds: monitoredSeconds, at: reading.timestamp)

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
  /// silently persist the drift ; NB-1), and keeps `lastCalibratedPitch` in sync
  /// with the analyzer so the UI baseline matches what classification uses (NB-3).
  private func applyAutoDriftIfNeeded(currentPitch: Double, dt: TimeInterval) {
    guard settings.autoDriftEnabled,
      postureState == .good,
      dt > 0,
      let original = originalCalibratedPitch,
      let currentBaseline = analyzer.calibration?.baselinePitch,
      let drop = analyzer.currentDrop,
      drop < settings.thresholdDegrees * 0.5
    else {
      return
    }

    // Time-based EMA (NB-22): 0.005/s regardless of sensor rate, so drift speed
    // doesn't double at 50 Hz vs 25 Hz. The drop guard keeps sub-threshold
    // slouching inside the hold window from pulling the baseline toward it.
    let alpha = min(1.0, 0.005 * dt)
    let candidate = currentBaseline * (1.0 - alpha) + currentPitch * alpha
    let newBaseline = max(original - 2.0, min(original + 2.0, candidate))

    guard newBaseline != currentBaseline else {
      return
    }

    analyzer.updateBaselinePitch(newBaseline)
    // Publishing on every motion frame invalidates SwiftUI 25–50×/s (NB-22);
    // 0.05° granularity keeps the displayed baseline in sync without the churn.
    // Landing exactly on the ±2° clamp always publishes so the settled value
    // matches the analyzer precisely.
    let hitBound = newBaseline == original - 2.0 || newBaseline == original + 2.0
    if !hitBound, let displayed = lastCalibratedPitch, abs(displayed - newBaseline) < 0.05 {
      return
    }
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

    let snoozed = snoozedUntil.map { timestamp < $0 } ?? false
    for kind in reminderScheduler.due(
      configs: reminderConfigs(), monitoredSeconds: monitoredSeconds,
      suppressed: mutedByMeeting || inQuietHours || snoozed)
    {
      notifier.nudgeReminder(
        kind: kind, settings: settings, notificationsEnabled: notificationsEnabled)
    }
  }

  /// True when `timestamp`'s local time-of-day falls inside the configured quiet
  /// window (B2), handling windows that span midnight.
  func isWithinQuietHours(at timestamp: Date) -> Bool {
    guard settings.quietHoursEnabled else {
      return false
    }
    let components = calendar.dateComponents([.hour, .minute], from: timestamp)
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
    reminderScheduler.anchor(kind, at: monitoredSeconds)
  }

  /// Fires a single low-battery warning per low episode; re-arms once the battery
  /// recovers above the threshold (H3).
  private func checkLowBattery(_ info: AirPodsBatteryInfo) {
    guard settings.lowBatteryWarningEnabled, !isWithinQuietHours(at: now()),
      !(settings.muteInMeetings && isMicActive), !(settings.pauseWhenAwayEnabled && isUserAway)
    else {
      return
    }
    // Buds only (NB-28): a drained charging case doesn't affect tracking, and a
    // persistently low case would both mis-warn and block the fire-once flag
    // from re-arming for the buds actually dying.
    let levels = [info.leftPercentage, info.rightPercentage].compactMap { $0 }
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
    interruptMonitoring()
    disconnected = true
  }

  private func finalizeSession() {
    guard sessionStartedAt != nil else { return }
    historyStore.commit(sessionAccumulator.hours)
    sessionStartedAt = nil
    lastReadingAt = nil
    resetSessionAccumulators()
    refreshHistorySnapshot()
    maybeSendWeeklyDigest()
  }

  private func refreshHistorySnapshot() {
    historyStore.pruneExpiredHistory()
    let snapshot = historyStore.preview(sessionAccumulator.hours)
    if dailyStats != snapshot.days { dailyStats = snapshot.days }
    if hourlyStats != snapshot.hours { hourlyStats = snapshot.hours }
    persistenceError = historyStore.lastError
  }

  private func checkpointIfNeeded(force: Bool = false) {
    guard isMonitoring else { return }
    if force || lastCheckpointAt == nil || now().timeIntervalSince(lastCheckpointAt ?? now()) >= 15
    {
      historyStore.checkpoint(sessionAccumulator.hours)
      lastCheckpointAt = now()
      persistenceError = historyStore.lastError
    }
  }

  /// Delivers the weekly digest as a notification once per 7 days (J2). First
  /// activation anchors the clock without firing; delivery is only counted when
  /// notifications are actually enabled, so a digest isn't silently consumed.
  private func maybeSendWeeklyDigest(now suppliedDate: Date? = nil) {
    let now = suppliedDate ?? self.now()
    guard settings.weeklyDigestEnabled else {
      return
    }
    guard let last = settings.lastWeeklyDigestDate else {
      settings.lastWeeklyDigestDate = now
      settings.save(to: settingsDefaults)
      return
    }
    guard now.timeIntervalSince(last) >= 7 * 86_400,
      notificationsEnabled,
      !dailyStats.isEmpty
    else {
      return
    }

    notifier.notifyWeeklyDigest(
      summary: WeeklyDigest.summary(stats: dailyStats, asOf: now, calendar: calendar),
      notificationsEnabled: notificationsEnabled
    )
    settings.lastWeeklyDigestDate = now
    settings.save(to: settingsDefaults)
  }

  private func resetSessionAccumulators() {
    badSeconds = 0
    goodSeconds = 0
    monitoredSeconds = 0
    slouchEvents = 0
    sessionBadSeconds = 0
    sessionGoodSeconds = 0
    sessionSlouchEvents = 0
    deviationSamples = []
    lastDeviationSampleAt = nil
    reminderScheduler = ReminderScheduler()
    sessionAccumulator = SessionAccumulator(calendar: calendar)
    lastCheckpointAt = nil
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
    settings.calibratedBaselineRoll = nil
    settings.lastCalibrationDate = nil
    settings.save(to: settingsDefaults)
    analyzer = Self.makeAnalyzer(settings: settings)
    postureState = analyzer.state
    lastCalibratedPitch = nil
    originalCalibratedPitch = nil
    isBaselineRestored = false
    canCalibrate = hasFreshReading
    refreshStatus()
  }

  private func refreshStatus() {
    if isCalibrating { statusText = calibrationMessage; return }
    if motionProvider.authorization == .denied || motionProvider.authorization == .restricted {
      statusText = "Motion access denied. Open Motion Settings to allow NoSlouch."
      return
    }
    if isMonitoring && !hasFreshReading {
      statusText = "Waiting for fresh headphone motion. Reconnect or Retry."
      return
    }
    if audioOutputMonitor.isHeadphoneOutput && !motionProvider.isDeviceMotionAvailable {
      statusText = "Headphone motion unavailable. Connect supported AirPods or Beats Fit Pro."
      return
    }
    let notificationSuffix = notificationsEnabled ? "" : " (notifications off)"

    if let motionError {
      statusText = motionError
      return
    }

    if disconnected {
      statusText = "AirPods disconnected\(notificationSuffix)"
    } else if !audioOutputMonitor.isHeadphoneOutput {
      statusText = "Set AirPods as output\(notificationSuffix)"
    } else if !isMonitoring {
      // Suppression states (mic, snooze, pause) only make sense while
      // monitoring; an idle app must not claim "Nudges paused" (NB-24).
      let deviceName = audioOutputMonitor.deviceName
      if deviceName.isEmpty {
        statusText = "Ready\(notificationSuffix)"
      } else {
        statusText = "\(deviceName) connected\(notificationSuffix)"
      }
    } else if settings.muteInMeetings && isMicActive {
      statusText = "Nudges paused (mic active)"
    } else if settings.pauseWhenAwayEnabled && isUserAway {
      statusText = "Paused ; away from desk\(notificationSuffix)"
    } else if isWithinQuietHours(at: now()) {
      statusText = "Quiet hours\(notificationSuffix)"
    } else if let snoozedUntil {
      statusText = "Nudges snoozed · \(minutesLeft(until: snoozedUntil)) min left"
    } else if let nudgesPausedUntil {
      statusText = "Nudges paused · \(minutesLeft(until: nudgesPausedUntil)) min left"
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
    let remaining = deadline.timeIntervalSince(now())
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

  private func resetAfterAwayTransition() {
    cancelCalibration()
    checkpointIfNeeded(force: true)
    invalidateReadings()
    lastReadingAt = nil
    recentReadings.removeAll()
    analyzer.resetForNewSession()
    postureState = analyzer.state
    resetBadNudgeTracking()
  }

  func updatePauseWhenAwayEnabled(_ enabled: Bool) {
    if settings.pauseWhenAwayEnabled != enabled && isUserAway {
      resetAfterAwayTransition()
    }
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
    if enabled && settings.lastWeeklyDigestDate == nil {
      // Anchor at enable time so the first digest arrives a week from now.
      settings.lastWeeklyDigestDate = now()
    }
    settings.save(to: settingsDefaults)
  }

  /// Applies a `noslouch://` automation command (E2). Runs on main (called
  /// from `onOpenURL`).
  func handle(_ command: URLCommand) {
    switch command {
    case .start:
      startMonitoring()
    case .stop:
      stopMonitoring()
    case .calibrate:
      beginGuidedCalibration()
    case .resume:
      resumeNudges()
    case .snooze(let minutes):
      snoozeNudges(for: Double(minutes) * 60)
    }
  }

  var needsOnboarding: Bool {
    !settings.hasCompletedOnboarding
  }

  func completeOnboarding() {
    settings.hasCompletedOnboarding = true
    settings.save(to: settingsDefaults)
    queueStartupMonitoringIfNeeded()
  }

  var weeklyDigestText: String {
    WeeklyDigest.summary(stats: dailyStats, asOf: now(), calendar: calendar)
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

extension PostureViewModel {
  private var hasFreshReading: Bool {
    guard !disconnected, let lastReceivedAt, latestPitch != nil else { return false }
    return now().timeIntervalSince(lastReceivedAt) <= 2
      && audioOutputMonitor.isHeadphoneOutput
  }

  func refreshTrackingHealth() {
    let age = lastReceivedAt.map { max(0, now().timeIntervalSince($0)) }
    diagnosticsText =
      age.map { "Last motion sample: \(Int($0)) seconds ago" } ?? "No motion samples yet"
    if isMonitoring && !hasFreshReading {
      if lastReadingAt != nil {
        checkpointIfNeeded(force: true)
        lastReadingAt = nil
        analyzer.resetForNewSession()
        postureState = .unknown
        recentReadings.removeAll()
      }
      canCalibrate = false
    }
    if let snoozedUntil, now() >= snoozedUntil { self.snoozedUntil = nil }
    if let nudgesPausedUntil, now() >= nudgesPausedUntil { resetBadNudgeTracking() }
    if isCalibrating, let calibrationStartedAt, now().timeIntervalSince(calibrationStartedAt) > 8 {
      cancelCalibration()
      calibrationMessage = "Not enough stable motion. Check your headphones, then try again."
    }
    checkpointIfNeeded()
    refreshHistorySnapshot()
    resumeAfterInterruptionIfNeeded()
    refreshStatus()
  }

  private func invalidateReadings() {
    latestPitch = nil
    latestRoll = nil
    currentPitch = nil
    lastReceivedAt = nil
    lastSensorTimestamp = nil
    lastPitchDisplayUpdateAt = nil
    lastReadingAt = nil
    recentReadings.removeAll()
    canCalibrate = false
  }

  func handleSystemSleep() {
    isSystemSleeping = true
    interruptMonitoring()
  }

  func handleSystemWake() {
    isSystemSleeping = false
    resumeAfterInterruptionIfNeeded()
  }

  func interruptMonitoring() {
    let shouldResume = wantsMonitoring && settings.resumeAfterInterruption
    cancelCalibration()
    if isMonitoring {
      motionProvider.stop()
      finalizeSession()
      isMonitoring = false
    }
    wantsMonitoring = shouldResume
    invalidateReadings()
    resetBadNudgeTracking()
    refreshStatus()
  }

  private func resumeAfterInterruptionIfNeeded() {
    guard (isWaitingToStart || (wantsMonitoring && settings.resumeAfterInterruption)),
      !isMonitoring, !isSystemSleeping,
      !isUserAway, !disconnected, audioOutputMonitor.isHeadphoneOutput,
      motionProvider.isDeviceMotionAvailable
    else { return }
    startMonitoring()
  }

  func retryHistorySave() {
    if isMonitoring { checkpointIfNeeded(force: true) } else { historyStore.retrySave() }
    persistenceError = historyStore.lastError
  }

  func retryMotion() {
    let shouldMonitor = wantsMonitoring || isMonitoring
    motionProvider.stop()
    invalidateReadings()
    resetBadNudgeTracking()
    analyzer.resetForNewSession()
    postureState = .unknown
    if isMonitoring { motionProvider.start() } else if shouldMonitor { startMonitoring() }
    refreshStatus()
  }

  func openMotionSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func beginGuidedCalibration() {
    if !isMonitoring { startMonitoring() }
    guard isMonitoring, !isUserAway else { return }
    calibrationStartedAt = now()
    calibrationSamples = []
    stableCalibrationStartedAt = nil
    lastCalibrationSampleAt = nil
    isCalibrating = true
    calibrationMessage = "Sit upright and hold still for 3 seconds."
    lastReadingAt = nil
    refreshStatus()
  }

  func cancelCalibration() {
    isCalibrating = false
    calibrationStartedAt = nil
    stableCalibrationStartedAt = nil
    lastCalibrationSampleAt = nil
    calibrationSamples = []
  }

  private func collectCalibration(_ reading: HeadMotionReading) {
    guard isCalibrating else { return }
    if let lastCalibrationSampleAt, reading.timestamp.timeIntervalSince(lastCalibrationSampleAt) > 2
    {
      calibrationSamples = []
      stableCalibrationStartedAt = nil
    }
    lastCalibrationSampleAt = reading.timestamp
    if stableCalibrationStartedAt == nil { stableCalibrationStartedAt = now() }
    calibrationSamples.append((reading.pitch, reading.roll))
    let elapsed = now().timeIntervalSince(stableCalibrationStartedAt ?? now())
    calibrationMessage = "Hold still: \(max(0, 3 - Int(elapsed))) seconds remaining"
    guard elapsed >= 3, calibrationSamples.count >= 15 else { return }
    let pitches = calibrationSamples.map(\.pitch)
    let rolls = calibrationSamples.map(\.roll)
    guard (pitches.max() ?? 0) - (pitches.min() ?? 0) <= 3,
      (rolls.max() ?? 0) - (rolls.min() ?? 0) <= 3
    else {
      cancelCalibration()
      calibrationMessage = "Too much movement. Sit comfortably upright and try again."
      return
    }
    let count = Double(calibrationSamples.count)
    let pitch = pitches.reduce(0, +) / count
    let roll = rolls.reduce(0, +) / count
    cancelCalibration()
    performCalibration(pitch: pitch, roll: roll)
    calibrationMessage = "Calibration complete. Your upright position is saved."
  }

  func updateResumeAfterInterruption(_ enabled: Bool) {
    settings.resumeAfterInterruption = enabled
    settings.save(to: settingsDefaults)
    if !enabled && !isMonitoring { wantsMonitoring = false }
  }

  func updateMinimumDailyMinutes(_ minutes: Double) {
    guard minutes.isFinite else { return }
    settings.minimumDailyMinutes = min(240, max(1, minutes))
    settings.save(to: settingsDefaults)
  }

  func saveCalibrationProfile(named name: String) {
    guard let pitch = settings.calibratedBaselinePitch else { return }
    let profile = CalibrationProfile(
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      pitch: pitch, roll: settings.calibratedBaselineRoll ?? 0, savedAt: now())
    guard profile.isValid else { return }
    calibrationProfiles.removeAll { $0.name == profile.name }
    calibrationProfiles.append(profile)
    persistProfiles()
  }

  func applyCalibrationProfile(_ profile: CalibrationProfile) {
    guard profile.isValid else { return }
    cancelCalibration()
    performCalibration(pitch: profile.pitch, roll: profile.roll)
    settings.lastCalibrationDate = profile.savedAt
    settings.save(to: settingsDefaults)
    isBaselineRestored = true
    calibrationMessage = "Loaded \(profile.name). Recalibrate if your headphones have moved."
  }

  func deleteCalibrationProfile(_ profile: CalibrationProfile) {
    calibrationProfiles.removeAll { $0.id == profile.id }
    persistProfiles()
  }

  private func persistProfiles() {
    do {
      settingsDefaults.set(
        try JSONEncoder().encode(calibrationProfiles), forKey: AppSettings.Keys.calibrationProfiles)
    } catch {
      systemError = "Could not save calibration profiles: \(error.localizedDescription)"
    }
  }
}

extension PostureViewModel {
  private func queueStartupMonitoringIfNeeded() {
    guard settings.startMonitoringAtLaunch, settings.hasCompletedOnboarding, !isMonitoring else {
      return
    }
    isWaitingToStart = true
    resumeAfterInterruptionIfNeeded()
  }

  func updateStartMonitoringAtLaunch(_ enabled: Bool) {
    settings.startMonitoringAtLaunch = enabled
    settings.save(to: settingsDefaults)
    if !enabled {
      if isWaitingToStart && !isMonitoring { wantsMonitoring = false }
      isWaitingToStart = false
    }
  }

  func dismissRecoveryMessage() {
    recoveryMessage = nil
  }

  func openNotificationSettings() {
    notifier.openNotificationSettings()
  }

  func sendTestNotification() {
    guard !isTestingNotification else { return }
    isTestingNotification = true
    testNotificationMessage = "Checking notification permission..."
    notifier.refreshAuthorization { [weak self] allowed in
      DispatchQueue.main.async {
        self?.submitTestNotificationIfAuthorized(allowed)
      }
    }
  }

  private func submitTestNotificationIfAuthorized(_ allowed: Bool) {
    notificationsEnabled = allowed
    guard allowed else {
      isTestingNotification = false
      testNotificationMessage =
        "Notifications are disabled. Enable them, then send another test."
      return
    }
    notifier.testNotification(settings: settings) { [weak self] error in
      DispatchQueue.main.async {
        self?.finishTestNotification(error: error)
      }
    }
  }

  private func finishTestNotification(error: Error?) {
    isTestingNotification = false
    if let error {
      testNotificationMessage =
        "Could not submit the test notification: \(error.localizedDescription)"
    } else {
      testNotificationMessage =
        "Test notification submitted. If no banner appears, check macOS Focus and notification settings."
    }
  }

}
