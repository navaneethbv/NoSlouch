# Phase 03: Slim down MenuBarView

**Milestone:** M1 — Settings/Preferences UI
**Status:** review
**Depends on:** phase-02
**Estimated diff:** ~33 lines (removals)
**Tags:** language=swift, kind=refactor, size=s

## Goal

Remove the four per-setting controls from the menu-bar popover now that the
Settings window (phase-02) owns them. The popover is left with status readouts
plus primary actions only. This completes M1's third exit criterion ("the
menu-bar popover is slimmed to status + primary actions; per-setting controls
live in the Settings window").

## Architecture references

Read before starting:

- `docs/architecture.md#settings-ownership` — the per-setting controls being
  removed here are duplicated in `SettingsView`; both bind to the same
  `update<Field>` methods, so removing them from the popover loses no
  functionality.
- `docs/architecture.md#3-output-persistence-ui` — the popover is the
  `MenuBarExtra`'s window content; this phase only thins it.

## Pre-flight

1. Read `docs/dev/STANDARDS.md` top to bottom.
2. Read the architecture references above.
3. Read this entire phase doc before touching any code.
4. Confirm the repo is on a clean branch with no uncommitted changes.

## Current state

`Sources/NoSlouch/MenuBarView.swift` is the popover. Its `body` is a single
`VStack` containing, in order: a title, the status text, two conditional pitch
readouts, a `Divider`, an `HStack` of Start/Stop + Calibrate, **four
per-setting controls**, a conditional "Enable Notifications" button, a second
`Divider`, the session summary, a `SettingsLink`, and a `Quit` button. The whole
`VStack` carries `.padding(12).frame(width: 260)`.

The **four controls to remove** are these consecutive blocks (a Threshold
`Stepper`, a Reminder/cooldown `Stepper`, a Sound `Toggle`, and an Invert-pitch
`Toggle`), currently between the Start/Calibrate `HStack` and the "Enable
Notifications" button:

```swift
Stepper(
  "Threshold: \(viewModel.settings.thresholdDegrees, specifier: "%.0f") deg",
  value: Binding(
    get: { viewModel.settings.thresholdDegrees },
    set: { viewModel.updateThreshold($0) }
  ),
  in: 5...30,
  step: 1
)

Stepper(
  "Reminder: \(viewModel.settings.alertCooldownSeconds, specifier: "%.0f") sec",
  value: Binding(
    get: { viewModel.settings.alertCooldownSeconds },
    set: { viewModel.updateAlertCooldown($0) }
  ),
  in: 10...300,
  step: 10
)

Toggle(
  "Sound",
  isOn: Binding(
    get: { viewModel.settings.soundEnabled },
    set: { viewModel.updateSoundEnabled($0) }
  ))

Toggle(
  "Invert pitch",
  isOn: Binding(
    get: { viewModel.settings.invertedPitch },
    set: { viewModel.updateInvertedPitch($0) }
  ))
```

Everything else in the file stays.

## Spec

1. **Remove the four per-setting controls** — in `Sources/NoSlouch/MenuBarView.swift`,
   delete the two `Stepper` blocks (Threshold, Reminder) and the two `Toggle`
   blocks (Sound, Invert pitch) quoted in Current state, plus the blank lines
   that separated them. Change nothing else: keep the title, status text, both
   pitch readouts, both `Divider`s, the Start/Calibrate `HStack`, the
   conditional "Enable Notifications" button, the session summary, the
   `SettingsLink`, the `Quit` button, and the `.padding(12).frame(width: 260)`
   modifiers exactly as they are.

The file after this change should read exactly:

```swift
import AppKit
import SwiftUI

struct MenuBarView: View {
  @ObservedObject var viewModel: PostureViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("NoSlouch")
        .font(.headline)

      Text(viewModel.statusText)
        .foregroundStyle(viewModel.postureState == .bad ? .red : .secondary)

      if let pitch = viewModel.currentPitch {
        Text("Pitch: \(pitch, specifier: "%.1f") deg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let calibratedPitch = viewModel.lastCalibratedPitch {
        Text("Calibrated: \(calibratedPitch, specifier: "%.1f") deg")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      HStack {
        Button(viewModel.isMonitoring ? "Stop" : "Start") {
          viewModel.toggleMonitoring()
        }
        .keyboardShortcut(.defaultAction)

        Button("Calibrate") {
          viewModel.calibrate()
        }
        .disabled(!viewModel.canCalibrate)
      }

      if !viewModel.notificationsEnabled {
        Button("Enable Notifications") {
          viewModel.requestNotifications()
        }
      }

      Divider()

      Text(viewModel.sessionSummary)
        .font(.caption)
        .foregroundStyle(.secondary)

      SettingsLink {
        Text("Settings…")
      }

      Button("Quit") {
        viewModel.stopMonitoring()
        NSApplication.shared.terminate(nil)
      }
    }
    .padding(12)
    .frame(width: 260)
  }
}
```

**Gotcha — brace structure.** Phase-02 hard-failed on this exact file by
dropping the `VStack`'s closing `}` while editing, which silently re-attached
`.padding`/`.frame` to the `Button` instead of the `VStack`. After your edit,
the structure must be: every control is a direct child of the `VStack`, the
`VStack`'s `{ … }` closes on its own line, and `.padding(12).frame(width: 260)`
sit on the `VStack` (two lines below the closing brace of `Button("Quit")`).
Writing the whole file to match the block above is the safe path; `make build`
will fail loudly if the braces are wrong, so build before reporting done.

## Acceptance criteria

- [ ] `make build` succeeds with zero new warnings.
- [ ] `make lint` passes.
- [ ] `make test` passes (the existing 28 tests stay green; no new tests).
- [ ] `MenuBarView.swift` no longer references `updateThreshold`,
      `updateAlertCooldown`, `updateSoundEnabled`, or `updateInvertedPitch`
      (grep for each returns no match in that file).
- [ ] `MenuBarView.swift` still contains the `SettingsLink`, the
      `toggleMonitoring`/`calibrate` buttons, the `requestNotifications`
      button, and the `Quit` button (grep confirms each remains).
- [ ] `MenuBarView.swift` contains exactly one `.frame(width: 260)` attached to
      the `VStack` (the popover still renders at its fixed width).

## Test plan

No new unit tests. `MenuBarView` is a SwiftUI view body, exempt from unit
testing per STANDARDS §3.2 — the behavior behind every control that remains
(`toggleMonitoring`, `calibrate`, `requestNotifications`) is already covered by
`PostureViewModelTests`, and the removed controls' methods stay covered there
too (they are still called from `SettingsView`). Do **not** add view-snapshot
or rendering tests. Verification is build + lint green plus the structural
greps in Acceptance criteria.

## End-to-end verification

This phase ships a runtime artifact (the slimmed popover) but the executor is
headless and cannot drive the GUI. Verify what is checkable without a display:

- `make build` succeeds — quote the final build line.
- Grep `MenuBarView.swift` to confirm the four removed bindings are gone and
  the kept actions (`SettingsLink`, `toggleMonitoring`, `calibrate`,
  `requestNotifications`, `Quit`) remain.

Live GUI verification (launch via `make run`, open the popover, confirm it now
shows only status + actions and the per-setting controls are gone) is a human
step performed at review — note in your completion entry that it is deferred to
the human.

## Authorizations

None. (No new dependencies, no build-config changes, no new files.)

## Out of scope

- **Do not touch `SettingsView.swift`, `NoSlouchApp.swift`, `PostureViewModel.swift`,
  or `AppSettings.swift`.** The `update<Field>` methods stay; they are still
  used by `SettingsView`. This phase only deletes UI from the popover.
- **Do not remove or relocate the "Enable Notifications" button.** It is a
  permission call-to-action, not a per-setting control, and it is not
  duplicated in `SettingsView`. It stays as a primary action.
- **Do not remove the status readouts** (title, status text, pitch, calibrated
  pitch, session summary). Those are the popover's reason to exist.
- **Do not restyle, reorder, or "improve" the remaining controls.** The only
  change is the removal of the four settings controls.
- **No new settings, no new controls, no new tests.**

## Update Log

(Filled in by the executor. See WORKFLOW.md § "Update Log entries".)

<!-- entries appended below this line -->

### Update — 2026-06-29 07:15 (complete)

**What I did:** Replaced `MenuBarView.swift` with the slimmed version that
removes the four per-setting controls (Threshold Stepper, Reminder Stepper,
Sound Toggle, Invert pitch Toggle). The file now contains only status readouts
and primary actions.

**Verification:**
- `make build` — Build complete! (0.94s), zero warnings.
- `make lint` — passed with zero issues.
- `make test` — 28 tests executed, 0 failures.
- Grep for `updateThreshold|updateAlertCooldown|updateSoundEnabled|updateInvertedPitch` in `MenuBarView.swift` — 0 matches (all removed).
- Grep for `SettingsLink|toggleMonitoring|calibrate|requestNotifications|Quit` in `MenuBarView.swift` — 7 matches (all retained).

**Files changed:** `Sources/NoSlouch/MenuBarView.swift` (replaced entirely),
phase doc status flipped to review, README phase table updated.

**Notes for review:** Live GUI verification deferred to human reviewer: launch
`make run`, open the popover, confirm only status + primary actions remain and
per-setting controls are gone.
