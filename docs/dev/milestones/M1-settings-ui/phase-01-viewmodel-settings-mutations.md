# Phase 01: ViewModel settings-mutation completeness

**Milestone:** M1 — Settings/Preferences UI
**Status:** review
**Depends on:** none
**Estimated diff:** ~70 lines
**Tags:** language=swift, kind=feature, size=s

## Goal

Add the three missing `update<Field>` methods to `PostureViewModel` so every
`AppSettings` field can be mutated through the same persistence/analyzer-rebuild
seam the existing fields use. This unblocks the M1 Settings UI (phases 02–03),
which will bind controls to these methods. Pure logic, fully unit-testable.

## Architecture references

Read before starting:

- `docs/architecture.md#settings-ownership` — the two side-effect classes
  (analyzer-affecting vs notifier-only). This is the load-bearing distinction
  for this phase: getting a method in the wrong class is the one bug to avoid.

## Pre-flight

1. Read `docs/dev/STANDARDS.md` top to bottom.
2. Read the architecture reference above.
3. Read this entire phase doc before touching any code.
4. Confirm the repo is on a clean branch with no uncommitted changes.

## Current state

`Sources/NoSlouch/PostureViewModel.swift` already has mutation methods for four
of the seven settings fields. They fall into two shapes.

**Notifier-only fields** — setter only persists (lines 135–148):

```swift
func updateSoundEnabled(_ enabled: Bool) {
  settings.soundEnabled = enabled
  settings.save(to: settingsDefaults)
}

func updateAlertCooldown(_ cooldown: Double) {
  settings.alertCooldownSeconds = cooldown
  settings.save(to: settingsDefaults)
}
```

**Analyzer-affecting fields** — setter persists **and** rebuilds the analyzer,
via the existing private helper (lines 130–143, 291–298):

```swift
func updateThreshold(_ threshold: Double) {
  settings.thresholdDegrees = threshold
  saveSettingsAndResetAnalyzer()
}

func updateInvertedPitch(_ enabled: Bool) {
  settings.invertedPitch = enabled
  saveSettingsAndResetAnalyzer()
}

private func saveSettingsAndResetAnalyzer() {
  settings.save(to: settingsDefaults)
  analyzer = Self.makeAnalyzer(settings: settings)
  postureState = analyzer.state
  lastCalibratedPitch = nil
  canCalibrate = latestPitch != nil
  refreshStatus()
}
```

`makeAnalyzer` (lines 323–330) reads `thresholdDegrees`, `holdSeconds`,
`recoverSeconds`, `invertedPitch`. So `holdSeconds` and `recoverSeconds` are
**analyzer-affecting**. `speechEnabled` is read only by `PostureNotifier`, never
by the analyzer, so it is **notifier-only**.

The three fields with no mutation method today: `speechEnabled`, `holdSeconds`,
`recoverSeconds`.

## Spec

1. **Add `updateSpeechEnabled(_:)`** — in `Sources/NoSlouch/PostureViewModel.swift`,
   add a method that sets `settings.speechEnabled` and persists only (the
   notifier-only shape — mirror `updateSoundEnabled`). Do **not** rebuild the
   analyzer; `speechEnabled` is not an analyzer input.

2. **Add `updateHoldSeconds(_:)`** — in the same file, add a method that sets
   `settings.holdSeconds` and calls `saveSettingsAndResetAnalyzer()` (the
   analyzer-affecting shape — mirror `updateThreshold`). `holdSeconds` is a
   `makeAnalyzer` input, so the analyzer must be rebuilt.

3. **Add `updateRecoverSeconds(_:)`** — in the same file, add a method that sets
   `settings.recoverSeconds` and calls `saveSettingsAndResetAnalyzer()` (same
   analyzer-affecting shape). `recoverSeconds` is also a `makeAnalyzer` input.

Place the three methods alongside the existing `update*` methods (after
`updateAlertCooldown`, before `requestNotifications`), keeping the file's
ordering coherent. Use the same signatures as the existing setters
(`Double` for the two durations, `Bool` for speech).

## Acceptance criteria

- [ ] `make build` succeeds with zero new warnings.
- [ ] `make lint` passes.
- [ ] `make test` passes (existing + new tests).
- [ ] Test `testSpeechEnabledSettingPersists` passes.
- [ ] Test `testHoldSecondsUpdatePersistsAndRebuildsAnalyzer` passes.
- [ ] Test `testRecoverSecondsSettingPersists` passes.

## Test plan

Add these to `Tests/NoSlouchTests/PostureViewModelTests.swift`, following the
existing `testAlertCooldownSettingPersists` pattern (lines 166–189): construct a
ViewModel with an isolated `UserDefaults` (`isolatedDefaults()`) passed as
**both** `historyStore` defaults and `settingsDefaults`, call the new method,
then assert `AppSettings.load(from: defaults)` reflects the change.

- `testSpeechEnabledSettingPersists` in `PostureViewModelTests.swift` — calls
  `viewModel.updateSpeechEnabled(true)`, asserts
  `AppSettings.load(from: defaults).speechEnabled == true`.
- `testHoldSecondsUpdatePersistsAndRebuildsAnalyzer` in the same file — calls
  `viewModel.updateHoldSeconds(2.0)`, asserts
  `AppSettings.load(from: defaults).holdSeconds == 2.0`. Because the
  analyzer-affecting shape clears calibration, also assert
  `viewModel.lastCalibratedPitch == nil` after the call (this is the observable
  signal that `saveSettingsAndResetAnalyzer()` ran, distinguishing it from the
  notifier-only shape).
- `testRecoverSecondsSettingPersists` in the same file — calls
  `viewModel.updateRecoverSeconds(2.5)`, asserts
  `AppSettings.load(from: defaults).recoverSeconds == 2.5`.

The fakes (`FakeHeadMotionProvider`, `FakeAudioOutputMonitor`,
`FakePostureNotifier`) and `isolatedDefaults()` / `drainMainQueue()` helpers
already exist at the bottom of the test file — reuse them, do not redefine.

## End-to-end verification

Not applicable — phase ships no runtime-loadable artifact. The change is three
ViewModel methods exercised by unit tests; no checked-in file, CLI behavior, or
config is involved. (The Settings UI that calls these methods arrives in
phase-02.)

## Authorizations

None.

## Out of scope

- **No UI.** Do not add a Settings scene, a SettingsView, or any control to
  `MenuBarView`. That is phase-02/03. This phase only adds ViewModel methods and
  their tests.
- **No new validation or clamping.** The existing setters do not clamp; mirror
  them exactly. `AppSettings.load` already guards non-positive durations at load
  time. Adding range checks here is out of scope (STANDARDS §2.2).
- **No changes to `AppSettings`, `PostureAnalyzer`, or `makeAnalyzer`.** All
  three fields already exist and are already read by the analyzer/notifier.
- **No refactor of the existing `update*` methods.**

## Update Log

(Filled in by the executor. See WORKFLOW.md § "Update Log entries".)

<!-- entries appended below this line -->

### Update — 2026-06-29 05:43

**Added three `update<Field>` methods to `PostureViewModel` and their tests.**

- Added `updateSpeechEnabled(_:)` (notifier-only shape, persists only).
- Added `updateHoldSeconds(_:)` (analyzer-affecting, persists + rebuilds analyzer).
- Added `updateRecoverSeconds(_:)` (analyzer-affecting, persists + rebuilds analyzer).
- Added three corresponding tests: `testSpeechEnabledSettingPersists`,
  `testHoldSecondsUpdatePersistsAndRebuildsAnalyzer`,
  `testRecoverSecondsSettingPersists`.
- All three methods mirror the existing patterns exactly; no refactoring of
  existing code.

**Verification:**
- `make lint` passed (swift format lint --recursive --strict).
- `make build` succeeded with zero warnings.
- `make test` passed: 28 tests executed, 0 failures. All three new tests pass.
- End-to-end verification: N/A (phase ships no runtime-loadable artifact;
  methods exercised by unit tests only).

**Files changed:**
- `Sources/NoSlouch/PostureViewModel.swift` — added 3 update methods (+15 lines)
- `Tests/NoSlouchTests/PostureViewModelTests.swift` — added 3 tests (+72 lines)
- `docs/dev/milestones/M1-settings-ui/phase-01-viewmodel-settings-mutations.md` — status todo→review
- `docs/dev/milestones/M1-settings-ui/README.md` — phase 01 status todo→review
