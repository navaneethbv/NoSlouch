# M1 — Settings/Preferences UI

**Goal:** Give NoSlouch a dedicated Settings window exposing every `AppSettings`
field, replacing the controls crammed into the menu-bar popover.

**Status:** in-progress

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
| 03 | Slim down MenuBarView ([phase-03-slim-menubar.md](phase-03-slim-menubar.md)) | review |

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
