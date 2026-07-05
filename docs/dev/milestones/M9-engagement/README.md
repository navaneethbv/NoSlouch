# M9 — Engagement & Insight

**Status:** phase-01 complete as LOCAL, UNCOMMITTED working-tree changes (per
the principal engineer's instruction: no commits; changes are also mirrored to
the workspace's `New changes/` folder).

Builds the insight surface on top of M8's now-trustworthy data.

| Phase | Scope | Status |
|---|---|---|
| phase-01 | C4 trends, C1 heatmap grid, J2 digest notification, B3 banner actions, G4 NaN guard, settings-tier lockdown | complete (uncommitted) |

## Shipped in phase-01

- **C4 — Day/Week/Month trends.** New pure `TrendAggregator`
  (`Sources/NoSlouch/Persistence/TrendAggregator.swift`) rolls `DayPostureStat`
  into day/week/month `TrendPoint`s; `HistoryView` gains a segmented control
  driving the upright-share chart (day = last 30 days; week/month = full
  retained history).
- **C1 — hour×day heatmap.** 7-day × 24-hour grid in `HistoryView` colored by
  upright fraction — sequential single-hue ramp (darker green = more upright),
  neutral gray for no-data, per-cell tooltips with exact %/minutes/slouches so
  color is never the only channel.
- **J2 — weekly digest notification.** `lastWeeklyDigestDate` persisted in
  `AppSettings`; `PostureViewModel.maybeSendWeeklyDigest()` fires a passive
  notification at most once per 7 days (checked after authorization refresh and
  on session finalize). First activation anchors without firing; the date is
  only consumed when notifications are actually enabled.
- **B3 — banner actions.** "Snooze 15 min" / "Recalibrate" buttons on the
  posture nudge (`UNNotificationCategory`), routed through
  `PostureNotifying.onAction` back into `snoozeNudges`/`calibrateAveraged`.
  Needs a real-bundle manual pass for end-to-end delivery (ad-hoc dev builds
  may not show actions).
- **G4 — engine robustness.** `SlouchEngine.update` ignores non-finite
  pitch/roll samples.
- **Quality.** `@Published private(set) var settings` (mutations must go
  through the tier-aware update methods); paused/digest notifications use
  `.passive` interruption level; the deviation gauge's magic `30.0` is now a
  named constant.

## Verification (2026-07-04)

`make lint` exit 0; zero build warnings; **146 tests, 0 failures** (was 135;
+11: TrendAggregator ×5, engine NaN ×1, digest ×3, banner actions ×2), run via
`--scratch-path /tmp/noslouch-scratch` (the iCloud-synced default `.build`
intermittently corrupts `build.db` and reuses stale binaries).
