# Phase 02: Settings scene + SettingsView

**Milestone:** M1 — Settings/Preferences UI
**Status:** review
**Depends on:** phase-01
**Estimated diff:** ~120 lines
**Tags:** language=swift, kind=feature, size=m

## Goal

Add a standard macOS Settings window (⌘,) to NoSlouch that exposes all seven
`AppSettings` fields in a `Form`, bound to the `PostureViewModel.update<Field>`
methods completed in phase-01. Add a "Settings…" affordance to the menu-bar
popover that opens it. This is the first phase where the three currently-hidden
fields (`speechEnabled`, `holdSeconds`, `recoverSeconds`) become user-editable.

## Architecture references

Read before starting:

- `docs/architecture.md#settings-ownership` — every control binds to a
  `update<Field>` method; the UI never writes `AppSettings` or UserDefaults
  directly.
- `docs/architecture.md#3-output-persistence-ui` — the UI layer; NoSlouch is a
  `MenuBarExtra` app with `.window` style and no Dock icon.

## Pre-flight

1. Read `docs/dev/STANDARDS.md` top to bottom.
2. Read the architecture references above.
3. Read this entire phase doc before touching any code.
4. Confirm the repo is on a clean branch with no uncommitted changes.

## Current state

`Sources/NoSlouch/NoSlouchApp.swift` (the entry point) owns the single
`PostureViewModel` and has one scene:

```swift
@main
struct NoSlouchApp: App {
  @StateObject private var viewModel = PostureViewModel()

  var body: some Scene {
    MenuBarExtra("NoSlouch", systemImage: "figure.stand") {
      MenuBarView(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)
  }
}
```

`Sources/NoSlouch/MenuBarView.swift` already binds controls to the ViewModel
using the get/set `Binding` pattern. This is the **exact pattern to reuse** in
`SettingsView` — quote, lines 41–73:

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

Toggle(
  "Sound",
  isOn: Binding(
    get: { viewModel.settings.soundEnabled },
    set: { viewModel.updateSoundEnabled($0) }
  ))
```

After phase-01, `PostureViewModel` has an `update<Field>` method for **all
seven** fields. The full set, with the binding each control must call:

| Field | ViewModel method | Control | Suggested range/step |
|---|---|---|---|
| `thresholdDegrees` | `updateThreshold(_:)` | Stepper | `5...30` step `1`, `%.0f` deg |
| `holdSeconds` | `updateHoldSeconds(_:)` | Stepper | `1...10` step `0.5`, `%.1f` sec |
| `recoverSeconds` | `updateRecoverSeconds(_:)` | Stepper | `0.5...5` step `0.5`, `%.1f` sec |
| `alertCooldownSeconds` | `updateAlertCooldown(_:)` | Stepper | `10...300` step `10`, `%.0f` sec |
| `soundEnabled` | `updateSoundEnabled(_:)` | Toggle | — |
| `speechEnabled` | `updateSpeechEnabled(_:)` | Toggle | — |
| `invertedPitch` | `updateInvertedPitch(_:)` | Toggle | — |

The ranges/steps are suggestions; pick sensible values. What is pinned: every
field is editable and its control binds to the named method.

## Reference: SwiftUI Settings scene + SettingsLink (verified macOS 14 API)

The executor has no web access; this is the verified API for this phase.

- `Settings { SettingsView() }` is a `Scene` that gives the app the standard
  macOS Settings window, opened with ⌘, or the app menu's "Settings…" item.
  Add it as a **sibling scene** to the existing `MenuBarExtra` in
  `NoSlouchApp.body`.
- `SettingsLink { Label }` (macOS 14.0+) is a `View` that opens that Settings
  scene when clicked. Use it inside `MenuBarView` for the open affordance:

  ```swift
  SettingsLink {
    Text("Settings…")
  }
  ```

- **Gotcha — why `SettingsLink` works here:** `SettingsLink` is documented as
  unreliable inside a **menu-based** `MenuBarExtra`. NoSlouch's `MenuBarExtra`
  uses `.menuBarExtraStyle(.window)` (a window-based extra, see Current state
  above), where `SettingsLink` works directly. Do **not** add the legacy
  `NSApp.sendAction(Selector(("showSettingsWindow:")), …)` hack or any
  third-party access shim — neither is needed and `NSApp.sendAction` was
  removed for this purpose in macOS 14.

## Spec

1. **Create `Sources/NoSlouch/SettingsView.swift`** — a new SwiftUI `View`
   named `SettingsView` taking `@ObservedObject var viewModel: PostureViewModel`
   (mirror `MenuBarView`'s declaration, line 5). Its body is a `Form`
   presenting all seven fields from the table above, each bound to its
   `update<Field>` method via the get/set `Binding` pattern quoted in Current
   state. Group related controls with `Section`s if it reads better (e.g.
   "Detection" for threshold/hold/recover/invert, "Alerts" for
   cooldown/sound/speech) — grouping is your call. Give the form a reasonable
   fixed width (the menu popover uses `.frame(width: 260)`; a settings window
   can be wider, e.g. `~340`).

2. **Add the `Settings` scene** — in `Sources/NoSlouch/NoSlouchApp.swift`, add
   `Settings { SettingsView(viewModel: viewModel) }` as a sibling scene after
   the `MenuBarExtra` block (same `viewModel` instance — it is already in
   scope). Do not change the `MenuBarExtra` block itself.

3. **Add the open affordance** — in `Sources/NoSlouch/MenuBarView.swift`, add a
   `SettingsLink { Text("Settings…") }` to the popover, placed in the lower
   action area (near the existing `Quit` button is fine). This is purely
   additive; do not remove or move the existing inline controls in this phase.

## Acceptance criteria

- [ ] `make build` succeeds with zero new warnings.
- [ ] `make lint` passes.
- [ ] `make test` passes (the existing 28 tests stay green; no new tests — see
      Test plan).
- [ ] `Sources/NoSlouch/SettingsView.swift` exists, declares `SettingsView`, and
      its body references all seven `update<Field>` methods
      (`updateThreshold`, `updateHoldSeconds`, `updateRecoverSeconds`,
      `updateAlertCooldown`, `updateSoundEnabled`, `updateSpeechEnabled`,
      `updateInvertedPitch`).
- [ ] `NoSlouchApp.swift` contains a `Settings {` scene rendering
      `SettingsView(viewModel: viewModel)`.
- [ ] `MenuBarView.swift` contains a `SettingsLink`.

## Test plan

No new unit tests. SwiftUI view bodies are exempt from unit testing per
STANDARDS §3.2 — the behavior behind every control (the `update<Field>`
methods) is already covered by `PostureViewModelTests` from phase-01. Do **not**
fabricate view-snapshot or rendering tests; they would be brittle and are out of
scope. The verification for this phase is build + lint green and the structural
checks in Acceptance criteria.

## End-to-end verification

This phase ships a runtime artifact (the Settings window) but the executor is
headless and cannot drive the GUI. Verify what is checkable without a display:

- `make build` succeeds — quote the final build line.
- Confirm by reading the source that the three artifacts exist: the `Settings`
  scene in `NoSlouchApp.swift`, `SettingsView` with all seven bindings, and the
  `SettingsLink` in `MenuBarView.swift`.

Live GUI verification (launch via `make run`, press ⌘, , confirm the window
opens and each control persists) is a human step performed at review — note in
your completion entry that it is deferred to the human.

## Authorizations

None. (No new dependencies — SwiftUI only. No build-config changes.)

## Out of scope

- **Do not remove or relocate the inline controls in `MenuBarView`.** Slimming
  the popover down to status + primary actions is phase-03. Temporary
  duplication (a control in both the popover and the Settings window, both
  bound to the same method) is expected and harmless this phase.
- **No `@Environment(\.openSettings)` programmatic plumbing, no third-party
  settings-access package, no `NSApp.sendAction` legacy hack.** `SettingsLink`
  is sufficient.
- **No changes to `PostureViewModel`, `AppSettings`, or any non-UI file.** All
  seven `update<Field>` methods already exist.
- **No new settings fields.** Only surface the seven that exist.

## Update Log

(Filled in by the executor. See WORKFLOW.md § "Update Log entries".)

<!-- entries appended below this line -->

### Update — 2026-06-28

**Executor run (qwen3.6:35b-mlx, 63 turns) + architect takeover.**

Executor completed all three tasks:
- Created `Sources/NoSlouch/SettingsView.swift` with all seven `update<Field>` bindings, two sections (Detection, Alerts), `.frame(width: 340)`.
- Added `Settings { SettingsView(viewModel: viewModel) }` scene to `NoSlouchApp.swift`.
- Added `SettingsLink { Text("Settings…") }` to `MenuBarView.swift`.

Executor hard-failed (governor: 6× identical `read_file` on `MenuBarView.swift`). Root cause: executor dropped the VStack closing `}` when inserting `SettingsLink`, causing `.padding`/`.frame` to attach to `Button` rather than `VStack`. Architect corrected the brace structure (3-line fix).

**Verification (architect):**
- `make lint` passed (swift format lint --recursive --strict).
- `make build` succeeded with zero warnings.
- `make test` passed: 28 tests executed, 0 failures.
- GUI verification (open Settings window, confirm each control persists) deferred to human at review — `make run`, press ⌘,.

**Files changed:**
- `Sources/NoSlouch/SettingsView.swift` — new file, 78 lines
- `Sources/NoSlouch/NoSlouchApp.swift` — +4 lines (Settings scene)
- `Sources/NoSlouch/MenuBarView.swift` — +5 -2 lines (SettingsLink + brace fix)
