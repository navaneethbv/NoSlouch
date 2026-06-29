# M1 — Settings/Preferences UI

**Goal:** Give NoSlouch a dedicated Settings window exposing every `AppSettings`
field, replacing the controls crammed into the menu-bar popover.

**Status:** done

**Depends on:** none

**Exit criteria:**
- All seven `AppSettings` fields are user-editable through the UI (today
  `speechEnabled`, `holdSeconds`, `recoverSeconds` have no control at all).
- A standard macOS Settings window (⌘,) opens from the menu bar.
- The menu-bar popover is slimmed to status + primary actions; per-setting
  controls live in the Settings window.
- `make build`, `make lint`, `make test` all pass.

## Architecture references

- `docs/architecture.md#settings-ownership` — the `update<Field>` seam and the
  analyzer-affecting vs notifier-only split.
- `docs/architecture.md#3-output-persistence-ui` — where the UI layer sits.

## Phases

| #  | Phase                                                                                | Status |
|----|--------------------------------------------------------------------------------------|--------|
| 01 | ViewModel settings-mutation completeness ([phase-01-viewmodel-settings-mutations.md](phase-01-viewmodel-settings-mutations.md)) | done |
| 02 | Settings scene + SettingsView ([phase-02-settings-scene-and-view.md](phase-02-settings-scene-and-view.md)) | done |
| 03 | Slim down MenuBarView ([phase-03-slim-menubar.md](phase-03-slim-menubar.md)) | done |

Phase 03 is the final in-scope phase of M1. When it lands, all M1 exit criteria
are met and the milestone reaches a human-gated boundary (close via
`/rexymcp:architect`).

## Notes

The pure-logic ViewModel work (phase-01) is sequenced first because it is the
only fully unit-testable slice of M1 — the SwiftUI phases that follow are
verified through the ViewModel methods this phase completes. `speechEnabled`,
`holdSeconds`, and `recoverSeconds` already exist in `AppSettings` and are read
by `PostureViewModel.makeAnalyzer` / `PostureNotifier`; they simply have no
mutation method or UI yet.

## M1 retrospective — 2026-06-29

**Outcome:** all four exit criteria met. All seven `AppSettings` fields are now
user-editable (the three previously-hidden ones — `speechEnabled`,
`holdSeconds`, `recoverSeconds` — gained both an `update<Field>` method and a
control); a standard macOS Settings window opens via ⌘, and the `SettingsLink`
in the popover; the popover is slimmed to status + primary actions; `make
build` / `make lint` / `make test` all pass (28 tests green).

**Phase ledger:**

| Phase | Verdict | Bounces | Notes |
|---|---|---|---|
| 01 ViewModel settings-mutation completeness | approved_first_try | none | Pure ViewModel work; clean. |
| 02 Settings scene + SettingsView | escalated | none (governor hard-fail → architect takeover) | Executor completed all 3 tasks but dropped the `VStack` closing brace inserting `SettingsLink`, re-attaching `.padding`/`.frame` to `Button`; then looped re-reading the file and tripped the identical-call governor. Architect applied a 3-line brace fix. |
| 03 Slim down MenuBarView | approved_first_try | none | Same brace-sensitive file as phase-02. Pre-injected the **entire** target file (not just the lines to remove) plus an explicit brace gotcha quoting the phase-02 failure. Executor passed first try in 29 turns, no governor fire. |

**Calibration assessment (one = data, two = trend, three = fold):**

- **Dropped container-closing braces in nested SwiftUI edits** — one occurrence
  (phase-02). The mitigation (pre-inject the full enclosing container block, or
  the whole file for a small view) was applied in phase-03 and worked first
  try. This is **calibration data, not a fold**: a single failure plus one
  successful preventive application is not the two occurrences the threshold
  requires. **Held for recurrence; `WORKFLOW.md` and `STANDARDS.md` are
  unchanged.** If a future SwiftUI-container phase drops a brace despite
  full-block pre-injection, that is the second occurrence and the
  "pre-inject the full enclosing block for container edits" discipline should
  be folded into `WORKFLOW.md` § pre-injection.

- **Telemetry disabled** — all three verdicts went unrecorded to the scorecard
  (`[telemetry] dir` is unset in `rexymcp.toml`). Not a workflow defect, but it
  means cross-model calibration data is not accumulating. If the executor model
  is ever compared or swapped, enable telemetry first.

**No template or standards folds this milestone.** The one candidate pattern is
held at one occurrence per the calibration rule.

**Deferred to human (not blocking close):** live GUI smoke test of the Settings
window and the slimmed popover — `make run`, press ⌘, , confirm each control
persists across restart and the popover shows only status + actions. Documented
in the phase-02 and phase-03 review verdicts.

**Future work** beyond M1 (deviation in notifications, device name in status,
launch at login, richer session stats, live chart, sound picker) is tracked in
`MVP.md` for M2+ scoping. The next milestone is **not** yet chosen — that is the
next human decision.
