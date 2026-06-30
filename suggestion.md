# NoSlouch: Pending Suggestions

Outstanding improvements only. Implemented items have been removed.

> **Shipped & removed from this list:** `AirPodsMotionProvider` data-race fix, `AudioOutputMonitor` CoreAudio memory-safety fix, dynamic notification-auth refresh, persisted calibration baseline (PR #11); mute-in-meetings, stretch-break reminders (incl. mute during meetings), visual posture-deviation gauge, gradient live chart, and session-stat cards (PR #12).

---

## 1. Architecture

### 🧵 Callback Thread Safety (optional, taste)

The closures on `HeadMotionProvider` (`onReading`, `onConnectionChanged`, `onError`) are set on the main thread but invoked from background threads inside `AirPodsMotionProvider`. The ViewModel re-dispatches them to main, so there is no live bug; this is a consistency cleanup.

*   `AirPodsMotionProvider` is already half-consistent: `onError` is wrapped in `DispatchQueue.main.async` but `onReading` and `onConnectionChanged` are not. Consolidating all three onto the main queue (matching `AudioOutputMonitor` / `MicrophoneMonitor`, which already run their listeners on `DispatchQueue.main`) is the cleaner end state.

---

## 2. UI/UX

### ⏳ Active Snooze / Pause Countdown

Snooze (`snoozeNudges`/`resumeNudges`) and the auto-pause both work, but the popover only shows static text ("Nudges snoozed" / a "Resume nudges" button) with no remaining time.

*   **Implementation**: Surface a live countdown (e.g. `Nudges snoozed · 12 min left`). Drive it off the same reading clock (`lastReadingAt`) that snooze expiry uses, not wall-clock, so the displayed remaining time matches when nudges actually resume.

---

## 3. New Functionality

### 📈 Posture Heatmap / Fatigue Analysis (intraday)

`HistoryView` already ships a 30-day **daily** upright bar chart plus per-day rows. The remaining idea is an **intraday** breakdown of slouch events through the day.

*   **Implementation**: A GitHub-style hourly heatmap (or hour-bucketed bar chart) so users can see when posture degrades (e.g. fatigue peaking at 3:00 PM) and schedule breaks accordingly.
*   **Scope note**: Not a view-only change. `PostureHistoryStore` aggregates each session into a **daily** bucket (`DayPostureStat`), so there is no hourly data to plot. The data model must first retain finer-grained (hourly) buckets before the intraday heatmap is possible.

### 🔋 AirPods Battery Monitor

Since NoSlouch requires AirPods, a tiny battery widget (Left, Right, Case) in the menu-bar popover would be useful.

*   **Implementation**: Use `IOKit` or the private `BluetoothManager` framework to read AirPods battery percentages.
*   **Risk note**: This breaks the app's current dependency-free, public-API-only stance. The `BluetoothManager` framework is private (brittle across OS versions, distribution/notarization risk), and there is no supported public API for AirPods battery. Treat as higher-risk and lower-priority than its size suggests.

### 🔄 Auto-Drift Detection (Self-Calibration)

Over a long session a user may sink into their chair, or the AirPods may shift, drifting the pitch baseline.

*   **Implementation**: If the pitch stabilizes at a slightly different value for a sustained period without slouch events, suggest an auto-recalibration, or adjust the baseline with a very slow-moving average filter.
*   **Safety note**: A silent slow-moving average is dangerous, it can drift the baseline toward a slouched posture and mask real slouching, defeating the app. Prefer the "suggest a recalibration" variant. If adapting automatically, only adapt while posture is already classified good and bound the total cumulative drift.
