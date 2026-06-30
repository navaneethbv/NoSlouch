# Design: Robustness fixes + history, dynamic icon, snooze, upright score

Date: 2026-06-30

A code-review pass over NoSlouch plus four user-facing features. All work
keeps `PostureViewModel` as the single coordinator and keeps detection /
aggregation logic in pure, testable types.

## Bug / robustness fixes

### 1. Do not prompt for notifications on launch

`PostureViewModel.init` currently calls `notifier.requestAuthorization`, which
shows the system permission dialog on first launch. The `PostureNotifying`
protocol already declares `refreshAuthorization` (status check, no prompt) but
nothing uses it.

- `init` calls `refreshAuthorization` to reflect current status.
- The "Enable Notifications" button keeps calling `requestAuthorization`.
- Test impact: `testEnableNotificationsRequestsPermission` expected
  `requestCount == 2` (init + button); it becomes `1`. Add a `refreshCount`
  to `FakePostureNotifier` and assert init refreshed once.

### 2. Flush the in-progress session on app termination

Only the menu's Quit button calls `stopMonitoring()`. A system logout/shutdown
or Cmd-Q loses the active session.

- `PostureViewModel.init` observes `NSApplication.willTerminateNotification`
  and calls `stopMonitoring()` (which already finalizes the session).
- Testable by posting the notification and asserting the session was stored.

### 3. Derive the paused status text from the constant

`refreshStatus()` hardcodes `"Nudges paused for 10 min"` while the duration is
the separate constant `nudgePauseDuration = 600`.

- Compute `Int(nudgePauseDuration / 60)`. Output stays `"10 min"`, so the
  existing assertion still passes.

## Feature A: History / trends window

- New `Window(id: "history")` scene and `HistoryView.swift`. A "History…"
  button in `MenuBarView` opens it via `@Environment(\.openWindow)` plus
  `NSApplication.shared.activate(...)` (the app is menu-bar-only).
- `DayPostureStat` gains a computed `uprightFraction`:
  `goodSeconds / (goodSeconds + badSeconds)`, returning `0` when both are zero.
  Pure, unit tested.
- `PostureViewModel` publishes `@Published private(set) var dailyStats:
  [DayPostureStat]`, refreshed in `init` and after `finalizeSession`.
- `HistoryView` renders a Charts bar chart of upright % for the most recent 30
  days plus per-day rows (date, monitored time, slouch count).

## Feature B: Dynamic menu-bar icon

- `PostureViewModel` exposes computed `menuBarSymbolName`:
  - not monitoring -> `figure.stand`
  - monitoring + good/unknown -> `figure.stand`
  - monitoring + bad -> `figure.seated.side`
  - snoozed or auto-paused -> `moon.zzz`
  Pure mapping, unit tested.
- `NoSlouchApp` uses the `MenuBarExtra` label-closure form with
  `Image(systemName: viewModel.menuBarSymbolName)`.

## Feature C: Snooze monitoring

- New `snoozedUntil: Date?`, independent of the auto 3-strikes
  `nudgesPausedUntil`. It is **not** cleared by good posture (so it survives
  upright readings), only by expiry or `resumeNudges()`.
- `snoozeNudges(for:)` sets `snoozedUntil` from the reading clock
  (`lastReadingAt ?? Date()`) to stay consistent with the existing
  timestamp-based nudge logic and remain testable with the fakes.
- `maybeNudgeForBadPosture` returns early while `timestamp < snoozedUntil`.
- Menu: "Snooze nudges" with 15 / 30 / 60 min options and a "Resume" button
  shown while snoozed. Status text and the menu-bar icon reflect snoozed state.

## Feature D: Upright score in the menu

- `PostureViewModel` computed `todayUprightText` combines today's
  `DayPostureStat` (from `dailyStats`) with the live session accumulators
  (`sessionGoodSeconds` / `sessionBadSeconds`) into e.g.
  `"Today: 87% upright · 4 slouches"`.
- Shown in `MenuBarView` whether or not monitoring (currently only
  "Sessions today: N" appears).

## Testing

New pure-logic tests: `DayPostureStat.uprightFraction`,
`PostureViewModel.menuBarSymbolName`. New VM tests: snooze suppresses nudges,
snooze survives a good-posture reading, `dailyStats` publishes after a session
finalizes, launch refreshes (does not request) authorization, termination
flushes the active session. All via the existing `FakeHeadMotionProvider` /
`FakeAudioOutputMonitor` / `FakePostureNotifier`.

## Risk

The `Window` scene plus activation from a menu-bar-only (accessory) app is the
least-certain piece. If activation misbehaves, fall back to a second tab in the
existing `Settings` scene. Flag if it comes up.

## Settings tier note

No new `AppSettings` fields are introduced, so the two-tier settings rule
(`saveSettingsAndResetAnalyzer` vs `saveSettings`) is unaffected. Snooze state
is in-memory only and intentionally not persisted.
