# Cleanup & Feature Ideas

Tracking doc from the 2026-06-30 repo review. Two parts: (1) file-placement
cleanup to run now, (2) a prioritized feature backlog to pull from later.

Check items off as they land. Link a PR next to each when done.

---

## Part 1 — File placement cleanup

Context: the real git repo is the nested `NoSlouch/NoSlouch/` folder. The outer
`~/Desktop/NoSlouch/` is just the opened workspace and has accumulated clutter
that is not part of the project.

### Outer level (delete — not part of the repo)

- [x] Delete `New changes/` — stale export folder; its `Sources/`, `Tests/`,
      and `improvements.md` are byte-identical to what PR #16 already committed.
      Its own `FILE_PLACEMENT.md` references another machine's paths
      (`nbangalorevenugo`), confirming it is a leftover. Only real diffs are
      `.DS_Store` junk.
- [x] Delete outer `rexymcp.toml` — byte-identical duplicate of
      `NoSlouch/rexymcp.toml`.
- [x] Delete outer `.DS_Store`.
- [ ] (Optional) Reopen the workspace at `NoSlouch/NoSlouch/` so the orphaned
      outer `.claude/`, `.vscode/`, and `.remember/` tooling dirs live with the
      repo instead of the parent folder.

### Inside the repo (`NoSlouch/NoSlouch/`)

- [x] `git mv improvements.md docs/dev/improvements.md` — 95 KB planning doc,
      previously tracked at repo root; now with the other `docs/dev/` docs.
- [x] `git mv suggestion.md docs/dev/suggestion.md` — same reasoning.
- [x] Prune stale entries from `suggestion.md`: removed the AirPods battery
      monitor, auto-drift self-calibration, and snooze/pause countdown items
      (all shipped in PR #14/#16), and updated the heatmap note now that hourly
      buckets exist.

Note: `.DS_Store`, `.build/`, `.superpowers/`, `.rexymcp/`, `.vscode/` are all
already gitignored and untracked — nothing to do there.

---

## Part 2 — Feature backlog

Grounded in what already exists: slouch + tilt detection, calibration,
break/eye/hydration/movement reminders, quiet hours, mute-in-meetings,
away-pause, auto-drift, streaks/grades/achievements, weekly digest, CSV export,
battery widget.

### High value, low friction (plumbing already exists)

- [ ] **Intraday hourly heatmap.** `PostureHistoryStore` now retains hourly
      buckets (per `CLAUDE.md`), so the data exists; only a `HistoryView`
      heatmap (hour x day grid) remains — surfaces the afternoon fatigue dip.
- [ ] **Launch at login** via `SMAppService`, with a Settings toggle. Confirm
      it is not already present first. Table-stakes for a menu-bar app.
- [ ] **Surface `WeeklyDigest`.** The type exists but is not delivered anywhere;
      wire it to a weekly notification or a popover card.

### Ecosystem integration

- [ ] **App Intents / Shortcuts + Focus filters.** Expose "Start/Stop
      monitoring", "Calibrate now", "Today's upright %" as Shortcuts actions;
      auto-suppress nudges when a macOS Focus is active (extends the existing
      quiet-hours / mute-in-meetings suppression logic).
- [ ] **HealthKit logging** (Mindful / Stand) so posture sessions appear
      alongside Apple Watch stand data.

### Detection depth

- [ ] **Time-of-day adaptive sensitivity.** Auto-loosen the threshold later in
      the day using the hourly buckets now retained.
- [ ] **Sit/stand desk awareness.** Detect the pitch-baseline shift when
      standing to avoid false slouch alerts; optionally nudge to alternate.

### Distribution

- [ ] **Auto-update (Sparkle)** so releases reach users without a manual
      re-download.

---

## Next step

Before building any Part 2 item, run a proper brainstorm on it first
(requirements, edge cases, and which of the two `AppSettings` mutation tiers any
new setting belongs to — see `CLAUDE.md`).
