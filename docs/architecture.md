# NoSlouch — Architecture

NoSlouch is a dependency-free macOS 14+ menu-bar app that nudges the user when
their head pitch (read from AirPods motion sensors) indicates slouching. It has
no Dock icon and runs entirely from a `MenuBarExtra`.

This document is the source of truth for the system's shape. When a phase doc
and this document disagree, this document wins (STANDARDS.md §9).

## Layers

The app is three layers, coordinated by a single `PostureViewModel`.

### 1. Sensing / input

Hardware-facing sources, each behind a protocol so the ViewModel can be tested
with fakes:

- `HeadMotionProvider` (protocol) → `AirPodsMotionProvider` (real, CoreMotion).
  Emits `HeadMotionReading` (pitch/roll/yaw + timestamp) on `onReading`, and
  connection changes on `onConnectionChanged`. Real callbacks arrive on a
  background `OperationQueue`.
- `AudioOutputMonitoring` (protocol) → `AudioOutputMonitor` (real, CoreAudio).
  Tracks whether AirPods are the current output route via `airPodsActive`,
  notifying on `onChange`. Its CoreAudio listener dispatches on `DispatchQueue.main`;
  all reads/writes of `airPodsActive` happen on the main thread.

### 2. Analysis / coordination

- `PostureAnalyzer` — a pure Swift `struct` (no imports). Given a calibrated
  upright pitch, a threshold, and hold/recover durations, it maps a stream of
  `(pitch, timestamp)` samples to a `PostureState` (`unknown` / `good` / `bad`).
  Highest unit-test priority module.
- `PostureViewModel` — the single `@StateObject` the app owns. It is the only
  coordinator: it dispatches background motion callbacks to the main thread,
  drives the analyzer, owns the nudge cooldown (`lastBadNudgeAt`,
  `nudgesPausedUntil`), finalizes sessions, and exposes `@Published` UI state.
  All state mutation happens on the main thread.

### 3. Output / persistence / UI

- `PostureNotifier` (`PostureNotifying` protocol) — fires a nudge on every
  `nudge()` call (sound / speech / user notification). It does **not**
  rate-limit; cooldown is the ViewModel's job.
- `PostureHistoryStore` — aggregates finished `PostureSession`s into per-day
  stats in UserDefaults. Sessions under 5 seconds are discarded; history is
  capped at 90 days.
- `AppSettings` — a value type loaded from / saved to UserDefaults. Seven
  fields: `thresholdDegrees`, `holdSeconds`, `recoverSeconds`,
  `alertCooldownSeconds`, `soundEnabled`, `speechEnabled`, `invertedPitch`.
- UI — `NoSlouchApp` (`MenuBarExtra`, `.window` style) → `MenuBarView`. Future
  milestones add a `Settings` scene.

## Data flow

```
AirPodsMotionProvider  ──onReading──►  PostureViewModel  ──pitch──►  PostureAnalyzer
                                              │                           │
AudioOutputMonitor  ──onChange──►            │          ◄──PostureState──┘
                                             │
                                    PostureNotifier  (nudge / sound / speech)
                                    PostureHistoryStore  (session → daily aggregate)
                                    AppSettings  (UserDefaults)
```

A reading is dispatched to the main thread, fed to the analyzer, and the
resulting state decides whether the cooldown-gated nudge fires. Settings changes
re-build the analyzer (for analyzer-affecting fields) and persist to UserDefaults.

## Settings ownership

`AppSettings` is the model; `PostureViewModel.settings` is the live copy. Each
field is mutated through a dedicated `update<Field>` method on the ViewModel so
persistence and analyzer-rebuild side effects stay in one place. Two side-effect
classes:

- **Analyzer-affecting fields** (`thresholdDegrees`, `holdSeconds`,
  `recoverSeconds`, `invertedPitch`) — their setter saves **and** rebuilds the
  analyzer, because `PostureAnalyzer` is constructed from them.
- **Notifier-only fields** (`soundEnabled`, `speechEnabled`,
  `alertCooldownSeconds`) — their setter only saves; the analyzer is unaffected.

The UI binds to these methods; it never writes `AppSettings` or UserDefaults
directly.

## Non-goals

- No cloud account, sync, or remote storage. All data is local UserDefaults.
- No sensors other than AirPods head motion. No camera, no accelerometer fusion.
- No Dock icon, no main window beyond the menu-bar popover and a Settings window.
- No third-party dependencies. Apple frameworks only.
- No analytics / telemetry of user posture data off-device.

## Milestone roadmap

- **M1 — Settings/Preferences UI (active).** A dedicated Settings window
  exposing all seven `AppSettings` fields (including `speechEnabled`,
  `holdSeconds`, `recoverSeconds`, which currently have no UI), replacing the
  inline controls crammed into the menu-bar popover.
- **M2 — History & stats UI.** Visualize `PostureHistoryStore`: daily good/bad
  breakdown, trends, streaks.
- **M3 — Onboarding & calibration.** First-run flow: permission prompts, guided
  neutral-pitch calibration, explainer.
- **M4 — Release & distribution.** Developer ID signing, notarization, app icon,
  installer, updates.
