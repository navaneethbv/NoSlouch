# NoSlouch — Improvements & Next-Features Plan

> **Purpose.** This is a self-contained, hand-off-to-an-LLM implementation plan.
> Every feature below names the **real files, symbols, and conventions** it
> touches so an implementing agent can execute it without re-discovering the
> architecture. Read the "Ground rules" section first — it encodes the
> invariants that, if violated, will silently break calibration, persistence, or
> the test suite.
>
> **Status as of writing:** M1–M6 are all shipped (see `README.md`). The codebase
> is a dependency-free macOS 14+ menu-bar app. No milestone is currently active
> (`docs/dev/NEXT.md`).
>
> **Author's note on scope:** this file deliberately over-specifies. Treat each
> feature as a candidate phase. Do **not** attempt them all in one pass — pick a
> milestone grouping from §7 and ship it end-to-end (DoD in
> `docs/dev/STANDARDS.md`) before starting the next.

---

> ## ⚠️ SYNC UPDATE — PR #14 "feat(M7)" merged (origin/main `ff7295d`)
>
> The merge titled *"snooze/auto-pause countdown in status text"* actually shipped
> **five** items from this plan plus two unplanned ones. Statuses below are now
> **stale in places**; this block is the authoritative reconciliation. The
> codebase was pulled (`6bc574a..ff7295d`, fast-forward) and **all 72 tests pass**
> (`make test` green; the trailing non-zero exit is the swift-testing 0-tests
> toolchain quirk, not a failure).
>
> **Now DONE / no longer "future work":**
> - **B1** (snooze/pause countdown) — shipped. `minutesLeft(until:)` +
>   `"Nudges snoozed · N min left"` / `"… paused · N min left"`, driven off
>   `lastReadingAt`. ✔ Also resolves the fixed-"10 min" text noted in §10.3.
> - **C1** (intraday heatmap) — shipped. New `HourPostureStat`,
>   `PostureHistoryStore.hourlyStats`, daily-→hourly migration, and a clickable
>   per-day hourly slouch chart in `HistoryView`. ⚠️ See **NB-8/NB-9** for issues.
> - **G1 / BUG-5** (callbacks on main) — **FIXED**. All `AirPodsMotionProvider`
>   callbacks now dispatch to `DispatchQueue.main`.
> - **BUG-4** (data race on `lastReadingAt`) — **FIXED** as a side effect (the
>   throttle now runs on main). ⚠️ Introduced a minor perf regression — see **NB-10**.
> - **A4** (AirPods battery monitor) — shipped **despite the high-risk flag**.
>   New `AirPodsBatteryMonitor` + popover widget. ⚠️ Major concerns — **NB-4..NB-7**.
> - **A2** (auto-drift self-calibration) — shipped as the **silent-EMA variant
>   this plan explicitly cautioned against** (±2° bound). ⚠️ See **NB-1..NB-3**.
>
> **Still open (unchanged by PR #14):** BUG-1, BUG-2, BUG-3, BUG-6, BUG-7, BUG-8,
> BUG-9, and all of §9 (token/repo optimization) except the milestone-doc churn.
>
> **New issues introduced by PR #14:** see **§10.5** (NB-1 … NB-10).
>
> Milestone docs now show **M7 complete** (`docs/dev/NEXT.md`); battery + auto-drift
> were "deferred pending a design decision" in the phase docs yet were merged
> anyway — a process gap worth noting.

## Table of contents

1. [Ground rules every implementing agent MUST follow](#1-ground-rules)
2. [Current-state snapshot (what already exists)](#2-current-state-snapshot)
3. [The naming question: does "NoSlouch" still fit?](#3-the-naming-question)
4. [Feature catalog (detailed specs)](#4-feature-catalog)
   - A. [Detection & sensing](#a-detection--sensing)
   - B. [Nudges, scheduling & focus](#b-nudges-scheduling--focus)
   - C. [Analytics, history & goals](#c-analytics-history--goals)
   - D. [Wellness expansion (breaks, eyes, hydration, movement)](#d-wellness-expansion)
   - E. [Platform integration & surfaces](#e-platform-integration--surfaces)
   - F. [Onboarding, calibration & distribution](#f-onboarding-calibration--distribution)
   - G. [Engineering / robustness debt](#g-engineering--robustness-debt)
5. [Carry-over items from `suggestion.md`](#5-carry-over-items)
6. [Priority matrix (effort × impact × risk)](#6-priority-matrix)
7. [Suggested milestone sequencing (M7 → M12)](#7-suggested-milestone-sequencing)
8. [Per-feature implementation checklist template](#8-implementation-checklist-template)
9. [Repo optimization for LLM token efficiency](#9-repo-optimization-for-llm-token-efficiency)
10. [Bugs, code improvements & functionality updates](#10-bugs-code-improvements--functionality-updates)
11. [Additional feature catalog — round 2](#11-additional-feature-catalog--round-2)

---

## 1. Ground rules

These are non-negotiable invariants derived from `CLAUDE.md`,
`docs/architecture.md`, and `docs/dev/STANDARDS.md`. Any feature spec below
inherits all of them.

1. **No third-party dependencies.** Apple frameworks only (`docs/architecture.md`
   "Non-goals"). `Charts`, `ServiceManagement`, `UserNotifications`,
   `AVFoundation`, `CoreMotion`, `CoreAudio` are all already in use and fair game.
   Adding a SwiftPM dependency requires explicit principal-engineer sign-off (the
   one realistic exception is Sparkle for auto-update — flagged in F4).

2. **The settings two-tier rule.** Any new field added to `AppSettings`
   (`Sources/NoSlouch/Persistence/AppSettings.swift`) MUST:
   - be added to `Keys`, the stored properties, the `init` (with a default), the
     `load(from:)` reader, **and** the `save(to:)` writer (all five places);
   - be mutated through a dedicated `update<Field>(_:)` method on
     `PostureViewModel`;
   - be classified into exactly **one** tier:
     - **Analyzer-affecting** (changes how `SlouchEngine` classifies posture):
       the `update` method calls `saveSettingsAndResetAnalyzer()`, which **clears
       `calibratedBaselinePitch`** and rebuilds the engine. Current members:
       `thresholdDegrees`, `holdSeconds`, `recoverSeconds`, `invertedPitch`.
     - **Notifier/behavior-only** (does not change classification): the `update`
       method calls `settings.save(to: settingsDefaults)` only. Current members:
       `soundEnabled`, `speechEnabled`, `alertCooldownSeconds`, `soundName`,
       `muteInMeetings`, `breakRemindersEnabled`, `breakReminderMinutes`.
   - **Decision heuristic:** "If `SlouchEngine.init` or `calibrate` would need
     this value, it's analyzer-affecting. Otherwise notifier-only." Getting this
     wrong either wipes the user's calibration on an unrelated toggle, or fails to
     re-classify when it should.

3. **Hardware is always behind a protocol + fake.** Real implementations
   (`AirPodsMotionProvider`, `AudioOutputMonitor`, `MicrophoneMonitor`,
   `PostureNotifier`) require hardware. Their protocols
   (`HeadMotionProvider`, `AudioOutputMonitoring`, `MicrophoneMonitoring`,
   `PostureNotifying`) are injected via `PostureViewModel.init`. Every new
   external capability follows the same pattern, and `PostureViewModelTests.swift`
   gets a `Fake…` for it (see the existing fakes at the bottom of that file).

4. **Threading.** Motion callbacks arrive on a background `OperationQueue`; the
   ViewModel re-dispatches every provider closure onto `DispatchQueue.main`
   before mutating state (`bindProviders()` in `PostureViewModel.swift`). All
   `@Published` mutation happens on main. New providers MUST follow this — do not
   mutate ViewModel state off-main.

5. **`SlouchEngine` is a pure `struct` with no imports** beyond `Foundation`. It
   is the highest unit-test-priority module (`docs/architecture.md`). Keep it
   pure: no `Date()` calls inside it (timestamps are passed in), no I/O, no
   `import AppKit`. This is what makes it deterministically testable.

6. **Definition of Done** (`docs/dev/STANDARDS.md §1`): `make build` with zero new
   warnings, `make lint`, `make test` all green; new code covered by tests;
   no force-unwrap/`try!`/`fatalError()` in production paths; end-to-end
   verification quoted in the phase Update Log. Use the rexyMCP phase workflow
   (`REXYMCP.md`) — write a phase doc under `docs/dev/milestones/<MX-name>/`.

7. **Privacy is a feature.** "No analytics/telemetry of user posture data
   off-device" is an architectural non-goal. Any cloud/sync feature (E5) is a
   **deliberate architecture change** and must be called out as such, not slipped
   in.

8. **Tests use isolated UUID-named `UserDefaults` suites.** New persistence MUST
   be testable with an injected `UserDefaults` (see `PostureHistoryStore.init`'s
   `defaults:` parameter and `AppSettings.load(from:)`). Never hardcode
   `.standard` in a code path you want to test.

---

## 2. Current-state snapshot

What the app does **today** (so we don't re-propose shipped work):

| Capability | Implemented in |
|---|---|
| Slouch detection from AirPods **pitch** | `SlouchEngine.update(pitch:at:)`, `AirPodsMotionProvider` |
| Calibration + persisted baseline | `PostureViewModel.calibrate()`, `AppSettings.calibratedBaselinePitch` |
| Nudge with degree-drop message | `PostureNotifier.nudge(…, drop:)` |
| Cooldown + 3-strikes auto-pause | `PostureViewModel.maybeNudgeForBadPosture`, `nudgePauseDuration` |
| User snooze (15/30/60 min) | `PostureViewModel.snoozeNudges(for:)`, `MenuBarView` |
| Mute in meetings (mic active) | `MicrophoneMonitor`, `settings.muteInMeetings` |
| Stretch break reminders | `settings.breakRemindersEnabled/breakReminderMinutes`, `nudgeBreak` |
| Sound picker + preview + speech | `AppSettings.availableSoundNames`, `previewSound` |
| Live 60s deviation chart | `PostureChartView`, `deviationSamples` |
| Session stat cards + today's score | `MenuBarView`, `sessionGoodSeconds`/`BadSeconds`/`SlouchEvents` |
| 30-day history window | `HistoryView`, `PostureHistoryStore` (daily buckets, 90-day cap) |
| Launch at login | `setLaunchAtLogin`, `SMAppService` |
| Dynamic menu-bar icon | `menuBarSymbolName` |

**Untapped capability already in the codebase:**
- `HeadMotionReading.roll` and `.yaw` are streamed but **never consumed**
  (`SlouchEngine` reads only `pitch`). → enables A1/A2 with no new hardware code.
- `AudioOutputMonitor.deviceName` exists and is shown in status text only.
- History is stored as **daily** `DayPostureStat` buckets — no finer grain → C1
  (heatmap) requires a data-model change, not just a view.

---

## 3. The naming question

**Short answer: keep "NoSlouch" as the product name, but evolve the
positioning/tagline and reserve a rename as an optional, well-scoped task.**

### Why the question is fair

The app started as a pure slouch detector. It now also does: stretch-break
reminders, meeting-aware muting, session analytics, and a history dashboard. The
roadmap below pushes further into **eye rest (20-20-20), hydration, movement/
sit-stand, focus-aware scheduling, and goals/streaks**. At that point the product
is a **"desk wellness / ergonomics companion,"** and "NoSlouch" describes only the
hero feature, not the category. A user searching for "standing desk reminder mac"
or "eye strain break app" won't recognize "NoSlouch" as a match.

### Why keep it anyway (recommended)

1. **Posture is and should remain the hero.** Every other feature (breaks, eye
   rest, movement) is a *desk-wellness satellite* orbiting the same core sensor
   loop. A hero-feature name is a strength, not a liability, as long as posture
   stays the headline.
2. **Brand equity & memorability.** "NoSlouch" is punchy, spellable, and the
   double meaning ("don't slouch" / "no slouch = competent") is genuinely good.
3. **Rename cost is real and broad.** A true rename touches:
   - Swift target/module name, `Package.swift`, all `NoSlouch*` type/file names
     (`NoSlouchApp`, `NoSlouch.app`, `NoSlouch.entitlements`).
   - **Bundle identifier** → which changes the `SMAppService` (launch-at-login)
     registration and the UserDefaults domain → **existing users lose their
     settings, calibration, and 90-day history** unless you write a migration.
   - `UNUserNotificationCenter` identifiers (`noslouch.posture.*`,
     `noslouch.break.*`, `noslouch.paused.*`).
   - Notification copy ("NoSlouch", "NoSlouch paused"), `README.md`, all `docs/`.
   - The `com.apple.developer.coremotion.headphone-motion-data` entitlement is
     tied to the signed bundle id (re-provisioning needed for release).

   This is a multi-day, migration-bearing task with user-data-loss risk — only
   worth doing **before** any public launch, never casually after.

### Decision matrix

| Option | When it's right | Cost | Recommendation |
|---|---|---|---|
| **Keep "NoSlouch", evolve tagline** | Posture stays the hero; pre- or post-launch | ~0 (copy only) | ✅ **Default** |
| **Keep name, add a category subtitle** e.g. *"NoSlouch — Posture & Desk Wellness"* | You want discoverability without a rename | Low (App Store subtitle, README, About box) | ✅ **Do this alongside** |
| **Rename to a category-neutral brand** (e.g. *Perch, Upright, Poise, Stance, Tend, DeskWell, Ergo, Sitwell*) | You're pre-launch AND committing hard to the broader wellness category | High + migration | ⚠️ Only pre-launch, as its own phase |
| **Umbrella brand + posture sub-name** | You're building a suite | Very high | ❌ Premature |

### Concrete recommendation

1. **Now:** keep `NoSlouch`. Update the App Store/README **subtitle** to
   *"Posture & desk-wellness companion for Mac."* (Pure copy change:
   `README.md:3`, the `MenuBarView` header could gain a one-line subtitle, and
   `Info.plist` `CFBundleDisplayName` stays "NoSlouch".)
2. **If a rename is ever chosen,** treat it as a dedicated phase with this
   checklist (do NOT do it incrementally):
   - [ ] Decide new bundle id; write a one-time **UserDefaults migration** that
         copies every `settings.*`, `posture.history.dailyStats`, and
         `calibratedBaselinePitch` key from the old domain to the new one on first
         launch (and ideally `SMAppService` re-register).
   - [ ] Rename module in `Package.swift`, target dir, all `NoSlouch*` symbols.
   - [ ] Re-issue Developer ID provisioning for the headphone-motion entitlement.
   - [ ] Update all notification identifiers + copy + `docs/` + `README.md`.
   - [ ] Keep "NoSlouch" as a documented former name for support continuity.

**Bottom line:** the name still works because posture is still the point. Sell the
breadth in the *tagline*, not by burning the brand.

---

## 4. Feature catalog

Each feature uses this shape: **Why → What changes (files/symbols) → Settings tier
→ UI → Tests → Acceptance → Risks**. Difficulty is S/M/L/XL.

---

### A. Detection & sensing

#### A1. Multi-axis posture: detect head tilt (roll) and turn (yaw) — **M**

**Why.** Slouching isn't only forward head drop. Chronic lateral head tilt
("phone neck"/leaning on a hand) and sustained head turn are real ergonomic
problems, and the data is *already streaming* (`HeadMotionReading.roll/.yaw`) but
discarded.

**What changes.**
- `SlouchEngine`: generalize from a single `pitch` axis to a small set of axes.
  Two viable designs (pick one in the phase doc):
  - **(a) Composite drop:** keep one `state`, but compute deviation from baseline
    on pitch **and** |roll| (head tilt), classify `.bad` if either exceeds its
    threshold. Add `baselineRoll` to `PostureCalibration`
    (`Sources/NoSlouch/Posture/PostureCalibration.swift`).
  - **(b) Per-axis sub-states:** add an enum or struct describing *which* axis is
    off (`.forwardHead`, `.tilt`) so the nudge can say "head tilted left."
  - Recommended: start with (a) for a single threshold knob, expose roll
    sensitivity later.
- `PostureCalibration`: store `baselinePitch` **and** `baselineRoll`.
  `SlouchEngine.calibrate(pitch:roll:)`.
- `PostureViewModel.handle(_:)`: pass `reading.roll` into the engine.
- `currentDrop` stays the pitch drop; add `currentTilt` for roll deviation.

**Settings tier.** New fields `tiltDetectionEnabled: Bool`, `tiltThresholdDegrees:
Double` → **analyzer-affecting** (engine is built from them; toggling clears
baseline — acceptable, document it).

**UI.** `SettingsView` "Detection" section: a "Detect head tilt" toggle + a tilt
threshold stepper (shown only when enabled, mirroring the break-interval pattern
at `SettingsView.swift:109`). `MenuBarView` gauge could show a second mini-bar.

**Tests.** `SlouchEngineTests`: add cases mirroring the existing pitch tests but
for roll (sustained tilt → `.bad`, recovery → `.good`, below-threshold tilt stays
`.good`). This is pure-struct testing — cheap and high-value.

**Acceptance.** With tilt detection on and a calibrated baseline, a sustained
roll beyond the tilt threshold (held ≥ `holdSeconds`) transitions to `.bad`; the
notification body distinguishes tilt from forward-head (if design (b)).

**Risks.** AirPods roll readings are noisier than pitch when worn asymmetrically
(one bud seated differently). Keep tilt **off by default** and document the noise
caveat. Reuse the existing EMA smoothing (`smoothingAlpha`).

---

#### A2. Auto-drift detection / self-calibration — **M** (carried from `suggestion.md`)

**Why.** Over a long session a user sinks into the chair or the buds shift,
drifting the baseline. Today only a manual re-`calibrate()` fixes it.

**What changes.** Implement the **"suggest a recalibration"** variant (NOT a
silent moving average — see the safety note below).
- `SlouchEngine`: track a rolling estimate of mean pitch **while `state == .good`
  only**. If that estimate diverges from `baselinePitch` by > N degrees for a
  sustained window without slouch events, set a flag `suggestsRecalibration:
  Bool`.
- `PostureViewModel`: surface it as `@Published var recalibrationSuggested: Bool`;
  show a one-tap "Re-calibrate?" affordance in `MenuBarView`.

**Settings tier.** `autoDriftDetectionEnabled: Bool` → analyzer-affecting.

**Tests.** `SlouchEngineTests`: feed a slow upward baseline shift while staying
"good"; assert `suggestsRecalibration` flips after the window; assert it does
**not** flip during genuine slouching.

**Acceptance.** A 10-minute synthetic drift of +6° (good posture throughout)
raises the suggestion; a slouch event does not.

**Risks (important).** A silent slow-moving-average baseline is **dangerous** — it
drifts the baseline toward a slouched posture and masks real slouching, defeating
the app. If anyone ever implements auto-*adapt* instead of auto-*suggest*: only
adapt while `state == .good`, and hard-bound cumulative drift (e.g. ±5° total).

---

#### A3. Sensitivity presets (Gentle / Standard / Strict) — **S**

**Why.** Threshold + hold + recover are three coupled knobs most users won't tune.
A preset that sets all three is a far better default UX.

**What changes.** A `DetectionPreset` enum mapping to
`(thresholdDegrees, holdSeconds, recoverSeconds)` triples. `PostureViewModel.
applyPreset(_:)` sets all three via the analyzer-affecting path (single
`saveSettingsAndResetAnalyzer()`). "Custom" is implied when values don't match a
preset.

**Settings tier.** Drives existing analyzer-affecting fields — no new persisted
field strictly required (you can derive the selected preset from the values), but
optionally persist `detectionPreset: String` for UI state.

**UI.** A `Picker` at the top of the "Detection" section; the individual steppers
remain (collapsed under a "Custom" disclosure, optional).

**Tests.** `PostureViewModelTests`: `applyPreset(.strict)` sets the expected
triple and rebuilds the analyzer (assert `lastCalibratedPitch == nil` post-apply,
matching existing analyzer-reset semantics).

**Acceptance.** Selecting a preset updates all three steppers and persists.

---

#### A4. AirPods battery widget — **S code / HIGH risk** (carried from `suggestion.md`)

**Why.** The app requires AirPods; a tiny L/R/Case battery readout in the popover
is genuinely handy.

**Why this is risky / low priority.** There is **no supported public API** for
AirPods battery. Options are the private `BluetoothManager` framework or IOKit
hacks — both **break the "public-API-only" stance**, are brittle across macOS
versions, and create **notarization/distribution risk**. 

**Recommendation.** Defer. If pursued, isolate it behind a
`BatteryProviding` protocol with a real impl that **fails closed** (returns `nil`,
hides the widget) so an OS update can't crash the app. Treat as experimental and
never block a release on it.

---

### B. Nudges, scheduling & focus

#### B1. Active snooze / pause countdown — **S** (carried from `suggestion.md`)

**Why.** Snooze and auto-pause work, but `MenuBarView` shows static text
("Nudges snoozed") with no remaining time.

**What changes.**
- `PostureViewModel`: expose `snoozeRemaining: TimeInterval?` and
  `pauseRemaining: TimeInterval?` computed from `snoozedUntil`/`nudgesPausedUntil`
  **against the reading clock (`lastReadingAt`)**, not wall-clock, so the
  displayed remaining time matches when nudges actually resume (snooze expiry is
  evaluated against `reading.timestamp` in `handle`).
- `refreshStatus()` already builds the snooze/pause status strings — extend them:
  `"Nudges snoozed · 12 min left"`.

**UI.** `MenuBarView` status line + the "Resume nudges" button area.

**Tests.** `PostureViewModelTests`: snooze for 30 min, emit a reading 10 min
later (timestamped), assert remaining ≈ 20 min; assert it reaches 0 and clears at
expiry. Use the existing `drainMainQueue()` pattern after `motionProvider.emit()`.

**Acceptance.** Countdown decrements as readings arrive and disappears on expiry/
resume.

**Note.** Status text is currently derived; if it becomes a live ticking display
while the popover is open you may need a `Timer`/`TimelineView` — but driving it
off readings (which arrive at ~sensor rate) is sufficient and keeps the
reading-clock invariant.

---

#### B2. Quiet hours / work-schedule awareness — **M**

**Why.** Users don't want posture nudges at 11pm or on weekends. Today nudging is
active whenever monitoring is on.

**What changes.**
- New fields: `quietHoursEnabled: Bool`, `quietStartMinutes: Int`,
  `quietEndMinutes: Int` (minutes-from-midnight), and `activeDays: Set<Int>` (or a
  7-bit mask persisted as `Int`).
- `PostureViewModel.maybeNudgeForBadPosture` and the break-reminder block in
  `handle`: add an `isWithinQuietHours(at:)` guard that suppresses **outbound
  alerts** (mirror the `muteInMeetings` early-return exactly — for breaks, *defer*
  rather than drop, matching the mic logic at `PostureViewModel.swift:392`).

**Settings tier.** Notifier-only (does not affect classification). Add all to
`save`/`load`.

**UI.** `SettingsView` new "Schedule" section: enable toggle, two time pickers,
day-of-week chips.

**Tests.** `PostureViewModelTests`: inject a reading timestamped inside quiet
hours → no nudge; outside → nudge. (Timestamps are passed in, so this is
deterministic — no clock mocking needed beyond the reading timestamp.)

**Acceptance.** Nudges and breaks suppress during configured quiet windows and on
off-days; status text reflects "Quiet hours."

---

#### B3. Notification actions (Snooze / Calibrate from the banner) — **M**

**Why.** Currently a nudge is informational; the user must open the popover to
act. macOS supports actionable notifications.

**What changes.**
- `PostureNotifier`: register a `UNNotificationCategory` with actions ("Snooze
  15m", "Recalibrate") in `init`; attach `categoryIdentifier` to the posture
  `UNMutableNotificationContent`.
- Implement `userNotificationCenter(_:didReceive:withCompletionHandler:)` in the
  `UNUserNotificationCenterDelegate` extension to route taps. The handler must
  call back into the ViewModel **on main** — add a delegate/closure
  (`onNotificationAction: ((NotifierAction) -> Void)?`) on `PostureNotifying` so
  the ViewModel wires `snoozeNudges`/`calibrate`.

**Settings tier.** None (behavioral).

**Tests.** `FakePostureNotifier` gains a way to simulate an action firing; assert
the ViewModel calls the right method. Real delivery is end-to-end-verified
manually (quote it in the Update Log per DoD).

**Acceptance.** Tapping "Snooze 15m" on the banner snoozes without opening the
app.

**Risks.** Actionable notifications require the app's notification category to be
registered before the notification is posted; ordering matters. Also needs
`make bundle` (real bundle id) to behave — ad-hoc dev builds may not deliver.

---

#### B4. Calendar-aware meeting mute (complement mic-based mute) — **L**

**Why.** `muteInMeetings` relies on the mic being *active*. It misses meetings
where you're muted/listening, and fires for non-meeting mic use (voice memos).
EventKit can mute based on actual calendar events.

**What changes.** New `CalendarMonitoring` protocol + `EventKitCalendarMonitor`
real impl (requires `NSCalendarsUsageDescription` in `Info.plist` and a permission
prompt — a real privacy surface). Expose `isInMeeting: Bool`. ViewModel ORs it
with the existing mic state in the mute decision.

**Settings tier.** `muteDuringCalendarEvents: Bool` → notifier-only.

**Risks.** Adds a permission prompt and an entitlement-adjacent capability. Keep
**off by default**; mic-based mute remains the zero-permission default. Document
the new `Info.plist` key.

---

### C. Analytics, history & goals

#### C1. Intraday posture heatmap (hourly buckets) — **L** (carried from `suggestion.md`)

**Why.** `HistoryView` shows daily upright share, but users want to see *when*
posture degrades (e.g. the 3pm slump) to schedule breaks.

**What changes — this is a data-model change, not a view-only one.**
- `PostureHistoryStore` currently aggregates each session into one **daily**
  `DayPostureStat`. There is no hourly data to plot. Add an **hourly bucket**
  layer:
  - New `HourPostureStat` (hour-of-day 0–23 → good/bad seconds, slouch events),
    OR extend `DayPostureStat` with a `[24]` array of hourly tallies.
  - `PostureViewModel.finalizeSession` / `handle` must attribute accumulated
    good/bad seconds to the **hour they occurred in** (a session can span hours,
    so accumulation must bucket by `reading.timestamp`'s hour, not just session
    start). This likely means tracking per-hour accumulators in the ViewModel.
  - Bump the persisted schema; `DayPostureStat` already uses
    `decodeIfPresent`-based migration (`PostureHistoryStore.swift:39`) — follow
    that pattern so old data decodes with empty hourly buckets.
- New `IntradayHeatmapView` (GitHub-style hour grid or hour-bucketed `BarMark`).

**Settings tier.** None.

**Tests.** `PostureHistoryStoreTests`: a session spanning 14:55→15:10 attributes
seconds to hours 14 and 15 correctly; old-format JSON decodes with zeroed hourly
data (migration test).

**Acceptance.** History window gains an intraday view; a synthetic cross-hour
session shows up in two hour buckets.

**Risks.** Storage growth (hourly × 90 days). Keep it bounded; UserDefaults is
fine for this volume but consider whether this is the trigger for G3 (move to a
file-backed store).

---

#### C2. Goals, streaks & daily target — **M**

**Why.** Behavior-change apps live on streaks. Today there's a "today's upright
score" but no goal to beat or streak to protect.

**What changes.**
- `AppSettings`: `dailyUprightGoalPercent: Double` (e.g. 80%).
- New `StreakCalculator` **pure struct** (no imports — same testing tier as
  `SlouchEngine`) that, given `[DayPostureStat]` and the goal, returns current
  streak, longest streak, and whether today's goal is met.
- `PostureViewModel`: expose `currentStreak`, `goalMetToday`.

**Settings tier.** `dailyUprightGoalPercent` → notifier-only.

**UI.** A streak badge in `MenuBarView` / `HistoryView` ("🔥 5-day streak").
Optionally a celebratory notification when the daily goal is first met
(`PostureNotifier.notifyGoalMet`).

**Tests.** `StreakCalculatorTests` (new, pure): consecutive goal-met days → streak
N; a gap resets; today partial doesn't break a prior streak until day ends.

**Acceptance.** Streak increments across qualifying days and resets after a miss.

---

#### C3. Data export (CSV / JSON) — **S**

**Why.** Users (and the privacy-conscious) want their data out; useful for sharing
with a physiotherapist.

**What changes.** `PostureHistoryStore.exportCSV() -> String` (and/or JSON);
`HistoryView` "Export…" button using `NSSavePanel`. No new persisted state.

**Settings tier.** None.

**Tests.** `PostureHistoryStoreTests`: export of a known stat set yields expected
CSV rows/headers.

**Acceptance.** Export writes a valid CSV of daily stats the user can open in
Numbers/Excel.

---

#### C4. Weekly / monthly trend summaries — **S/M**

**Why.** Daily bars are noisy; a "this week vs last week" delta and a 7-day moving
average tell a clearer story.

**What changes.** Pure aggregation helpers over `dailyStats` (week/month rollups,
moving average). `HistoryView` gains a segmented control (Day / Week / Month).

**Settings tier.** None.

**Tests.** Pure aggregation tests with fixed `DayPostureStat` arrays.

**Acceptance.** Switching granularity re-buckets the chart correctly.

---

### D. Wellness expansion

> These are the features that most stretch the "NoSlouch" name (see §3). They turn
> the app into a desk-wellness companion. Each reuses the **existing nudge/break
> plumbing** (`PostureNotifier`, reminder-interval pattern).

#### D1. Eye-rest 20-20-20 reminders — **S**

**Why.** Classic ergonomic guidance: every 20 min, look 20 ft away for 20 s. Same
mechanic as break reminders, different copy/interval.

**What changes.** Generalize the break-reminder loop in `PostureViewModel.handle`
(currently a single `lastBreakNudgeMonitoredSeconds` marker) into a small list of
**recurring reminders** so eye-rest, hydration (D2), and movement (D3) all share
one engine. Concretely: a `RecurringReminder` value type
`(kind, intervalMinutes, enabled, lastFiredMonitoredSeconds)` and a loop over an
array. `PostureNotifier` gains `nudgeReminder(kind:settings:…)` with per-kind copy.

**Settings tier.** `eyeRestEnabled: Bool`, `eyeRestMinutes: Double` →
notifier-only. (When you generalize, the existing `breakReminders*` fields become
one entry in the reminder set — keep their keys for back-compat.)

**UI.** `SettingsView` "Reminders" section consolidating break + eye-rest (+ D2/D3)
as a uniform list.

**Tests.** `PostureViewModelTests`: with eye-rest at 20 min, accumulate 20 min of
monitored time (emit timestamped readings) → exactly one eye-rest nudge; verify
it **defers** under mute-in-meetings exactly like breaks do.

**Acceptance.** Independent eye-rest reminders fire on their own cadence; respect
mute and quiet hours (B2).

---

#### D2. Hydration reminders — **S**

Same `RecurringReminder` mechanic as D1, different copy ("Time for a sip of
water 💧") and interval (`hydrationEnabled`, `hydrationMinutes`, notifier-only).
Optional: a tiny daily "glasses" tally surfaced in the popover (reuses the
goal/stat card pattern). Ships essentially free once D1's generalization lands.

---

#### D3. Movement / sit-stand cycle reminders — **M**

**Why.** "You've been monitored-active for 50 min — stand up / change posture."
Distinct from a stretch break in intent (movement vs. stretch), and a natural fit
for standing-desk users.

**What changes.** Another `RecurringReminder` kind. Optionally a **sit/stand
mode** where the user logs transitions and the app reminds them to alternate;
keep v1 as a simple timed movement nudge.

**Settings tier.** `movementRemindersEnabled`, `movementMinutes` → notifier-only.

**Risk.** Reminder fatigue: with breaks + eyes + hydration + movement all on, the
user gets pinged constantly. Add a **global "minimum gap between any two
reminders"** coordinator in the ViewModel so reminders don't stack within, say,
2 minutes of each other. Spec this explicitly when D1's engine is built.

---

#### D4. Guided break/stretch content — **M**

**Why.** A break reminder that *shows a 30-second stretch* (illustrated steps,
countdown) is far more actionable than "time to stretch."

**What changes.** A lightweight `StretchRoutine` model (bundled, local — no
network) + a small SwiftUI sheet/window with a step-through + timer
(`TimelineView`/`Timer`). Triggered from the break notification action (B3) or the
popover. Content is static assets in `Resources/`.

**Settings tier.** `showGuidedStretches: Bool` → notifier-only.

**Risks.** Scope creep (content design, illustrations). Keep v1 to 2–3
text-only routines; art later.

---

### E. Platform integration & surfaces

#### E1. Notification Center / Today widget (WidgetKit) — **M/L**

**Why.** A glanceable today's-upright-% + streak widget increases stickiness.

**What changes.** A WidgetKit extension target (new target in `Package.swift` is
non-trivial for a SwiftPM-built app — may require an Xcode project or careful
bundle assembly in the `Makefile`). Shares data via an **App Group** UserDefaults
suite — which means `PostureHistoryStore`/`AppSettings` must read/write the app
group suite (already parameterized by `UserDefaults`, so injectable). 

**Risks.** Build-system complexity is the real cost here, not the Swift. The repo
currently builds with `swift build`; widgets/extensions push toward an Xcode
project. Flag as a build-infra decision before committing.

---

#### E2. Shortcuts / AppleScript / URL scheme — **S/M**

**Why.** Power users automate ("Start monitoring when I open Xcode"). App Intents
expose Start/Stop/Calibrate/Snooze to Shortcuts and Focus automations.

**What changes.** Adopt the App Intents framework: `StartMonitoringIntent`,
`SnoozeIntent`, etc., each calling the corresponding `PostureViewModel` method on
main. Alternatively a custom URL scheme (`noslouch://snooze?minutes=15`) handled
in `NoSlouchApp`.

**Settings tier.** None.

**Acceptance.** "Hey Siri, snooze NoSlouch" / a Shortcuts action works.

---

#### E3. macOS Focus / Do Not Disturb awareness — **S**

**Why.** When the system is in Do Not Disturb / a Focus, the user likely doesn't
want banner nudges (sound/speech could still be fine, or also suppressed per
preference).

**What changes.** There's no clean public API to *read* Focus state, but posting
notifications with appropriate `interruptionLevel` and letting the OS gate them is
the supported path. Set posture nudges to `.active`/`.timeSensitive` thoughtfully
in `PostureNotifier`. Optionally a setting "Respect Do Not Disturb (sound only)."

**Settings tier.** `respectDoNotDisturb: Bool` → notifier-only.

**Risks.** Reading Focus reliably is not publicly supported; lean on
`interruptionLevel` rather than trying to detect Focus.

---

#### E4. Apple Watch / iOS companion — **XL**

**Why.** Posture cues on the wrist; iPhone could host AirPods motion when the Mac
is closed. 

**Reality check.** This is a separate app, a shared Swift package for
`SlouchEngine` (it's already pure and portable — a genuine asset here), and a
sync story. **Out of scope for the near term**; noted for completeness. If pursued,
the first step is extracting `SlouchEngine` + models into a shared SwiftPM library
target.

---

#### E5. iCloud sync — **L / architecture change**

**Why.** Multi-Mac users want continuity.

**Reality check.** Directly contradicts the current non-goal "No cloud account,
sync, or remote storage" (`docs/architecture.md`). If ever done, use **CloudKit
private database** (data stays in the user's account, not on our servers), gate it
behind an explicit opt-in, and update the architecture doc's non-goals. Treat as a
deliberate, documented pivot — not a quiet addition.

---

### F. Onboarding, calibration & distribution

#### F1. First-run onboarding flow — **M** (this is roadmap M3, never shipped)

**Why.** New users face a menu-bar popover with no guidance on permissions,
AirPods setup, or calibration. `docs/architecture.md` lists this as planned M3.

**What changes.** A first-run window (gate on a `hasCompletedOnboarding` flag in
UserDefaults) that walks: (1) what the app does, (2) set AirPods as output, (3)
enable notifications (`requestNotifications`), (4) guided neutral-pitch
calibration, (5) optional launch-at-login. Reuses existing ViewModel methods —
mostly a UI/flow layer.

**Settings tier.** `hasCompletedOnboarding: Bool` (a flag, not a behavior toggle;
notifier-only path / direct UserDefaults).

**Acceptance.** First launch shows onboarding once; subsequent launches go
straight to the menu bar.

---

#### F2. Guided calibration improvements — **S**

**Why.** Calibration is a single `calibrate()` snapshot of the current pitch — if
the user isn't actually upright at that instant, the baseline is wrong.

**What changes.** A short "sit up straight… hold… 3-2-1" countdown that averages
pitch over ~2 s before calling `calibrate()`. Could live in `SlouchEngine` as a
calibration-averaging helper (keeps it pure/testable) or in the ViewModel.

**Tests.** If averaging logic goes in `SlouchEngine`, add `SlouchEngineTests`.

---

#### F3. App icon, About box, polish — **S**

`AppIcon.icns` exists; ensure it's wired in `Info.plist`/bundle. Add an About
panel (version, link, license). Low risk, good pre-release polish.

---

#### F4. Release & distribution: notarization + auto-update — **L** (roadmap M4)

**Why.** Ship to real users: Developer ID signing, notarization, a DMG, and
updates.

**What changes.**
- The `Makefile` already conditionally passes entitlements for non-ad-hoc signing
  (`SIGN_IDENTITY != -`, see `CLAUDE.md`). Add `make notarize`/`make dmg` targets
  driving `xcrun notarytool` + `create-dmg` (or hand-rolled).
- **The headphone-motion entitlement only embeds for Developer-ID-signed builds**
  — live AirPods data in a release build *requires* a Developer ID cert. This is
  the gating dependency for a real release.
- **Auto-update:** the only realistic non-Apple path is **Sparkle**, which would
  be the project's *first* third-party dependency — call this out for explicit
  sign-off, or ship via the Mac App Store instead (sandboxing implications for the
  headphone-motion entitlement must be checked).

**Risks.** Signing/notarization/entitlement provisioning is the highest external
dependency in this whole plan. Sequence it last among "ship it" work.

---

### G. Engineering / robustness debt

#### G1. Callback thread-safety consistency — **S** (carried from `suggestion.md`)

**Why.** Not a live bug (the ViewModel re-dispatches to main), but
`AirPodsMotionProvider` is half-consistent: `onError` is wrapped in
`DispatchQueue.main.async` while `onReading`/`onConnectionChanged` are not.
`AudioOutputMonitor`/`MicrophoneMonitor` already run their listeners on main.

**What changes.** Consolidate all three `AirPodsMotionProvider` callbacks onto the
main queue for a consistent end state.

**Tests.** Existing `PostureViewModelTests` continue to pass; no behavior change.

---

#### G2. Reminder-engine refactor (prerequisite for D1–D3) — **M**

**Why.** The break-reminder logic in `PostureViewModel.handle` is a single
hardcoded marker (`lastBreakNudgeMonitoredSeconds`). Adding eye-rest/hydration/
movement by copy-paste would create four parallel markers and four mute/quiet-hour
checks. Refactor **once** into a reminder set (see D1) with one place that applies
mute-in-meetings deferral, quiet hours (B2), and the global min-gap (D3 risk).

**Tests.** Re-express existing break-reminder tests against the generalized engine
to prove no regression, then add per-kind tests.

**Acceptance.** Existing break behavior is byte-for-byte preserved; new kinds plug
in via data, not new control flow.

---

#### G3. Persistence layer: consider a file-backed store — **M**

**Why.** Everything lives in UserDefaults (`AppSettings`, the history JSON blob,
calibration). That's fine today, but C1 (hourly history) and E1 (widget app group)
push volume and sharing requirements. 

**What changes (optional, triggered by C1/E1).** Move `PostureHistoryStore`'s blob
to a JSON file in Application Support (or an App Group container), keeping the same
`add`/`stats` API and the `defaults`-injectable test seam (swap for a path seam).
Keep `AppSettings` in UserDefaults (small, key-value-natural).

**Risks.** Migration of existing users' history blob. Write a one-time importer.

---

#### G4. Test coverage expansion for analyzer edge cases — **S**

`SlouchEngine` is the crown jewel and pure — cheap to test exhaustively. Add cases
for: `invertedPitch` symmetry, exactly-at-threshold boundaries, hold/recover timer
resets on flapping input, NaN/inf pitch robustness (defensive). Pure-struct, no
hardware.

---

## 5. Carry-over items

These were already enumerated in `suggestion.md` and are folded into the catalog
above so nothing is lost:

| `suggestion.md` item | Mapped to |
|---|---|
| Callback thread safety | **G1** |
| Active snooze / pause countdown | **B1** |
| Posture heatmap / intraday fatigue | **C1** |
| AirPods battery monitor | **A4** (deferred, risk-flagged) |
| Auto-drift detection / self-calibration | **A2** |

After implementing these, prune them from `suggestion.md` (that file's convention
is "outstanding improvements only").

---

## 6. Priority matrix

Effort: S(mall) / M(edium) / L(arge) / XL. Impact and risk are 1–5
(5 = highest). "Score" is a rough `impact − risk` tiebreaker, not gospel.

| ID | Feature | Effort | Impact | Risk | Notes |
|---|---|:--:|:--:|:--:|---|
| B1 | Snooze/pause countdown | S | 3 | 1 | Quick win, pure UX |
| G1 | Callback thread consistency | S | 2 | 1 | Cleanup, zero behavior change |
| A3 | Sensitivity presets | S | 4 | 1 | Big UX, tiny code |
| C3 | Data export | S | 3 | 1 | Privacy/trust win |
| D1 | Eye-rest 20-20-20 | S | 4 | 2 | Needs G2 ideally |
| G2 | Reminder-engine refactor | M | 3 | 2 | **Unlocks D1/D2/D3** |
| C2 | Goals & streaks | M | 5 | 2 | Retention driver |
| F1 | First-run onboarding | M | 4 | 2 | Roadmap M3; conversion |
| A1 | Multi-axis (tilt) detection | M | 4 | 3 | Data already streaming |
| B2 | Quiet hours / schedule | M | 4 | 2 | Stops off-hours annoyance |
| A2 | Auto-drift suggestion | M | 3 | 3 | Safety caveats |
| F2 | Guided calibration | S | 3 | 1 | Accuracy boost |
| D2 | Hydration | S | 2 | 2 | ~Free after G2 |
| D3 | Movement/sit-stand | M | 3 | 2 | Watch reminder fatigue |
| B3 | Notification actions | M | 3 | 3 | Needs real bundle |
| C1 | Intraday heatmap | L | 4 | 3 | Data-model change |
| C4 | Weekly/monthly trends | M | 3 | 1 | Pure aggregation |
| D4 | Guided stretch content | M | 3 | 2 | Content scope creep |
| E2 | Shortcuts / App Intents | M | 3 | 2 | Power-user delight |
| E3 | DnD / Focus awareness | S | 3 | 3 | API limits |
| F3 | Icon / About / polish | S | 2 | 1 | Pre-release |
| B4 | Calendar-aware mute | L | 3 | 3 | New permission |
| F4 | Notarize + auto-update | L | 5 | 4 | **Gates public release** |
| G3 | File-backed persistence | M | 2 | 3 | Triggered by C1/E1 |
| E1 | WidgetKit widget | L | 3 | 4 | Build-system cost |
| A4 | AirPods battery | S | 2 | 5 | Private API — defer |
| E5 | iCloud sync | L | 3 | 5 | Architecture pivot |
| E4 | Watch/iOS companion | XL | 4 | 5 | Separate app |

---

## 7. Suggested milestone sequencing

Grouped so each milestone ships a coherent, testable slice end-to-end. Use the
rexyMCP phase workflow per `REXYMCP.md`; write phase docs under
`docs/dev/milestones/<MX-name>/`.

- **M7 — Quick wins & polish.** B1 (countdown), G1 (thread cleanup), A3
  (presets), C3 (export). Low risk, immediately felt. _Also: §3 tagline copy
  change._
- **M8 — Reminder platform & wellness.** G2 (reminder-engine refactor) → D1
  (eye-rest) → D2 (hydration) → D3 (movement) with the global min-gap. This is
  the milestone that most justifies a "desk wellness" positioning — do the §3
  subtitle change here at the latest.
- **M9 — Engagement.** C2 (goals/streaks), C4 (trends), B2 (quiet hours). Turns
  data into motivation and stops off-hours annoyance.
- **M10 — Onboarding & accuracy.** F1 (onboarding — the long-planned M3), F2
  (guided calibration), A1 (tilt detection), A2 (drift suggestion).
- **M11 — Depth & integration.** C1 (intraday heatmap, with G3 if needed), B3
  (notification actions), E2 (Shortcuts), E3 (DnD).
- **M12 — Ship it.** F3 (icon/About), F4 (notarize + update path). Gate the
  public release here; this is where the §3 *rename* decision must be final
  (rename only ever happens before this point).

Deferred / explicit-decision-required: A4 (battery, private API), B4 (calendar
permission), D4 (content), E1 (widget build infra), E4 (companion app), E5
(iCloud — architecture pivot).

---

## 8. Implementation checklist template

Copy this per feature into its phase doc. It encodes the DoD
(`docs/dev/STANDARDS.md §1`) plus this project's specific gotchas.

```
### <Feature ID + name>

- [ ] Phase doc written under docs/dev/milestones/<MX>/ with Spec + acceptance.
- [ ] New AppSettings field(s)? → added to Keys, stored prop, init default,
      load(), save() — ALL FIVE — and classified analyzer-affecting vs
      notifier-only, with the matching update<Field>() on PostureViewModel.
- [ ] New external capability? → behind a protocol, injected via
      PostureViewModel.init, with a Fake… in PostureViewModelTests.swift.
- [ ] All provider callbacks dispatch to main before mutating @Published state.
- [ ] SlouchEngine kept pure (Foundation-only, timestamps passed in) if touched.
- [ ] Pure-logic tests added (SlouchEngine / StreakCalculator / store / settings).
- [ ] ViewModel behavior tests use drainMainQueue() after emit() and isolated
      UUID-named UserDefaults suites.
- [ ] make build (zero new warnings), make lint, make test all green.
- [ ] No force-unwrap / try! / fatalError() in production paths.
- [ ] End-to-end verification performed against the real bundle (make bundle /
      make run) and quoted in the Update Log — not just unit-test fakes.
- [ ] README.md "Features" + docs/architecture.md updated IF the phase changes
      architecture or user-facing capability.
- [ ] Conventional commit(s), one per logical change.
```

---

## Appendix: file → responsibility quick reference

| File | Touch it for |
|---|---|
| `Sources/NoSlouch/Posture/SlouchEngine.swift` | A1, A2, F2, G4 (pure classification logic) |
| `Sources/NoSlouch/Posture/PostureCalibration.swift` | A1 (multi-axis baseline) |
| `Sources/NoSlouch/Persistence/AppSettings.swift` | every new persisted setting (all 5 spots + tier) |
| `Sources/NoSlouch/Persistence/PostureHistoryStore.swift` | C1, C3, C4, G3 |
| `Sources/NoSlouch/Persistence/PostureSession.swift` | C1 (if session model grows) |
| `Sources/NoSlouch/PostureViewModel.swift` | coordination for nearly everything |
| `Sources/NoSlouch/Alerts/PostureNotifier.swift` | B3, D1–D4, E3 (alert delivery) |
| `Sources/NoSlouch/SettingsView.swift` | UI for every new setting |
| `Sources/NoSlouch/MenuBarView.swift` | popover surfaces (B1, C2) |
| `Sources/NoSlouch/HistoryView.swift` | C1, C3, C4 |
| `Sources/NoSlouch/PostureChartView.swift` | chart variants |
| `Sources/NoSlouch/NoSlouchApp.swift` | new scenes/windows (F1 onboarding), URL scheme (E2) |
| `Sources/NoSlouch/Motion/*` | A1 (consume roll/yaw), A4, G1 |
| `Tests/NoSlouchTests/*` | tests for all of the above |
| `Makefile` | F4 (notarize/dmg targets) |
| `Info.plist` / `NoSlouch.entitlements` | B4, E1, F4 (permissions/entitlements) |
| `README.md`, `docs/architecture.md` | keep in sync per DoD |

---

## 9. Repo optimization for LLM token efficiency

> **Goal.** Make it so any LLM (or human) can pick up a task and implement it
> while *reading as few tokens as possible* and *reasoning about as little
> ambiguity as possible*. Every item below is a concrete, repo-specific change.
>
> **Mental model.** An agent spends tokens in four places: (1) **discovery** —
> finding the right file; (2) **reading** — loading file contents into context;
> (3) **reconciliation** — resolving contradictions between docs/code; (4)
> **verification** — re-reading code because a doc couldn't be trusted. The
> optimizations below attack each. The single highest-leverage principle:
> **one source of truth, kept accurate** — because reconciliation and
> verification are the silent, compounding costs.

### 9.0 Quick-win table (do these first — all low effort)

| # | Change | Token problem it fixes | Effort |
|---|---|---|---|
| 1 | Fix stale `docs/architecture.md` (see 9.1) | reconciliation + verification | S |
| 2 | De-duplicate the "settings two-tier rule" into ONE canonical doc (9.2) | reconciliation | S |
| 3 | Remove duplicate DoD line in `STANDARDS.md` L41–42 (9.3) | reading noise | XS |
| 4 | Add a 1–2 line "responsibility" header doc-comment to each source file (9.4) | reading (read header, not whole file) | S |
| 5 | Extract test fakes into `Tests/NoSlouchTests/Fakes.swift` (9.5) | reading (1151-line test file) | M |
| 6 | Consolidate planning docs behind `NEXT.md` (9.6) | discovery + reconciliation | S |
| 7 | Add/keep ONE authoritative code map; delete the duplicates (9.7) | discovery | S |
| 8 | Purge on-disk `.DS_Store` noise (9.8) | discovery (clutters `ls`/`find` output) | XS |

### 9.1 Keep `docs/architecture.md` accurate (highest leverage)

The doc is now **stale**, and stale docs cost more tokens than missing ones
because an agent reads them, then re-reads code to check, then reconciles:

- It says `AppSettings` has **"Seven fields"** and lists them — there are now
  **12** (`muteInMeetings`, `breakRemindersEnabled`, `breakReminderMinutes`,
  `soundName`, `calibratedBaselinePitch` are all missing from the list).
- It lists **"M1 — Settings UI (active)"** as the current milestone — M1–M6 are
  all **done** (`README.md`).
- The data-flow diagram and component list **omit `MicrophoneMonitor`** and the
  break-reminder path, both of which exist.

**Fix.** Either update it to current reality, or — better for maintenance — slim
it to the *stable* parts (the layering, the threading contract, the non-goals)
and add a one-line pointer: *"For the current feature list and field set, the
code is the source of truth; see `README.md`."* Don't enumerate volatile details
(exact field lists) in prose that drifts — point to the type instead.

**Rule going forward:** the DoD already says "Architecture doc updated only if the
phase requires it." Tighten the convention: a phase that adds an `AppSettings`
field or a new monitor **does** require it (or requires removing the enumeration
so there's nothing to drift).

### 9.2 One canonical home for each convention

The **settings two-tier rule** is currently stated in `CLAUDE.md:57`,
`docs/architecture.md` "Settings ownership", and (now) this file §1. Three copies
= guaranteed future drift = reconciliation cost on every settings task.

**Fix.** Make `CLAUDE.md` the single canonical statement (it's the file every
agent is guaranteed to load). Replace the other copies with a one-line link:
*"Settings ownership / two-tier rule: see `CLAUDE.md`."* Same treatment for the
threading contract and the "hardware behind a protocol + fake" rule.

### 9.3 Remove literal duplicate lines

`docs/dev/STANDARDS.md` repeats `- [ ] `make lint` passes.` on **lines 41 and
42** (and the command table maps two rows to `make lint`, which is *intentional*
and explained — leave that). The DoD-checklist dupe is pure noise an agent reads
twice. Delete line 42.

### 9.4 Give every source file a one-line responsibility header

An agent deciding whether a file is relevant currently has to read its body. A
top-of-file doc comment lets it decide from the first ~40 tokens:

```swift
/// Pure posture classifier: maps (pitch, timestamp) samples to SlouchState.
/// No imports beyond Foundation. Highest unit-test priority. (See CLAUDE.md.)
public struct SlouchEngine { … }
```

Add one to each file in `Sources/NoSlouch/`. Cheap, and it compounds: discovery +
reading both drop.

### 9.5 Split the 1151-line test file; extract fakes

`Tests/NoSlouchTests/PostureViewModelTests.swift` is **1151 lines** — by far the
largest file in the repo. To edit one cooldown test, an agent loads all 1151
lines (or risks a non-unique `old_string` edit). Two fixes:

1. **Extract `Tests/NoSlouchTests/Fakes.swift`** holding `FakeHeadMotionProvider`,
   `FakeAudioOutputMonitor`, `FakeMicrophoneMonitor`, `FakePostureNotifier`
   (currently "defined at the bottom" per `CLAUDE.md:67`). An agent reads the
   fakes **once**, then never reloads them while editing tests.
2. **Split the tests by concern** into focused files
   (`…Cooldown`, `…Mute`, `…Breaks`, `…Snooze`, `…Sessions`). Each file is then
   small enough to load whole, and `--filter` still works per file.

Same logic applies to `PostureViewModel.swift` (615 lines, the god-coordinator):
splitting reminder logic, deviation sampling, and status-text formatting into
`extension PostureViewModel` files (one concern each) means an agent touching
breaks doesn't load the chart/snooze code. **Note:** this dovetails with **G2**
(reminder-engine refactor) — do them together.

### 9.6 Consolidate planning docs behind `NEXT.md`

Planned/next work currently lives across `docs/dev/NEXT.md`,
`docs/dev/MVP.md`, `suggestion.md`, and now `improvements.md`. An agent asking
"what should I build next?" must read all four and reconcile. Make **`NEXT.md`
the one entry point**: it names the active phase and links out
("backlog: `improvements.md`; resolved-vs-shipped trace: `MVP.md`; outstanding
small fixes: `suggestion.md`"). One hop to the truth, not four reads.

### 9.7 Exactly one authoritative code map

A "file → responsibility" table currently exists in **`README.md`** (lines ~87)
**and** in this file's Appendix. Two tables drift. Pick one canonical location
(suggest `README.md`, since it's the public front door) and have the other link
to it. A short, *accurate* index is what lets an agent jump straight to a file via
`Glob`/`Grep` instead of an exploratory directory crawl.

### 9.8 Purge on-disk `.DS_Store` noise

`.DS_Store` is correctly **gitignored** (not tracked — good), but the files still
exist on disk (`docs/.DS_Store`, `Sources/.DS_Store`, etc.) and **show up in
every `find`/`ls`/Glob result**, padding tool output an agent has to parse. Run a
one-time `find . -name .DS_Store -delete`, and consider a `make clean`-adjacent
target or a pre-commit step to keep them gone.

### 9.9 Reduce naming ambiguity (`Posture*` vs `Slouch*`)

The codebase mixes two prefixes for the same domain:
`PostureViewModel`, `PostureNotifier`, `PostureHistoryStore`, `PostureSession`,
`PostureChartView`, `PostureCalibration` **vs** `SlouchEngine`, `SlouchState`.
An agent guessing a filename (e.g. "where's the engine?") guesses `Posture…`
half the time and burns a failed `Glob`/`Grep` round-trip. Two options:

- **Cheap:** document the split explicitly in `CLAUDE.md` ("the analyzer pair is
  `SlouchEngine`/`SlouchState`; everything else is `Posture*`") so the agent never
  guesses.
- **Thorough:** unify on one prefix (e.g. rename `SlouchEngine`→`PostureEngine`,
  `SlouchState`→`PostureState`). Note this was *deliberately* renamed the other
  way recently (`PostureAnalyzer`→`SlouchEngine`), so confirm intent before
  flipping. Lower priority than 9.1–9.6.

### 9.10 Make invariants structural, not documental (highest-effort, highest-payoff)

The two-tier settings rule is enforced today by **discipline + docs**. Every new
field is a chance to get it wrong, and every agent must read the rule to get it
right. If the rule were encoded in the **type system**, the doc (and the reading
of it) becomes unnecessary:

- Introduce a single choke point, e.g.
  `func update<V>(_ keyPath: WritableKeyPath<AppSettings, V>, to value: V, tier:
  SettingTier)` where `SettingTier` is `.analyzerAffecting | .notifierOnly`, and
  the function performs the correct save/rebuild for the chosen tier.
- The compiler now *forces* the author to name a tier; the per-field `update…`
  boilerplate in `PostureViewModel` (≈15 near-identical methods) collapses; and an
  agent adding a field literally cannot skip the decision or do the wrong
  side-effect.

This trades a one-time refactor for permanently lower per-task token cost and
fewer correctness foot-guns. Treat as its own small phase.

### 9.11 General principles (apply to all future work)

- **Prefer the type over prose.** Don't enumerate fields/values in docs that the
  code already lists — point to the type. Code can't drift from itself.
- **Keep files single-responsibility and < ~300 lines** where practical, so a
  whole unit fits in one cheap read.
- **Keep symbols unique and grep-able** so `Grep` finds them in one shot.
- **Keep tool output lean:** no committed build artifacts (already done ✅), no
  stray `.DS_Store` (9.8), no generated/vendored blobs in tracked paths.
- **One entry point per question:** "what's the architecture?" → architecture.md;
  "what's next?" → NEXT.md; "what are the rules?" → CLAUDE.md; "where's the code
  for X?" → README code map. Each question, exactly one hop.

> These are recommendations only — no code has been changed. Items 9.1, 9.2, 9.3,
> 9.6, 9.7, and 9.8 are near-zero-risk and can be applied immediately; 9.5, 9.9,
> and 9.10 are larger and should be their own phases.

---

## 10. Bugs, code improvements & functionality updates

> Found by reading the full source. Each item: **severity**, **location**,
> **what's wrong**, **fix**, and a **test** to lock it down. Severity legend:
> 🔴 correctness bug users will hit · 🟠 correctness/UX bug in an edge case ·
> 🟡 robustness/latent · ⚪ quality/maintainability.
>
> Confidence is noted where a claim depends on runtime behavior I inferred rather
> than executed — verify those against a real device before "fixing."

### 10.1 Bugs

#### 🔴 BUG-1 — Analyzer's internal timing state is stale across a stop→start

**Where.** `PostureViewModel.startMonitoring()` (`PostureViewModel.swift:138-157`)
vs `SlouchEngine`'s private `badStartedAt` / `recoveryStartedAt` / `smoothedPitch`.

**What's wrong.** `stop()` does not touch the analyzer, and `startMonitoring()`
only does `postureState = analyzer.state` — it never resets the engine's internal
hold/recover timers or smoothed pitch. So if a user stops while slouching (or
mid-transition) and restarts later, the engine still carries
`badStartedAt`/`recoveryStartedAt` timestamps from the previous session. On the
**first** reading after restart, `timestamp.timeIntervalSince(badStartedAt)` is
enormous (could be hours), so the hold/recover threshold is satisfied
*immediately* — producing an instant, incorrect `.good`↔`.bad` transition on the
first sample instead of requiring a fresh `holdSeconds`/`recoverSeconds` window.
The stale `smoothedPitch` also biases the first few smoothed values.

**Fix.** On `startMonitoring()`, reset the engine's transient state while keeping
the calibration baseline. Cleanest: add `SlouchEngine.resetTransientState()`
(zeroes `badStartedAt`/`recoveryStartedAt`, sets `state = calibration == nil ?
.unknown : .good`, clears `smoothedPitch`) and call it from `startMonitoring()`.
Re-applying the saved baseline via `analyzer.calibrate(pitch:)` also works if a
baseline exists.

**Test.** `SlouchEngineTests`: calibrate, drive to `.bad`, then feed a reading
with a timestamp hours later that is *below* threshold — assert it does **not**
instantly flip (a fresh recover window is required). Plus a `PostureViewModelTests`
restart scenario.

---

#### 🟠 BUG-2 — `airPodsActive` is true for *any* Bluetooth output device

**Where.** `AudioOutputMonitor.isHeadphones(name:transport:)`
(`AudioOutputMonitor.swift:143-150`); consumed by
`PostureViewModel.startMonitoring()` guard (`:143`).

**What's wrong.** `isHeadphones` returns `true` when the transport is
`kAudioDeviceTransportTypeBluetooth`/`…BluetoothLE`, regardless of device type. A
Bluetooth **speaker**, car audio, or non-motion BT headset all set
`airPodsActive = true`. The property name promises "AirPods," but it really means
"output looks like headphones or is any Bluetooth device." Consequence:
`startMonitoring()` passes its guard with BT speakers connected, flips to
"monitoring," but no head-motion ever arrives (the only thing that stops it is
`CMHeadphoneMotionManager.isDeviceMotionAvailable` being false → an error path).
The user sees "monitoring" with a silent dead sensor.

**Fix (two parts).**
1. Rename the protocol property to something honest
   (`isHeadphoneOutput` / `headphonesActive`) — it's already plumbed through the
   protocol so this is a mechanical rename across `AudioOutputMonitoring`,
   `PostureViewModel`, `FakeAudioOutputMonitor`, and tests.
2. Tighten the start path: gate `startMonitoring()` on **motion availability**,
   not just audio route. Either surface `CMHeadphoneMotionManager.
   isDeviceMotionAvailable` through `HeadMotionProvider` (e.g. a
   `var isAvailable: Bool`) and check it, or keep the audio guard but treat the
   provider's `onError`/no-readings as the authority and show a clear "AirPods
   motion unavailable" status quickly.

**Test.** `PostureViewModelTests` with a `FakeAudioOutputMonitor` reporting a
non-AirPods BT device + a motion provider that never emits → assert the UI does
not get stuck in a false "monitoring/healthy" state. (Confidence: the loose match
is certain from the code; the exact downstream UX depends on real
`isDeviceMotionAvailable` behavior — verify on device.)

---

#### 🟠 BUG-3 — Device-name change between two headphone devices is silent

**Where.** `AudioOutputMonitor.refresh()` (`AudioOutputMonitor.swift:59-76`).

**What's wrong.** `onChange` only fires when `active != airPodsActive`. If the
user switches directly from one headphone device to another (AirPods → Beats),
`active` stays `true`, so `onChange` never fires even though `deviceName` changed.
The ViewModel's status text ("AirPods Pro connected") then shows a **stale device
name** until some unrelated event triggers `refreshStatus()`.

**Fix.** Track the last-reported `deviceName` and fire `onChange` (or a dedicated
`onDeviceNameChange`) when the name changes even if `active` is unchanged. Or have
`refresh()` always notify and let the ViewModel debounce.

**Test.** Hard to unit-test (CoreAudio), so cover via a small refactor: extract the
"did the user-visible state change?" decision into a pure function and test that
a name-only change is reported.

---

#### ✅ BUG-4 — Data race on `AirPodsMotionProvider.lastReadingAt` — **FIXED by PR #14**

**Where.** `AirPodsMotionProvider.swift:12, 42-47, 64`.

**What's wrong.** `lastReadingAt` is written inside the motion handler on the
background `OperationQueue` (`:47`) and also written on the main thread by
`stop()` (`:64`). No synchronization. It's a throttle timestamp, so the race is
benign in practice (worst case: one extra or one skipped sample around a
stop/start), but it is a genuine data race that ThreadSanitizer will flag.

**Fix.** Either confine `stop()`'s reset to the same queue
(`queue.addOperation { self.lastReadingAt = nil }`) or drop the `stop()` reset
(harmless — the next `start()` re-establishes throttling on first sample).

**Status.** ✅ Resolved by PR #14: the throttle read/write now happens inside the
`DispatchQueue.main.async` block, so `lastReadingAt` is only ever touched on main.
(But the throttle moved *after* the dispatch — see **NB-10**.)

---

#### ✅ BUG-5 — `AirPodsMotionProvider` reading callbacks not consolidated on main — **FIXED by PR #14**

**Where.** `AirPodsMotionProvider.swift:57` (`onReading`), `:70-75`
(`onConnectionChanged` from delegate). Cross-ref `suggestion.md` / **G1**.

**What's wrong.** `onError` inside the motion handler is wrapped in
`DispatchQueue.main.async` (`:34`) but `onReading` (`:57`) is called directly on
the background queue, and the `CMHeadphoneMotionManagerDelegate` connect/disconnect
callbacks (`:70-75`) have no thread guarantee. The ViewModel re-dispatches
everything to main, so there's no live bug — but the provider is internally
inconsistent. Consolidate all callbacks onto main inside the provider (matches
`AudioOutputMonitor`/`MicrophoneMonitor`, which already dispatch on
`DispatchQueue.main`).

**Fix.** Wrap `onReading?` and the delegate `onConnectionChanged?` calls in
`DispatchQueue.main.async`. (This is **G1** from §5 — listed here with exact
lines.)

**Status.** ✅ Done in PR #14 — `start()`'s availability error, the motion handler
(`onReading`), and both `CMHeadphoneMotionManagerDelegate` connect/disconnect
callbacks are now wrapped in `DispatchQueue.main.async`.

---

#### 🟡 BUG-6 — `MicrophoneMonitor.addInputDeviceListener` ignores failure

**Where.** `MicrophoneMonitor.swift:127-133`.

**What's wrong.** The `AudioObjectAddPropertyListenerBlock` result is discarded
(`_ =`). On failure, `inputDeviceListenerBlock` is still stored and
`currentInputDeviceID` is set, so `removeInputDeviceListener` later calls Remove on
a listener that was never added (harmless error), **and** mic running-state changes
for that device go undetected until the default input device changes. Contrast with
`AudioOutputMonitor.start()` (`:40-42`) which correctly nils its block on failure.

**Fix.** Check the `OSStatus`; on non-`noErr`, nil out `inputDeviceListenerBlock`
(and don't record it as active). Consider falling back to polling or surfacing a
status if the listener can't be installed.

---

#### 🟡 BUG-7 — Lowering the break interval mid-session can fire an immediate reminder

**Where.** `PostureViewModel.updateBreakReminderMinutes(_:)`
(`PostureViewModel.swift:602-605`); break logic at `:392-403`.

**What's wrong.** `updateBreakReminderMinutes` changes `breakReminderMinutes`
without touching `lastBreakNudgeMonitoredSeconds`. If the user lowers the interval
below the already-accumulated `goodSeconds + badSeconds - lastBreakNudge…`, the
next reading sees `isDue == true` and fires a break reminder instantly. (`enable`
resets the marker at `:597-599`, but an interval *change* does not.)

**Fix.** On interval change, optionally re-anchor the marker
(`lastBreakNudgeMonitoredSeconds = goodSeconds + badSeconds`), or document that
interval changes are measured from "now." Pick one and test it.

---

#### ⚪ BUG-8 — Discarded `OSStatus` in `transportTypeFor`

**Where.** `AudioOutputMonitor.transportTypeFor(deviceID:)` (`:112`).

**What's wrong.** `AudioObjectGetPropertyData`'s status is ignored; on failure
`transport` stays `0`, silently falling back to name-matching only. Low impact
(the name heuristic usually catches it), but it's an unchecked syscall. Check the
status and treat failure explicitly.

---

#### ⚪ BUG-9 — Dead snooze-clear branch (minor)

**Where.** `PostureViewModel.maybeNudgeForBadPosture` (`:419-425`) vs the earlier
snooze-expiry clear in `handle` (`:368-370`).

**What's wrong.** `handle()` already clears `snoozedUntil` once
`reading.timestamp >= snoozedUntil`. By the time `maybeNudgeForBadPosture` runs,
an expired snooze is already nil, so its `self.snoozedUntil = nil` line is
effectively unreachable for the expiry case. Not a bug, but confusing duplicated
logic. Consolidate snooze-expiry into one place.

---

### 10.2 Code-quality improvements

- ⚪ **`@Published var settings` is publicly settable** (`PostureViewModel.swift:25`),
  which bypasses the two-tier `update…` discipline. Make it
  `@Published private(set) var settings` so the only way to change settings is
  through the tier-aware methods. (Pairs with §9.10's structural choke point.)
- ⚪ **Magic number `30.0`** appears in the deviation gauge math
  (`MenuBarView.swift:61,64,81`) and conceptually in the chart. Extract a named
  constant (`maxDeviationDegrees`) so the gauge scale and any future "max" label
  stay in sync.
- ⚪ **Status text is built as ad-hoc string concatenation** in `refreshStatus()`
  (`PostureViewModel.swift:547-586`). Model it as a `StatusState` enum with a
  computed display string — easier to test, localize, and reason about, and it
  removes the repeated `notificationSuffix` interpolation.
- ⚪ **No localization.** All user-facing strings are inline English literals
  (notifications, status, menu). If international users are a goal, route them
  through `String(localized:)` / a `.strings` catalog now, while the surface is
  small.
- ⚪ **Wall-clock `Date()` sprinkled in the ViewModel** (`finalizeSession(endedAt:
  Date())` `:165,222,481`; `snoozeNudges` fallback `:174`). Most timing correctly
  uses the reading clock, but these few wall-clock calls make those paths harder
  to test deterministically. Consider injecting a `now: () -> Date` clock (also
  helps when you add quiet-hours/scheduling in B2).
- ⚪ **Tunables are hardcoded constants** (`ignoredNudgeLimit = 3`,
  `nudgePauseDuration = 600`, `deviationWindowSeconds = 60`, `smoothingAlpha =
  0.2`). Fine as defaults, but surfacing `smoothingAlpha` and the pause behavior
  would help power users and makes the values discoverable.

### 10.3 Functionality updates

- 🟠 **Surface motion availability explicitly.** Tied to BUG-2: add
  `isDeviceMotionAvailable` to `HeadMotionProvider` and show a distinct,
  early status ("AirPods don't support motion" vs "Set AirPods as output" vs
  "Ready") so users aren't left in a silent dead-sensor state.
- **Persist (or deliberately don't) the auto-pause across launches.** `snoozedUntil`
  is intentionally in-memory (documented), but `nudgesPausedUntil` and
  `consecutiveBadNudgeCount` also reset on relaunch — decide if that's intended and
  document it next to the snooze rationale in `CLAUDE.md`.
- **Live snooze/pause countdown** — already specced as **B1**; BUG-9 cleanup and
  the fixed "paused for 10 min" text (`refreshStatus` `:563-564`, which always
  prints `nudgePauseDuration/60` regardless of remaining time) should be fixed
  together with it.
- **Make the break/eye/hydration reminders robust to interval edits** (BUG-7) as
  part of the **G2** reminder-engine refactor.
- **Guard against non-finite pitch** defensively in `SlouchEngine.update` (a NaN
  from the sensor would propagate through smoothing and comparisons). Cheap, pure,
  testable — fold into **G4**.

### 10.4 Priority of fixes

| ID | Severity | Effort | Do it… |
|---|:--:|:--:|---|
| BUG-1 stale analyzer state | 🔴 | S | **First** — real misclassification |
| BUG-2 BT-output misdetection | 🟠 | M | With a "motion availability" status pass |
| BUG-3 silent device-name change | 🟠 | S | Quick |
| BUG-7 break-interval immediate fire | 🟡 | S | With G2 |
| BUG-4 lastReadingAt race | 🟡 | S | With G1 |
| BUG-5 callbacks on main | 🟡 | S | = G1 |
| BUG-6 mic listener failure | 🟡 | S | Quick |
| BUG-8 discarded OSStatus | ⚪ | XS | Quick |
| BUG-9 dead snooze branch | ⚪ | XS | With B1 |

> No code changed — these are diagnoses with fixes. BUG-1, BUG-3, BUG-6, BUG-8 are
> safe, isolated fixes that could ship immediately with tests; BUG-2 is the one
> that benefits from being designed as a small phase (status model + protocol
> change).

---

### 10.5 New issues introduced by PR #14 (M7 merge `ff7295d`)

> Found by reading the merged diff. Build compiles, 72 tests pass — these are
> latent/behavioral/risk issues the tests don't catch. NB = "new bug."

#### 🟠 NB-1 — Auto-drift mutates `settings.calibratedBaselinePitch` in memory but never saves it; an unrelated setting change then silently persists the drift

**Where.** `PostureViewModel.handle()` auto-drift block (the `if postureState ==
.good …` section added around `:413-433`).

**What's wrong.** The drift block does
`settings.calibratedBaselinePitch = newBaseline` (and `analyzer.updateBaselinePitch`)
on good readings, but **never calls `settings.save(to:)`** — so drift is meant to
be session-only. The problem: the in-memory `settings` value type is now divergent
from disk, and **every notifier-only `update…` method calls `settings.save(to:)`**,
which writes *all* fields including `calibratedBaselinePitch`. So if the user
toggles Sound / Speech / break reminders / etc. mid-session, the **drifted**
baseline is flushed to disk as if it were a deliberate calibration. Persistence of
drift is therefore nondeterministic, dependent on unrelated UI actions.

**Fix.** Decide the intent explicitly: either (a) keep drift fully in-memory by
**not** mutating `settings` at all — store a separate `driftedBaseline` and feed
only the analyzer; or (b) make it a real, intentionally-persisted value with its
own save. Do not leave a half-persisted field that other `save()` calls leak.

**Test.** Drive drift, then call `updateSoundEnabled(true)`, reload `AppSettings`
from the same defaults, assert the baseline is/ isn't persisted per the chosen
intent.

#### 🟠 NB-2 — Auto-drift is the silent, non-disable-able EMA variant this plan warned against

**Where.** Same block; `alpha = 0.0005`, ±2.0° bound vs `originalCalibratedPitch`.

**What's wrong.** §A2 explicitly recommended the *"suggest a recalibration"*
variant and cautioned that a silent moving average "can drift the baseline toward
a slouched posture and mask real slouching." PR #14 implemented exactly the silent
auto-adapt. It is bounded to ±2° (good — matches the "bound cumulative drift"
caveat) and only adapts while `.good` (good), **but** there is **no setting to
disable it** and **no UI indication** it is happening. A user who calibrated
precisely will have their baseline silently moved up to 2°.

**Fix.** Add an `autoDriftEnabled: Bool` setting (default off, **analyzer-affecting
tier**) and gate the block on it; consider surfacing "baseline auto-adjusted" in
the UI. At minimum, document the behavior in `CLAUDE.md` next to the calibration
lifecycle notes.

#### 🟡 NB-3 — Drift desyncs the displayed baseline from the actual analyzer baseline

**Where.** Drift updates `analyzer` + `settings` but **not** `lastCalibratedPitch`
(the `@Published` shown in the popover). `MenuBarView` computes the deviation gauge
from `viewModel.lastCalibratedPitch` (`MenuBarView.swift:~33`), while the analyzer
classifies good/bad from the *drifted* baseline.

**What's wrong.** After drift, the popover "Calibrated: X°" and the deviation gauge
use the original baseline, but the red/green state uses the drifted one. The gauge
and the actual classification can disagree by up to 2°, and the displayed
"Calibrated" value is stale.

**Fix.** When drift updates the baseline, also update `lastCalibratedPitch` (and
have the gauge read a single source of truth), or compute the gauge from the same
baseline the analyzer uses.

#### 🟠 NB-4 — Battery monitor spawns `system_profiler` every 30 s (expensive, runs continuously)

**Where.** `AirPodsBatteryMonitor.fetchBatteryInfo()` runs
`/usr/sbin/system_profiler SPBluetoothDataType` via `Process`, scheduled every 30 s
by a repeating `Timer` (`AirPodsBatteryMonitor.swift:33-82`).

**What's wrong.** `system_profiler SPBluetoothDataType` is a heavyweight call
(spawns a subprocess, enumerates the entire Bluetooth stack, can take 1–several
seconds). Doing this **every 30 seconds for the whole time AirPods are connected**
is a real CPU/energy drain — ironic in a wellness/menu-bar utility meant to be
unobtrusive. Worse, it's gated on `audioOutputMonitor.airPodsActive`, which (per
**BUG-2**) is true for *any* Bluetooth output — so the polling can run with any BT
device connected.

**Fix.** Drastically reduce frequency (e.g. 5–10 min, and only refresh on a
relevant event), cache aggressively, and/or move off `system_profiler` to a less
costly source. Reconsider whether the feature earns its cost (this is the A4
"higher-risk and lower-priority than its size suggests" warning, realized).

#### 🟠 NB-5 — Battery parsing is English-locale-only and not scoped to a specific device

**Where.** `AirPodsBatteryMonitor.parseBatteryOutput` matches the literal prefixes
`"Left Battery Level:"`, `"Right Battery Level:"`, `"Case Battery Level:"`.

**What's wrong.** (1) Those strings are **English**; on a localized macOS the
`system_profiler` labels differ and parsing yields nothing — the widget silently
shows no data. (2) The parser scans **all** Bluetooth devices and the **last**
matching line wins — there is no scoping to the AirPods device name, so with
multiple battery-reporting BT devices the wrong device's level can be shown.

**Fix.** Scope parsing to the connected AirPods device block (match the device
name first), and don't depend on localized human-readable output — or accept the
feature as best-effort and hide it when uncertain.

#### 🟡 NB-6 — `Process` spawning is incompatible with App Store sandboxing

**Where.** `AirPodsBatteryMonitor.fetchBatteryInfo()`.

**What's wrong.** Spawning an external executable is disallowed under the App
Sandbox (Mac App Store) and adds hardened-runtime/notarization surface for Developer
ID. Under sandbox the call fails and the feature returns empty silently. This is the
exact distribution risk flagged in §A4, now in the codebase.

**Fix.** If MAS distribution is ever a goal, this feature must be reworked or
excluded; document the constraint now so it isn't discovered at submission time.

#### 🟡 NB-7 — Production code branches on the test environment

**Where.** `AirPodsBatteryMonitor.pollBattery()`:
`if NSClassFromString("XCTestCase") != nil { return }`.

**What's wrong.** Production code detecting whether it runs under XCTest is a smell
(and counter to the project's testing approach, where hardware is faked via
protocols). It also means the real `pollBattery` path is **never exercised** by
tests.

**Fix.** Inject the fetch (a `BatteryFetching` closure/protocol) and use a fake in
tests, instead of an in-code test check. Then delete the `NSClassFromString` guard.

#### 🟠 NB-8 — Force-unwrap in `PostureHistoryStore.add()` violates the DoD

**Where.** `PostureHistoryStore.add()`:
`let hour = calendar.date(from: calendar.dateComponents([.year,.month,.day,.hour], from: session.startedAt))!`

**What's wrong.** `STANDARDS.md §2` forbids force-unwrap in production paths. While
reconstructing a date from its own components is *practically* safe, this is an
explicit DoD violation and a theoretical crash on an exotic calendar/date.

**Fix.** Use a guarded fallback (`guard let hour = … else { return }` or fall back
to `calendar.startOfDay`). Add a test with an edge date.

#### 🟡 NB-9 — Heatmap attributes a whole session to its START hour

**Where.** `PostureHistoryStore.add()` buckets by `dateComponents(…, .hour)` of
`session.startedAt` only.

**What's wrong.** A session spanning 14:50→15:40 is counted **entirely in hour
14** — its goodSeconds/badSeconds/slouchEvents all land in the start hour. The
intraday heatmap therefore mis-attributes long, cross-hour sessions (the §C1 spec
called for attributing seconds to the hour in which they actually occurred). Daily
rollups remain correct (they sum all hours), so only the intraday view is affected.

**Fix.** If accuracy matters, split a session's accumulated seconds across the
hours it spans (the ViewModel would need per-hour accumulation, as §C1 noted).
Otherwise, document the "by start hour" approximation in the heatmap caption.

#### 🟡 NB-10 — Motion throttle moved onto the main thread (perf regression)

**Where.** `AirPodsMotionProvider.start()` motion handler — the
`minimumReadingInterval` throttle now runs **inside** `DispatchQueue.main.async`.

**What's wrong.** Previously the 10 Hz throttle ran on the background
`OperationQueue` and only ~10 readings/s were dispatched to main. Now **every** raw
sample (~25–50 Hz from `CMHeadphoneMotionManager`) is dispatched to main and the
throttle drops the surplus there — ~2.5–5× more main-queue hops, most of which do
nothing. The thread-safety win (BUG-4/5) is worth it, but the throttle didn't need
to move.

**Fix.** Keep the throttle (timestamp compare) on the background queue and only
`DispatchQueue.main.async` the surviving reading. That preserves both the
main-thread-state invariant and the low dispatch volume.

#### Severity-ordered fix priority for the new issues

| ID | Severity | Theme | Suggested action |
|---|:--:|---|---|
| NB-1 | 🟠 | auto-drift persistence leak | Fix before next release — silent data corruption of calibration |
| NB-4 | 🟠 | battery polling cost | Throttle hard or gate the feature |
| NB-2 | 🟠 | silent drift, no opt-out | Add setting + default off, or revert to suggest-only |
| NB-5 | 🟠 | locale/device-scoping | Scope parse; treat as best-effort |
| NB-8 | 🟠 | force-unwrap (DoD) | Quick guarded fix + test |
| NB-3 | 🟡 | UI baseline desync | Single source of truth for baseline |
| NB-9 | 🟡 | heatmap attribution | Split across hours or document |
| NB-10 | 🟡 | throttle on main | Move throttle back to bg queue |
| NB-6 | 🟡 | sandbox incompatible | Document; decide at distribution time |
| NB-7 | 🟡 | test-detection in prod | Inject a fetcher, delete the guard |

> **Process observation.** The phase docs (`docs/dev/milestones/M7-pending-suggestions/`)
> scheduled only three phases and explicitly **deferred** battery + auto-drift
> "pending a design decision," yet both were merged in the same PR. The two most
> problematic additions (NB-1..NB-7) are precisely the deferred ones — they bypassed
> the design gate the milestone set for them.

---

## 11. Additional feature catalog — round 2

> A second wave of features not covered in §4. Same conventions as §1 apply
> (settings two-tier rule, protocol+fake for hardware/OS surfaces, pure-struct
> logic where possible, DoD). Same spec shape: **Why → What changes → Tier → UI →
> Tests → Acceptance → Risk**. Difficulty S/M/L/XL. Grouped by theme H–K.

### H. Context awareness (the app should know when you're actually at your desk)

#### H1. Idle / screen-lock / away auto-pause — **M** ⭐ (highest-value new item)

**Why.** Today monitoring runs whenever AirPods are connected and you press Start.
If you walk away (lunch, a meeting in another room) but leave the AirPods in, the
session keeps accumulating — polluting "% upright," slouch counts, break timers,
and history with time you weren't even at the desk. There is no idle detection
anywhere in the code.

**What changes.**
- New `ActivityMonitoring` protocol + `ActivityMonitor` real impl (no new
  permissions): observe `NSWorkspace.shared.notificationCenter` for
  `.sessionDidResignActive`/`screensDidSleep`/lock (`com.apple.screenIsLocked`),
  and/or compute user-idle seconds via
  `CGEventSource.secondsSinceLastEventType(.combinedSessionState, .anyInputEventType)`.
  Expose `isUserAway: Bool` / `onChange`.
- `PostureViewModel`: when `isUserAway` becomes true while monitoring, **pause
  accumulation** (treat like a soft stop: stop counting good/bad seconds, freeze
  break timer) and resume on return. Keep the session open (don't finalize) unless
  away exceeds a threshold (then finalize so the gap isn't counted).

**Settings tier.** `pauseWhenAwayEnabled: Bool`, `awayThresholdSeconds: Double`
→ notifier/behavior-only (doesn't affect classification).

**UI.** Status text "Paused — away from desk"; a Settings toggle.

**Tests.** `PostureViewModelTests` with a `FakeActivityMonitor`: emit away→back,
assert good/bad seconds and break timer don't advance while away. Deterministic via
injected timestamps.

**Acceptance.** Walking away (idle > threshold or screen locked) stops counting;
returning resumes the same session without a slouch artifact.

**Risk.** Low — all public APIs, no permissions. Decide whether a long away-gap
splits the session (recommended) vs. one long session with a hole.

---

#### H2. Focus / Pomodoro work sessions with a posture grade — **M**

**Why.** Tie posture to how people already structure work. A 25/5 focus timer that,
at the end of each sprint, reports "this sprint: 88% upright, 2 slouches" turns
posture into per-sprint feedback and a natural break cadence (folds into the
reminder engine, **G2**).

**What changes.** A `FocusSession` concept layered on the existing session
accumulators; a start/stop timer in the popover; end-of-sprint summary via
`PostureNotifier`. Reuses `sessionGoodSeconds`/`sessionSlouchEvents`.

**Settings tier.** `focusWorkMinutes`, `focusBreakMinutes` → notifier-only.

**Risk.** Scope overlap with break reminders — unify under the **G2** engine rather
than a parallel timer.

---

#### H3. Low-battery-aware behavior — **S**

**Why.** Once the battery monitor exists (A4/NB-4), use it: when AirPods battery is
critically low, surface a one-time heads-up ("AirPods at 10% — motion tracking may
stop soon") instead of letting monitoring die silently.

**What changes.** `PostureViewModel` observes `batteryInfo`; fires a single
notification when any bud crosses a low threshold (debounced so it doesn't repeat).

**Settings tier.** None (or `lowBatteryWarningEnabled`).

**Risk.** Depends on the brittle battery source (NB-4/NB-5) — keep best-effort.

---

### I. Nudge experience (make the nudge itself smarter and nicer)

#### I1. In-ear audio cue through the AirPods — **S/M**

**Why.** The AirPods are *right there* and are the output device. A subtle in-ear
tone (or a short spoken word) is far less disruptive than a system banner + a
desktop sound others can hear. Currently nudges use `NSSound` (plays on the system
output) and optional speech.

**What changes.** Route the cue deliberately to the current output (it already is,
since AirPods are the output) but design a gentler, shorter, optionally
**spatial** cue. Could add an `AVAudioPlayer`-based soft tone bundled in
`Resources/`. Mostly a `PostureNotifier` change + an asset.

**Settings tier.** `nudgeStyle` (banner / sound / in-ear-tone / speech, multi-select)
→ notifier-only.

**Risk.** Don't fight the OS audio session; keep it short and low-volume.

---

#### I2. Custom nudge messages / affirmations — **S**

**Why.** "Sit up straight" gets ignored after a week. Let users write their own
lines ("Shoulders back, Nav") or rotate through a small set; personalization
improves adherence.

**What changes.** `AppSettings.customNudgeMessages: [String]` (persist as a joined
string or JSON). `PostureNotifier.nudge` picks one (rotate by index — remember, no
`Math.random` determinism needed, but here runtime randomness is fine in app code).

**Settings tier.** Notifier-only.

**Tests.** `PostureViewModelTests`/notifier fake: assert a custom message is passed
through when set; falls back to the degree-drop default when empty.

---

#### I3. Escalating nudge intensity — **S/M**

**Why.** A single banner is easy to ignore. If you stay slouched through several
nudges, escalate: banner → banner+sound → speech. (Distinct from the 3-strikes
*auto-pause*, which gives up; this leans in before giving up.)

**What changes.** `PostureViewModel.maybeNudgeForBadPosture` already tracks
`consecutiveBadNudgeCount` — map count → intensity level and pass it to
`PostureNotifier.nudge`. No new state needed.

**Settings tier.** `escalatingNudges: Bool` → notifier-only.

**Tests.** Drive N consecutive bad nudges; assert the notifier receives increasing
intensity until the existing pause kicks in.

**Risk.** Interaction with auto-pause — escalation must stop at the pause boundary.

---

#### I4. Configurable snooze presets + global hotkeys — **S**

**Why.** Snooze is hardcoded to 15/30/60 (`MenuBarView`). Power users want their own
durations and want to snooze/calibrate/start without opening the popover.

**What changes.** (a) `AppSettings.snoozePresetsMinutes: [Int]` driving the Snooze
menu. (b) Global hotkeys via `NSEvent.addGlobalMonitorForEvents` or a small key
registration for Start/Stop, Snooze, Calibrate (no extra entitlement for a
menu-bar app, but document the Accessibility-permission nuance for global
monitors).

**Settings tier.** Notifier-only (presets); hotkeys are app config.

**Risk.** Global event monitors may need Accessibility permission — prefer
`MenuBarExtra` keyboard shortcuts or `KeyboardShortcuts`-style local handling where
possible. Verify on device.

---

### J. Motivation & insight

#### J1. Daily letter-grade + achievements — **M**

**Why.** Streaks (C2) reward consistency; a daily **grade** (A–F from
`uprightFraction`) and unlockable achievements ("First week," "8-hour upright day,"
"Zero-slouch morning") reward improvement and milestones. Strong retention lever.

**What changes.** A pure `PostureGrading` struct (fraction → grade) and an
`Achievement` evaluator over `[DayPostureStat]`/`[HourPostureStat]` — both
Foundation-only, same test tier as `SlouchEngine`. Surface in `HistoryView`.

**Settings tier.** None (derived). Persist unlocked achievements (a `Set<String>`).

**Tests.** Pure grading/achievement tests with fixed stat arrays.

---

#### J2. Weekly digest — **S**

**Why.** A once-a-week local summary ("Last week: 82% upright, best day Tue, 34
slouches, ↑6% vs prior week") keeps the app present without daily nagging.

**What changes.** A scheduled local notification (compute on launch / via a low-freq
timer; no server). Pure aggregation over `dailyStats` (reuses C4 rollups).

**Settings tier.** `weeklyDigestEnabled`, `weeklyDigestWeekday` → notifier-only.

**Risk.** Scheduling reliability for a menu-bar app that may be quit — compute the
"is it time?" check on launch/active rather than relying solely on a long timer.

---

#### J3. Apple Health integration — **M**

**Why.** Write a daily "mindful/ergonomics" metric (or use `HKCategoryType`
mindful minutes as a proxy for upright minutes) so posture data lives alongside the
user's other health data. Read-nothing, write-only keeps it privacy-safe.

**What changes.** A `HealthExporting` protocol + `HealthKitExporter` real impl
(needs `NSHealthUpdateUsageDescription` + entitlement). ViewModel writes on session
finalize.

**Settings tier.** `exportToHealth: Bool` → notifier-only.

**Risk.** Adds a permission + entitlement; **off by default**. There's no native
"posture" HealthKit type, so document the chosen proxy metric. (Reconfirm against
current HealthKit — verify available types on device.)

---

#### J4. Session timeline / replay — **S/M**

**Why.** The live chart only shows the last 60 s. Let users scrub a finished
session's pitch/deviation timeline to see *when* they slouched.

**What changes.** Persist a downsampled per-session `[DeviationSample]` (or
pitch series) alongside the session; a scrubbable `Charts` view. Note storage
growth — downsample aggressively (e.g. 1 Hz), and this is another nudge toward the
file-backed store (**G3**).

**Settings tier.** None.

**Risk.** Storage size — cap retained replays (e.g. last 7 days) and log the cap
(§9.11 "no silent caps").

---

### K. Calibration, profiles & accessibility

#### K1. Multiple calibration profiles (sit / stand / laptop) — **M**

**Why.** One baseline doesn't fit a sit-stand desk or laptop-vs-monitor setups —
neutral head pitch differs. Today there's a single `calibratedBaselinePitch`.
Profiles let users switch context without recalibrating each time.

**What changes.** `AppSettings.profiles: [CalibrationProfile]` (name + baseline +
optionally threshold) and an `activeProfileID`. Switching a profile re-applies its
baseline to the analyzer. **Analyzer-affecting tier** (it changes the baseline the
engine uses) — switching must go through the analyzer-reset path or a dedicated
"apply baseline" path that does *not* wipe the stored profiles.

**Settings tier.** Analyzer-affecting (careful: don't clear all profiles on
switch — only re-point the active baseline).

**UI.** A profile picker in the popover + "calibrate this profile."

**Tests.** Switching profiles applies the right baseline; the deviation/state
recompute from it.

**Risk.** Interacts with auto-drift (A2/NB-1) and the persisted-baseline lifecycle
— design them together so drift writes back to the *active profile*, not a global.

---

#### K2. Recalibration reminder — **S**

**Why.** Baselines go stale (new chair, AirPods worn differently). A gentle "It's
been 14 days — recalibrate for accuracy?" keeps detection honest. Complements the
auto-drift *suggestion* idea (A2) with a time-based trigger.

**What changes.** Track `lastCalibrationDate` (persist on `calibrate()`); fire a
one-time prompt after N days. ViewModel + a notification.

**Settings tier.** Notifier-only (`recalibrationReminderDays`).

---

#### K3. Accessibility & color-blind-safe gauge — **S**

**Why.** The deviation gauge and stat cards lean on red/green, which is the most
common color-blind confusion pair, and there's no evidence of VoiceOver labels.

**What changes.** Add `.accessibilityLabel`/`Value` to the gauge, chart, and stat
cards; add a shape/icon channel (not color alone) to the good/bad indicator;
respect Dynamic Type. Pure SwiftUI changes in `MenuBarView`/`HistoryView`/
`PostureChartView`.

**Settings tier.** None (or a `highContrastGauge` toggle).

**Risk.** None — pure polish; high goodwill, App Review-friendly.

---

#### K4. Assertive "slouch overlay" (opt-in) — **M**

**Why.** For users who ignore banners, an optional, gentle full-screen tint or a
small floating indicator when slouching is a stronger cue. Strictly opt-in — this
is intrusive by design.

**What changes.** A borderless transparent `NSWindow`/`NSPanel` overlay toggled by
posture state; must be click-through and respect full-screen apps.

**Settings tier.** `assertiveOverlayEnabled: Bool` → notifier-only (default off).

**Risk.** Intrusiveness; full-screen/Spaces behavior; could annoy. Ship behind an
explicit opt-in with a strong default-off.

---

### Round-2 priority shortlist

| ID | Feature | Effort | Why it's worth it |
|---|---|:--:|---|
| **H1** | Idle/lock auto-pause | M | ⭐ Fixes data quality at the root; no permissions |
| K3 | Accessibility / color-blind gauge | S | Cheap, broad goodwill, App-Review-friendly |
| I3 | Escalating nudges | S/M | Uses existing `consecutiveBadNudgeCount` |
| J1 | Daily grade + achievements | M | Retention; pure-logic, easy to test |
| I2 | Custom nudge messages | S | High personalization / adherence per token |
| K1 | Calibration profiles | M | Real need for sit-stand/laptop users |
| H2 | Focus/Pomodoro sessions | M | Folds into the G2 reminder engine |
| J2 | Weekly digest | S | Presence without nagging |
| I4 | Snooze presets + hotkeys | S | Power-user delight |
| K2 | Recalibration reminder | S | Keeps detection accurate over time |
| J4 | Session replay | S/M | Pairs with G3 file store |
| J3 | Apple Health export | M | Privacy-safe write-only; needs entitlement |
| H3 | Low-battery warning | S | Cheap once A4 exists |
| K4 | Assertive overlay | M | Strong cue, opt-in only |

> Strongest single recommendation: **H1 (idle/lock auto-pause)** — every analytics
> and reminder feature in this document is only as trustworthy as the data feeding
> it, and right now away-from-desk time silently corrupts that data.
