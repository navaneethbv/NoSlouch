# Phase 03: Intraday Posture Heatmap / Hourly Breakdown

**Milestone:** M7 — Pending Suggestions
**Status:** done
**Depends on:** Phase 02
**Estimated diff:** ~150 lines
**Tags:** language=swift, kind=feature, size=m

## Goal

Introduce hourly posture statistics tracking and display them in the History window as an interactive hourly breakdown slouch activity chart.

## Spec

### 1. Data Layer (`PostureHistoryStore.swift`)
- Define `HourPostureStat` struct.
- Save and load hourly stats using the `posture.history.hourlyStats` defaults key.
- Provide a legacy migration path converting existing `DayPostureStat`s to start-of-day hourly stats.
- Keep the `stats: [DayPostureStat]` property updated dynamically by aggregating hourly stats by day.
- Maintain history up to the 90 most recent unique days of stats.

### 2. View Model Layer (`PostureViewModel.swift`)
- Expose `@Published private(set) var hourlyStats: [HourPostureStat]`.
- Sync the array in `init()` and `finalizeSession()`.

### 3. UI Layer (`HistoryView.swift`)
- Add `@State private var selectedDay: Date?` tracking.
- Turn day list rows into interactive buttons highlighting the selected day.
- Render a secondary bar chart for hourly slouch events of the selected day.
- Increase window dimensions to `460 x 520`.
