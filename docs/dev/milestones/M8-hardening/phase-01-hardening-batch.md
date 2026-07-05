# Phase 01: NB-11 … NB-30 hardening batch

**Milestone:** M8 — Data Integrity & Hardening
**Status:** complete (pending review)
**Depends on:** none
**Tags:** language=swift, kind=fix, size=l

## Goal

Fix every issue from `docs/dev/improvements.md` §10.6 (NB-11 … NB-30) plus the
leftover NB-7, so the data feeding streaks/grades/digest/hourly analytics is
trustworthy and the battery monitor cannot hang.

## Spec (what shipped)

**Monitors & alerts**

- NB-11/NB-12/NB-13/NB-21/NB-7 — `AirPodsBatteryMonitor` rewritten: pipe is
  drained *before* `waitUntilExit()` with a 15 s kill-switch (deadlock fix);
  parses `system_profiler -json` (locale-independent keys); only devices
  reporting left/right bud levels count, AirPods/Beats preferred, no
  whole-output fallback; a generation counter drops in-flight results after
  `stop()`; `start()` is a no-op while running (connect-flap debounce); the
  `NSClassFromString("XCTestCase")` production guard is replaced by an
  injectable `fetchRawOutput` test seam.
- NB-26 — `ActivityMonitor`: separate `isScreenLocked`/`displaysAsleep` flags
  (wake no longer clears lock), idempotent `start()`, idle threshold default
  raised 120 s → 600 s.
- NB-27/NB-28 — `PostureNotifier`: stable notification identifiers per kind
  (banners replace instead of stacking); `ReminderKind.spokenBody` so speech
  doesn't read "💧"/"~20 feet"; low-battery warning computed from buds only.
- NB-30 — `MicrophoneMonitor` resets `currentInputDeviceID` on listener
  registration failure so the next refresh retries.

**Time accounting & persistence**

- NB-15 — `PostureViewModel.handle()` discards inter-reading deltas > 300 s
  (motion stalls / Mac sleep book nothing instead of phantom hours + reminder
  bursts).
- NB-23 — reminders run on a new `monitoredSeconds` accumulator that keeps
  advancing while the analyzer is uncalibrated (`.unknown`).
- NB-14 — `PostureHistoryStore.add()` splits sessions across hour buckets pro
  rata (and across midnight); the session counts once in its starting hour.
- NB-29 — corrupt history blobs are backed up to `<key>.corrupt` before reset;
  store calendar unified to `.current`; `AppSettings` load clamps quiet-hours
  minutes to 0…1439, sanitizes snooze presets (positive/unique/non-empty), and
  clamps the daily goal to ≤ 100.
- NB-19 — `StreakCalculator` treats an unmet `asOf` day as pending (counts from
  the previous day) instead of zeroing the streak intraday.

**ViewModel & UI wiring**

- NB-16 — `calibratedBaselineRoll` persisted (all five `AppSettings` places)
  and restored, so tilt detection survives relaunch without false alarms;
  cleared by `saveSettingsAndResetAnalyzer()` like the pitch baseline.
- NB-17 — onboarding auto-presents at first launch from the `MenuBarExtra`
  label (`MenuBarLabel` helper view in `NoSlouchApp.swift`).
- NB-18 — `needsRecalibration` surfaced as a MenuBarView row.
- NB-20 — snooze-presets field uses local `@State` committed on submit.
- NB-22 — auto-drift EMA is dt-scaled (0.005/s), gated on
  `currentDrop < threshold/2`, and publishes `lastCalibratedPitch` at 0.05°
  granularity (exact at the ±2° clamp).
- NB-24 — `stopMonitoring()` clears the auto-pause; suppression status branches
  gated on `isMonitoring`.
- NB-25 — `recentReadings` cleared on stop/disconnect so guided calibration
  can't average a previous session.
- NB-29d — sensitivity picker gains a "Custom" case for hand-tuned values.

## Tests

- `AirPodsBatteryMonitorTests` rewritten for the JSON parser (7 tests incl.
  scoping, fallback, malformed input, injected-fetcher delivery).
- New: stalled-gap discard, stop-clears-auto-pause, stale-buffer calibration,
  reminders-while-uncalibrated, buds-only low battery, baseline-roll
  persist/restore (`PostureViewModelTests`); hour-split and midnight-split and
  corrupt-blob backup (`PostureHistoryStoreTests`); pending-today streaks
  (`StreakCalculatorTests`); quiet-minutes/snooze/goal clamps + roll round-trip
  (`AppSettingsTests`).
- Updated: tests that simulated continuous monitoring with single 600–1200 s
  timestamp jumps now emit ≤ 300 s steps (intent preserved; the jumps would be
  discarded as stalls by NB-15's fix).

## Update Log

- 2026-07-01 — phase complete. `make lint` exit 0;
  `swift build --disable-sandbox` zero warnings;
  `swift test --disable-sandbox` → **"Executed 135 tests, with 0 failures
  (0 unexpected)"** (was 117 tests before the phase; +18 new).
  Note: the default `.build/build.db` intermittently reports
  `disk I/O error` under the iCloud-synced Desktop path and can leave a stale
  test binary — verification used `--scratch-path /tmp/noslouch-scratch`.
  End-to-end verification against real AirPods hardware (battery widget JSON
  parse, onboarding auto-open on a fresh defaults domain) still needs a manual
  pass on a real device before release.
