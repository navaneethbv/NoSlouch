# NoSlouch MVP Design

## Goal

Build a small, tested macOS menu-bar app that uses AirPods head-motion readings to detect forward-head posture and nudge the user when they slouch. The first version should prove the core loop:

1. Read live head pitch from AirPods-compatible hardware.
2. Let the user calibrate an upright baseline.
3. Detect sustained forward-head posture.
4. Notify the user with a simple nudge.
5. Track basic session history.

The project should stay dependency-free and use Apple frameworks only.

## Platform Requirement

Minimum deployment target: **macOS 14.0**. This floor is required by `CMHeadphoneMotionManager`, which the macOS SDK marks as `API_AVAILABLE(macos(14.0))`. Package.swift must declare `.macOS(.v14)`.

## Entitlements and Permissions

Two items are required for `CMHeadphoneMotionManager` to return data, even under ad-hoc signing:

- `NSMotionUsageDescription` key in `Resources/Info.plist` with a user-facing explanation string.
- `com.apple.developer.coremotion.headphone-motion-data` entitlement in the app's entitlements file (`NoSlouch.entitlements`).

Without both, the API may silently return no data. The entitlements file must be present for Developer ID or App Store signing. The ad-hoc bundle path must avoid restricted entitlements unless hardware testing proves they are safe, because restricted entitlements can cause macOS to kill ad-hoc signed apps on launch.

## Scope

Included in the MVP:

- Swift package and macOS app bundle build scripts.
- Menu-bar UI with status, start/stop, calibrate, and basic settings.
- AirPods motion adapter using `CMHeadphoneMotionManager`.
- Audio output monitor that gates motion on AirPods being the active output.
- Pure Swift posture analyzer with unit tests.
- Basic notification/sound notifier.
- UserDefaults-backed settings and history with unit tests.
- Clean build verification and launch smoke test.

Deferred:

- Onboarding flow.
- Detailed charts.
- Launch at login.
- Homebrew formula and release automation.
- Developer ID / App Store signing beyond ad-hoc.
- Hardware automation tests.
- Third-party dependencies.

## File Structure

```text
Package.swift
Makefile
NoSlouch.entitlements
Resources/
  Info.plist
  AppIcon.icns          (placeholder PNG-to-icns; any 1024x1024 image is acceptable for MVP)
Sources/NoSlouch/
  NoSlouchApp.swift
  MenuBarView.swift
  PostureViewModel.swift

  Motion/HeadMotionReading.swift
  Motion/HeadMotionProvider.swift
  Motion/AirPodsMotionProvider.swift
  Motion/AudioOutputMonitor.swift

  Posture/PostureAnalyzer.swift
  Posture/PostureCalibration.swift
  Posture/PostureState.swift

  Alerts/PostureNotifier.swift

  Persistence/AppSettings.swift
  Persistence/PostureHistoryStore.swift
  Persistence/PostureSession.swift
Tests/NoSlouchTests/
  PostureAnalyzerTests.swift
  PostureHistoryStoreTests.swift
  AppSettingsTests.swift
```

`build.sh` is not used. The `Makefile` is the sole task runner (`make build`, `make test`, `make bundle`, `make run`). `Package.swift` handles Swift build resolution.

## Components

`NoSlouchApp` is the app entry point. It creates the shared `PostureViewModel` and presents `MenuBarView` inside a `MenuBarExtra` so the app runs without a Dock icon.

`MenuBarView` is intentionally thin. It shows posture state, motion availability, session controls, calibration, and a few settings. It sends user actions to `PostureViewModel`.

`PostureViewModel` coordinates the app. It owns the current state, starts and stops motion monitoring, sends readings into the analyzer, triggers notifications, and records completed sessions. It is not unit-tested because it wires hardware and UI together; it is covered by the manual smoke test only.

`HeadMotionProvider` is a protocol for streaming head-motion readings. `AirPodsMotionProvider` is the real Core Motion implementation. Tests can provide fake readings without linking behavior to hardware.

`AudioOutputMonitor` uses CoreAudio default-output-device notifications to determine whether AirPods are the current audio output. `PostureViewModel` consults it before starting and during monitoring: if AirPods are not the active output, motion data is unreliable and monitoring is disabled. When AirPods become the active output, the monitor notifies the view model, which re-enables the start button. It does not auto-resume a stopped session.

`PostureCalibration` is a value type (`struct PostureCalibration { var baselinePitch: Double }`). `PostureAnalyzer` holds an optional `PostureCalibration`; nil means uncalibrated (`.unknown` state). This keeps calibration data separate from analyzer logic.

`PostureAnalyzer` is pure Swift. It handles calibration, smoothing, threshold checks, hold timing, recovery timing, and state transitions. This module carries the highest unit-test priority.

`PostureNotifier` wraps user-facing nudges. The MVP can start with system notification and sound, with speech kept optional behind settings. Notification authorization is requested once at app launch via `UNUserNotificationCenter.requestAuthorization`. If denied, the notifier falls back to sound-only nudges; the menu-bar status line shows "(notifications off)" to make this visible to the user without a modal.

`AppSettings` persists user preferences in `UserDefaults`: threshold, hold duration, recovery duration, alert cooldown, sound enabled, speech enabled, and inverted pitch. Inverted pitch exists because some users wear AirPods with stems pointing up (ear tip down), which reverses the direction of the pitch signal; enabling this flag negates the drop calculation.

`PostureHistoryStore` persists daily aggregate history in `UserDefaults` JSON. It caps stored history at 90 days, evicting the oldest entries when saving. `PostureSession` represents one monitoring session before it is rolled into history.

## Data Flow

When the user starts monitoring, `PostureViewModel` asks `AirPodsMotionProvider` to stream readings. The provider delivers callbacks on a background `OperationQueue`, and the view model dispatches to the main thread before updating state or calling the analyzer.

The motion update interval is set to `0.1` seconds (10 Hz). The low-pass filter alpha of `0.2` at 10 Hz corresponds roughly to a 4-second time constant, which provides stable smoothing without excessive lag.

When the user calibrates, the view model passes the current smoothed pitch into `PostureAnalyzer` as a new `PostureCalibration`. After calibration, each reading updates the analyzer. If the analyzer enters `.bad`, the view model asks `PostureNotifier` to nudge, subject to cooldown.

When AirPods disconnect mid-session, `AudioOutputMonitor` fires a notification. The view model suspends analysis and shows "disconnected" status. The in-progress `PostureSession` is finalized at that point if it has lasted at least five seconds; otherwise it is discarded. Monitoring does not auto-resume on reconnect; the user must press Start.

When monitoring stops, recalibrates, or quits via the menu, the current `PostureSession` is finalized using the same five-second rule. The history store folds the session into the current day and evicts entries older than 90 days.

## Analyzer Behavior

The analyzer uses pitch as the primary signal. It low-pass filters live pitch with alpha `0.2` at a 10 Hz update rate. The posture drop is `baselinePitch - smoothedPitch`, unless inverted pitch is enabled, in which case the drop is `smoothedPitch - baselinePitch`.

State transitions:

- `.unknown` before calibration.
- `.good` after calibration while drop is under threshold.
- `.bad` when drop is at or above threshold for `holdSeconds`.
- `.good` again when drop remains below threshold for `recoverSeconds`.

This keeps the MVP simple while avoiding noisy one-frame alerts.

## Error Handling

If motion data is unavailable or AirPods are not the active audio output, the UI shows a disconnected or unavailable status and disables calibration until a reading exists.

If notification authorization is not granted, `PostureNotifier` falls back to sound-only nudges and the status line notes "(notifications off)".

If persisted settings or history cannot decode, the app falls back to defaults rather than crashing.

## Testing Strategy

Use TDD for testable modules.

Initial unit tests:

- `PostureAnalyzerTests`: calibration starts good, sustained drop becomes bad, brief drop does not alert, recovery returns good, inverted pitch works.
- `PostureHistoryStoreTests`: sessions aggregate by day, sessions under five seconds are ignored, history older than 90 days is evicted, malformed persisted data falls back safely.
- `AppSettingsTests`: defaults load, changed values persist, invalid stored values use defaults.

`PostureViewModel` is excluded from unit tests because it couples hardware, UI, and threading. It is verified by the manual smoke test.

Manual verification:

- `make run` builds and launches the app bundle.
- `pgrep -x NoSlouch` confirms launch.
- With AirPods hardware: start monitoring, calibrate upright, slouch, confirm nudge and session history update.

## Agent Split

Parallel agents can review or draft tests for independent modules:

- Posture agent: `PostureAnalyzer`, `PostureCalibration`, `PostureState`, and related tests.
- Persistence agent: `AppSettings`, `PostureHistoryStore`, `PostureSession`, and related tests.
- App shell agent: menu-bar app structure, motion provider adapter, audio output monitor, notifier adapter, entitlements wiring, and launch smoke path.

The main agent coordinates integration, resolves naming consistency, and runs the full verification commands.
