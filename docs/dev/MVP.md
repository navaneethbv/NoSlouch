# MVP Future Work

Features and improvements identified from comparing NoSlouch against
`posture-fix-main`. Items below are NOT bugs - they are enhancements to
implement in future milestones.

**Status update:** the M2, M3, and M4 candidate items below have all been
implemented (notification drop value, device name in status, launch at login;
per-session goodSeconds + slouchEvents; live deviation chart; named sound
picker with preview). They are retained here for traceability to the
`posture-fix-main` comparison.

## Reference project: posture-fix-main

Source reviewed at: `~/Downloads/posture-fix-main`

---

## Queued for future milestones

### M2 candidate - UX improvements

**Deviation in notification body**
- The reference passes the actual drop value (degrees below baseline) into
  the notification: "Your head dropped 14° below your baseline."
- NoSlouch currently sends a generic "Sit up straight" body.
- What's needed: expose `currentDrop: Double` from `PostureAnalyzer`,
  surface it through `PostureViewModel`, pass it into `PostureNotifier.nudge()`.
- Files: `PostureAnalyzer.swift`, `PostureViewModel.swift`,
  `PostureNotifier.swift`.

**Device name in connection status**
- Reference shows "AirPods Pro connected" instead of the generic "Ready".
- What's needed: expose `deviceName: String` from `AudioOutputMonitor` through
  the `AudioOutputMonitoring` protocol, surface it as a computed property on
  `PostureViewModel`, use it in `refreshStatus()` and optionally as a caption
  in `MenuBarView`.
- Files: `AudioOutputMonitor.swift`, `PostureViewModel.swift`,
  `MenuBarView.swift`.

**Launch at login**
- Reference uses `SMAppService.mainApp.register()/unregister()`.
- What's needed: add `setLaunchAtLogin(_ enabled: Bool)` to `PostureViewModel`
  (wrapping `SMAppService`), add a Toggle in `SettingsView`'s System section.
- Files: `PostureViewModel.swift`, `SettingsView.swift`.
- Note: requires a properly bundled `.app` (works after `make bundle`).

### M3 candidate - Richer session stats

**goodSeconds + slouchEvents during a session**
- Reference tracks `goodSeconds` and `slouchEvents` (transitions into `.bad`)
  alongside the existing `badSeconds`, and shows all three as live tile stats.
- NoSlouch tracks only `badSeconds` for the history store; the popover shows
  only "Sessions today: N".
- What's needed: add `goodSeconds` and `slouchEvents` counters to
  `PostureViewModel`, increment them in `handle()`, flush to `PostureHistoryStore`
  (which currently stores only `badSeconds`). May also require a `PostureSession`
  model update and migration.
- Files: `PostureViewModel.swift`, `PostureSession.swift`,
  `PostureHistoryStore.swift`, `MenuBarView.swift`.

### M4 candidate - Live chart

**60-second sliding pitch/deviation chart**
- Reference downsamples to ~5 Hz, keeps a sliding 60-second buffer of
  `DeviationSample` structs, and renders a `Charts.LineMark` with a dashed
  `RuleMark` at the alert threshold.
- What's needed: a `DeviationSample` struct, a rolling buffer on
  `PostureViewModel`, a `Charts` view in `MenuBarView` or a separate tab.
- Requires `import Charts` (available macOS 13+, no extra package needed).
- Files: `PostureViewModel.swift`, `MenuBarView.swift` (or a new
  `PostureChartView.swift`).

### M4 candidate - Sound picker

**Named system sound picker with preview**
- Reference offers 11 named `NSSound` options (Funk, Glass, Ping, etc.) plus
  a preview button, replacing the current on/off toggle.
- What's needed: a `soundName: String` field in `AppSettings` and
  `PostureNotifier.nudge()`, a `Picker` + preview button in `SettingsView`.
- Files: `AppSettings.swift`, `PostureNotifier.swift`, `SettingsView.swift`,
  `PostureViewModelTests.swift`.
