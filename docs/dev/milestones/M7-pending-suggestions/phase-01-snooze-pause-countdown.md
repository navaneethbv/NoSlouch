# Phase 01: Snooze / pause countdown in status text

**Milestone:** M7 — Pending Suggestions
**Status:** done
**Depends on:** none
**Estimated diff:** ~45 lines
**Tags:** language=swift, kind=feature, size=s

## Goal

Replace the static "Nudges snoozed" and "Nudges paused for 10 min" status
strings with a live countdown that shows the remaining time (e.g. "Nudges
snoozed · 8 min left"). The popover already renders `viewModel.statusText`, so
no new view code or published property is needed — only `refreshStatus()` and
its tests change.

## Architecture references

Read before starting:

- `CLAUDE.md` — "Snooze (`snoozedUntil`) is separate from the auto-pause
  (`nudgesPausedUntil`)" and "based on the reading clock (`lastReadingAt`)". The
  countdown must be derived from `lastReadingAt`, not wall-clock `Date()`, so it
  matches when nudges actually resume.

## Pre-flight

1. Read `docs/dev/STANDARDS.md` top to bottom.
2. Read the architecture reference above.
3. Read this entire phase doc before touching any code.
4. Confirm the repo is on a clean branch with no uncommitted changes.

## Current state

`Sources/NoSlouch/PostureViewModel.swift` computes the menu status string in
`refreshStatus()`. The two branches this phase changes read **exactly**:

```swift
    } else if snoozedUntil != nil {
      statusText = "Nudges snoozed"
    } else if nudgesPausedUntil != nil {
      statusText = "Nudges paused for \(Int(nudgePauseDuration / 60)) min"
```

Both deadlines are anchored to the reading clock, so remaining time is
`deadline − lastReadingAt`:

- `snoozeNudges(for:)` sets `snoozedUntil = (lastReadingAt ?? Date()) + duration`.
- The auto-pause sets `nudgesPausedUntil = reading.timestamp + nudgePauseDuration`
  (where `reading.timestamp` is the value `lastReadingAt` was just set to).

`refreshStatus()` is called at the end of `handle(_:)` **after** `lastReadingAt`
is updated to the current reading, so by the time these branches run,
`lastReadingAt` is the latest reading time. `lastReadingAt` is a
`private var lastReadingAt: Date?` on the view model.

Two existing tests in `Tests/NoSlouchTests/PostureViewModelTests.swift` assert
the old strings and **must be updated** by this phase:

- Line ~109 (`testThreeBadPostureNudgesPauseRemindersForTenMinutes`):
  `XCTAssertEqual(viewModel.statusText, "Nudges paused for 10 min")`. At that
  point `lastReadingAt` is the t=16 reading and `nudgesPausedUntil` is t=616, so
  remaining is 600 s → 10 min.
- Line ~881 (a snooze test): `XCTAssertEqual(viewModel.statusText, "Nudges
  snoozed")`. There `snoozeNudges(for: 600)` is called when `lastReadingAt` is
  t=1 (so `snoozedUntil` = 601), then a reading at t=3 makes `lastReadingAt` = 3,
  so remaining is 598 s → ceil = 10 min.

## Spec

1. **Replace the entire `refreshStatus()` method and add the `minutesLeft`
   helper** — in `Sources/NoSlouch/PostureViewModel.swift`, do a single
   whole-function replacement: locate the existing `private func refreshStatus()
   {` and replace from that line through its closing `}` (the method's final
   brace, the one immediately before `func updateMuteInMeetings`) with the
   **exact** block below. Do NOT attempt a partial in-place patch of the two
   branches; replace the whole method and append the helper as shown. Only two
   lines differ from the current method (the snooze and pause branches); the
   helper is new. Everything else is identical and must stay byte-for-byte the
   same.

   ```swift
     private func refreshStatus() {
       let notificationSuffix = notificationsEnabled ? "" : " (notifications off)"

       if let motionError {
         statusText = motionError
         return
       }

       if disconnected {
         statusText = "AirPods disconnected\(notificationSuffix)"
       } else if !audioOutputMonitor.airPodsActive {
         statusText = "Set AirPods as output\(notificationSuffix)"
       } else if settings.muteInMeetings && isMicActive {
         statusText = "Nudges paused (mic active)"
       } else if let snoozedUntil {
         statusText = "Nudges snoozed · \(minutesLeft(until: snoozedUntil)) min left"
       } else if let nudgesPausedUntil {
         statusText = "Nudges paused · \(minutesLeft(until: nudgesPausedUntil)) min left"
       } else if !isMonitoring {
         let deviceName = audioOutputMonitor.deviceName
         if deviceName.isEmpty {
           statusText = "Ready\(notificationSuffix)"
         } else {
           statusText = "\(deviceName) connected\(notificationSuffix)"
         }
       } else {
         switch postureState {
         case .unknown:
           statusText = "Monitoring, calibrate upright\(notificationSuffix)"
         case .good:
           if isBaselineRestored {
             statusText = "Calibrated (restored), posture looks good\(notificationSuffix)"
           } else {
             statusText = "Calibrated, posture looks good\(notificationSuffix)"
           }
         case .bad:
           statusText = "Sit up straight\(notificationSuffix)"
         }
       }
     }

     private func minutesLeft(until deadline: Date) -> Int {
       let remaining = deadline.timeIntervalSince(lastReadingAt ?? Date())
       return Int((max(0, remaining) / 60).rounded(.up))
     }
   ```

   `rounded(.up)` means a snooze with 30 s left still reads "1 min left"; the
   branches are only reached while the deadline is in the future, so the value is
   ≥ 1 in practice.

2. **Update the paused-status assertion** — in
   `Tests/NoSlouchTests/PostureViewModelTests.swift`, change the line that reads
   `XCTAssertEqual(viewModel.statusText, "Nudges paused for 10 min")` to
   `XCTAssertEqual(viewModel.statusText, "Nudges paused · 10 min left")`. Change
   nothing else in that test.

3. **Update the snoozed-status assertion** — in the same file, change the line
   that reads `XCTAssertEqual(viewModel.statusText, "Nudges snoozed")` to
   `XCTAssertEqual(viewModel.statusText, "Nudges snoozed · 10 min left")`. Change
   nothing else in that test.

4. **Add a snooze-countdown test** — in the same file, add `func
   testSnoozeStatusCountsDownFromReadingClock()`. Build a `PostureViewModel`
   with `FakeAudioOutputMonitor(airPodsActive: true)` and an isolated history
   store (follow the construction in the existing snooze test). Calibrate at a
   good pitch, `startMonitoring()`, emit a good reading at t=0 to anchor
   `lastReadingAt`, call `snoozeNudges(for: 600)`, then emit a good reading at
   t=120 and `drainMainQueue()`. Assert `viewModel.statusText == "Nudges snoozed
   · 8 min left"` (deadline 600, lastReadingAt 120 → 480 s → 8 min).

5. **Add a pause-countdown test** — add `func
   testPauseStatusCountsDownFromReadingClock()`. Reuse the construction from
   `testThreeBadPostureNudgesPauseRemindersForTenMinutes` (threshold 10, hold 0,
   recover 1, alertCooldown 5). Drive three bad nudges to trigger the auto-pause,
   then emit one more bad reading 120 s after the pause was set and
   `drainMainQueue()`. Assert `viewModel.statusText` ends with "min left" and
   equals "Nudges paused · 8 min left" (pause deadline = pause-set time + 600;
   lastReadingAt = pause-set time + 120 → 480 s → 8 min). If the exact arithmetic
   is awkward to hit, it is acceptable to assert
   `viewModel.statusText.hasPrefix("Nudges paused · ")` **and**
   `viewModel.statusText.hasSuffix(" min left")` instead — pin the format, not a
   brittle exact minute.

## Acceptance criteria

- [ ] `make build` succeeds.
- [ ] `make lint` passes.
- [ ] `make test` passes, including the two updated assertions and the two new
      tests.
- [ ] `refreshStatus()` no longer contains the literal strings "Nudges snoozed"
      (without "·") or "Nudges paused for".
- [ ] The snooze/pause branches derive remaining time from `lastReadingAt`, not
      a fresh `Date()` (the `?? Date()` fallback only applies when
      `lastReadingAt` is nil).

## Test plan

- `testSnoozeStatusCountsDownFromReadingClock` — asserts the snooze status string
  reflects remaining minutes from the reading clock ("· 8 min left" after 120 s
  of a 600 s snooze).
- `testPauseStatusCountsDownFromReadingClock` — asserts the auto-pause status
  string shows remaining minutes in the same "· N min left" format.
- Updated `testThreeBadPostureNudgesPauseRemindersForTenMinutes` and the snooze
  test continue to pass with the new strings.

## End-to-end verification

`statusText` is the exact string the popover renders (`MenuBarView.swift` shows
`Text(viewModel.statusText)`), so asserting `viewModel.statusText` in the unit
tests above verifies the shipped artifact. After `make test` passes, paste the
relevant test output in the completion Update Log. No separate runtime step is
required.

## Authorizations

None.

## Out of scope

- Do **not** add a new `@Published` property or change `MenuBarView.swift`.
- Do **not** add a countdown to the Snooze/Resume menu buttons.
- Do **not** change snooze/pause semantics (when they set or clear) — only the
  status string.
- Do **not** introduce second-level granularity or a timer; the string updates
  on each motion reading via the existing `refreshStatus()` call.

## Update Log

(Filled in by the executor. See WORKFLOW.md § "Update Log entries".)

<!-- entries appended below this line -->

### Update — 2026-06-30 (complete)

**Summary:** Implemented the snooze/auto-pause countdown. `refreshStatus()` now
renders "Nudges snoozed · N min left" / "Nudges paused · N min left" with N
derived from the reading clock (`lastReadingAt`) via a new `minutesLeft(until:)`
helper. The two existing status assertions were updated to the new strings and
two countdown tests were added (hermetic, with `FakeMicrophoneMonitor` injected).
No deviations from the spec.

**Executor:** Claude Code (direct). The qwen3.6:35b-mlx executor was dispatched
twice and hard-failed both times (run 1: inserted a literal `...` then
`IdenticalToolCallRepetition` after 59 turns; run 2, with a whole-function-replace
spec: no edit, `StuckGateFeedback` after 26 turns). Per the project owner's
decision, the phase was implemented directly rather than continuing to retry the
local model.

**Acceptance criteria:** all met.

**Commands:**

```
make build  → Build complete!
make lint   → clean (no violations)
make test   → Executed 66 tests, with 0 failures
```

**End-to-end verification:** `statusText` is the exact string the popover renders
(`MenuBarView` `Text(viewModel.statusText)`); the two new tests assert it
directly ("Nudges snoozed · 8 min left", "Nudges paused · 8 min left").

**Files changed:**
- `Sources/NoSlouch/PostureViewModel.swift` — countdown branches + `minutesLeft` helper.
- `Tests/NoSlouchTests/PostureViewModelTests.swift` — 2 updated assertions, 2 new tests.

**New tests:**
- `testSnoozeStatusCountsDownFromReadingClock`
- `testPauseStatusCountsDownFromReadingClock`
