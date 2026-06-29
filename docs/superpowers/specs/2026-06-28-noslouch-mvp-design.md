# NoSlouch MVP Design

## Goal

Build a small, tested macOS menu-bar app that uses AirPods head-motion readings to detect forward-head posture and nudge the user when they slouch. The first version should prove the core loop:

1. Read live head pitch from AirPods-compatible hardware.
2. Let the user calibrate an upright baseline.
3. Detect sustained forward-head posture.
4. Notify the user with a simple nudge.
5. Track basic session history.

The project should stay dependency-free and use Apple frameworks only.

## Scope

Included in the MVP:

- Swift package and macOS app bundle build scripts.
- Menu-bar UI with status, start/stop, calibrate, and basic settings.
- AirPods motion adapter using `CMHeadphoneMotionManager`.
- Pure Swift posture analyzer with unit tests.
- Basic notification/sound notifier.
- UserDefaults-backed settings and history with unit tests.
- Clean build verification and launch smoke test.

Deferred:

- Onboarding flow.
- Detailed charts.
- Launch at login.
- Homebrew formula and release automation.
- Developer ID entitlement handling beyond keeping ad-hoc signing safe.
- Hardware automation tests.
- Third-party dependencies.

## File Structure

```text
Package.swift
Makefile
build.sh
Resources/
  Info.plist
  AppIcon.icns
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

## Components

`NoSlouchApp` is the app entry point. It creates the shared `PostureViewModel` and presents `MenuBarView` inside a `MenuBarExtra` so the app runs without a Dock icon.

`MenuBarView` is intentionally thin. It shows posture state, motion availability, session controls, calibration, and a few settings. It sends user actions to `PostureViewModel`.

`PostureViewModel` coordinates the app. It owns the current state, starts and stops motion monitoring, sends readings into the analyzer, triggers notifications, and records completed sessions.

`HeadMotionProvider` is a protocol for streaming head-motion readings. `AirPodsMotionProvider` is the real Core Motion implementation. Tests can provide fake readings without linking behavior to hardware.

`PostureAnalyzer` is pure Swift. It handles calibration, smoothing, threshold checks, hold timing, recovery timing, and state transitions. This module carries the highest unit-test priority.

`PostureNotifier` wraps user-facing nudges. The MVP can start with system notification and sound, with speech kept optional behind settings.

`AppSettings` persists user preferences in `UserDefaults`: threshold, hold duration, recovery duration, alert cooldown, sound enabled, speech enabled, and inverted pitch.

`PostureHistoryStore` persists daily aggregate history in `UserDefaults` JSON. `PostureSession` represents one monitoring session before it is rolled into history.

## Data Flow

When the user starts monitoring, `PostureViewModel` asks `AirPodsMotionProvider` to stream readings on the main thread. Each `HeadMotionReading` contains pitch, roll, yaw, and timestamp.

When the user calibrates, the view model passes the current smoothed pitch into `PostureAnalyzer` as the upright baseline. After calibration, each reading updates the analyzer. If the analyzer enters `.bad`, the view model asks `PostureNotifier` to nudge, subject to cooldown.

When monitoring stops, recalibrates, or quits, the current `PostureSession` is finalized if it lasted at least five seconds. The history store folds the session into the current day.

## Analyzer Behavior

The analyzer uses pitch as the primary signal. It low-pass filters live pitch with alpha `0.2`. The posture drop is `baselinePitch - smoothedPitch`, unless inverted pitch is enabled.

State transitions:

- `.unknown` before calibration.
- `.good` after calibration while drop is under threshold.
- `.bad` when drop is at or above threshold for `holdSeconds`.
- `.good` again when drop remains below threshold for `recoverSeconds`.

This keeps the MVP simple while avoiding noisy one-frame alerts.

## Error Handling

If motion data is unavailable, the UI shows a disconnected or unavailable status and disables calibration until a reading exists.

If notification authorization is not granted, `PostureNotifier` should fail quietly and keep sound or speech nudges available when enabled.

If persisted settings or history cannot decode, the app falls back to defaults rather than crashing.

## Testing Strategy

Use TDD for testable modules.

Initial unit tests:

- `PostureAnalyzerTests`: calibration starts good, sustained drop becomes bad, brief drop does not alert, recovery returns good, inverted pitch works.
- `PostureHistoryStoreTests`: sessions aggregate by day, sessions under five seconds are ignored, malformed persisted data falls back safely.
- `AppSettingsTests`: defaults load, changed values persist, invalid stored values use defaults.

Manual verification:

- `make run` builds and launches the app bundle.
- `pgrep -x NoSlouch` confirms launch.
- With AirPods hardware: start monitoring, calibrate upright, slouch, confirm nudge and session history update.

## Agent Split

Parallel agents can review or draft tests for independent modules:

- Posture agent: `PostureAnalyzer` behavior and tests.
- Persistence agent: `AppSettings`, `PostureHistoryStore`, and related tests.
- App shell agent: menu-bar app structure, motion provider adapter, notifier adapter, and launch smoke path.

The main agent coordinates integration, resolves naming consistency, and runs the full verification commands.
