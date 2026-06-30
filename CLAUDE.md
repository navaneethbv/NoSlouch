# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
make build        # swift build --disable-sandbox
make test         # swift test --disable-sandbox
make lint         # swift format lint --recursive --strict
make format       # swift format format --recursive --in-place (auto-fix)
make bundle       # build + assemble NoSlouch.app with ad-hoc codesign
make run          # bundle + open the app
make clean        # remove .build/ and NoSlouch.app
```

Run a single test class or method:

```bash
swift test --disable-sandbox --filter SlouchEngineTests
swift test --disable-sandbox --filter SlouchEngineTests/testSustainedDropBecomesBad
```

The `--disable-sandbox` flag is required on every `swift build` and `swift test` invocation in this repo.

CI (`.github/workflows/ci.yml`) runs on `macos-15` and gates `make test` plus `make bundle`; the Swift toolchain version is environment-dependent, so match the pinned runner when reproducing CI-only failures.

## Architecture

NoSlouch is a dependency-free macOS 14+ menu-bar app (`MenuBarExtra`, no Dock icon). The entry point is `NoSlouchApp.swift`. All coordination flows through `PostureViewModel`, which is the single `@StateObject` owned by the app.

**Data flow:**

```
AirPodsMotionProvider  ──onReading──►  PostureViewModel  ──pitch──►  SlouchEngine
                                              │                           │
AudioOutputMonitor  ──onChange──►            │          ◄──SlouchState───┘
MicrophoneMonitor   ──onChange──►            │
                                             │
                                    PostureNotifier  (nudge / break / sound / speech)
                                    PostureHistoryStore  (session → daily aggregate)
                                    AppSettings  (UserDefaults)
```

**Key design decisions:**

- `HeadMotionProvider`, `AudioOutputMonitoring`, `MicrophoneMonitoring`, and `PostureNotifying` are protocols. Real implementations require hardware. All ViewModel tests inject fakes via `init`.
- `MicrophoneMonitor` powers **"mute in meetings"**: it tracks `kAudioDevicePropertyDeviceIsRunningSomewhere` on the default input device (a hardware-state read, so it needs no microphone permission prompt and no `NSMicrophoneUsageDescription`). Like `AudioOutputMonitor`, it dispatches on `DispatchQueue.main`; the ViewModel reads `isMicActive` from the main thread only. When `settings.muteInMeetings` is on and the mic is active, **all** outbound alerts are suppressed: bad-posture nudges return early in `maybeNudgeForBadPosture`, and break reminders are deferred (their marker is not advanced) so a due break fires on the next reading once the mic frees up.
- **Break reminders** (`breakRemindersEnabled`, `breakReminderMinutes`) fire from `handle()` based on accumulated monitored time in the session (`goodSeconds + badSeconds`), tracked against `lastBreakNudgeMonitoredSeconds`, which resets with the session.
- `SlouchEngine` is a pure Swift `struct` (no imports). It is the highest unit-test priority module.
- `AudioOutputMonitor` dispatches its CoreAudio listener on `DispatchQueue.main`. All reads and writes of `airPodsActive` happen on the main thread; the ViewModel reads it from the main thread only.
- **Cooldown is owned by `PostureViewModel`** (`lastBadNudgeAt`, `nudgesPausedUntil`). `PostureNotifier.nudge()` does not rate-limit itself; it fires on every call. After `ignoredNudgeLimit` (3) consecutive bad nudges with no calibration, nudges pause for `nudgePauseDuration` (600 s).
- **Snooze (`snoozedUntil`) is separate from the auto-pause (`nudgesPausedUntil`).** It is user-initiated (`snoozeNudges(for:)`), based on the reading clock (`lastReadingAt`), in-memory only (never persisted), and deliberately NOT cleared by good posture, only by expiry, `resumeNudges()`, or `stopMonitoring()`. The auto-pause, by contrast, is cleared by good posture via `resetBadNudgeTracking()`.
- **Notification authorization is refreshed, not requested, at launch.** `init` calls `refreshAuthorization` (no system prompt); only the explicit "Enable Notifications" action calls `requestAuthorization`. `init` also observes `NSApplication.willTerminateNotification` to flush the active session on quit.
- Motion callbacks arrive on a background `OperationQueue` inside `AirPodsMotionProvider` and are dispatched to the main thread by the ViewModel before any state mutation.
- Sessions under 5 seconds are discarded. History is capped at 90 days in `PostureHistoryStore`.
- **Settings have two mutation tiers.** Analyzer-affecting fields (`thresholdDegrees`, `holdSeconds`, `recoverSeconds`, `invertedPitch`) call `saveSettingsAndResetAnalyzer()`, which rebuilds `SlouchEngine` and resets calibration state. Notifier-only fields (`soundEnabled`, `speechEnabled`, `alertCooldownSeconds`, `soundName`, `muteInMeetings`, `breakRemindersEnabled`, `breakReminderMinutes`) call `saveSettings()` only. Any new `AppSettings` field must be assigned to one tier.
- **calibratedBaselinePitch lifecycle**: Persisted in `AppSettings` on calibration (`calibrate()`) and auto-loaded on launch. Any change to the analyzer-affecting setting tier calls `saveSettingsAndResetAnalyzer()`, which clears the baseline pitch (`nil`) to avoid stale baselines.
- `AppSettings.soundName` is validated against `AppSettings.availableSoundNames` at load time; values not in that list fall back to "Glass".
- **The app declares three SwiftUI scenes** in `NoSlouchApp.swift`, all sharing the single `PostureViewModel`: a `MenuBarExtra` (`.window` style, label is `Image(systemName: viewModel.menuBarSymbolName)` so the icon tracks posture state), a `Window(id: "history")` for `HistoryView`, and the `Settings` scene. `MenuBarView` opens the history window with `openWindow(id: "history")` preceded by `NSApplication.shared.activate(...)` — the activation call is required because the app is `LSUIElement` (accessory) and has no normal window to bring forward.

**Entitlements:** `com.apple.developer.coremotion.headphone-motion-data` is in `NoSlouch.entitlements`. The Makefile only passes the entitlements file for non-ad-hoc signing (`SIGN_IDENTITY != -`). Ad-hoc local builds work but the restricted entitlement is not embedded; a Developer ID certificate is required to get live AirPods motion data in a signed release build.

## Testing notes

- `SlouchEngineTests`, `PostureHistoryStoreTests`, `AppSettingsTests` cover pure logic with no hardware dependency.
- `PostureViewModelTests` uses `FakeHeadMotionProvider`, `FakeAudioOutputMonitor`, and `FakePostureNotifier` (all defined at the bottom of that file). `FakePostureNotifier.nudge()` increments a counter unconditionally; cooldown behavior is tested through the ViewModel, not the fake.
- Use `drainMainQueue()` (defined in the test file) after `motionProvider.emit()` calls to let the ViewModel's main-thread dispatch settle before asserting.
- Tests use isolated `UserDefaults` suites (UUID-named) created and torn down per test to avoid cross-test contamination.

## rexyMCP workflow

This project uses the rexyMCP architect/executor workflow; the contract lives in
REXYMCP.md, imported below.

@REXYMCP.md
