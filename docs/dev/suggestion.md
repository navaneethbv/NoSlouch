# NoSlouch: Pending Suggestions

Outstanding improvements only. Implemented items have been removed.

> **Shipped & removed from this list:** `AirPodsMotionProvider` data-race fix, `AudioOutputMonitor` CoreAudio memory-safety fix, dynamic notification-auth refresh, persisted calibration baseline (PR #11); mute-in-meetings, stretch-break reminders (incl. mute during meetings), visual posture-deviation gauge, gradient live chart, and session-stat cards (PR #12); active snooze/pause countdown (PR #14); AirPods battery monitor widget and safe auto-drift baseline self-calibration (PR #16).

---

## 1. Architecture

### 🧵 Callback Thread Safety (optional, taste)

The closures on `HeadMotionProvider` (`onReading`, `onConnectionChanged`, `onError`) are set on the main thread but invoked from background threads inside `AirPodsMotionProvider`. The ViewModel re-dispatches them to main, so there is no live bug; this is a consistency cleanup.

*   `AirPodsMotionProvider` is already half-consistent: `onError` is wrapped in `DispatchQueue.main.async` but `onReading` and `onConnectionChanged` are not. Consolidating all three onto the main queue (matching `AudioOutputMonitor` / `MicrophoneMonitor`, which already run their listeners on `DispatchQueue.main`) is the cleaner end state.

---

## 2. New Functionality

### 📈 Posture Heatmap / Fatigue Analysis (intraday)

`HistoryView` already ships a 30-day **daily** upright bar chart plus per-day rows. The remaining idea is an **intraday** breakdown of slouch events through the day.

*   **Implementation**: A GitHub-style hourly heatmap (or hour-bucketed bar chart) so users can see when posture degrades (e.g. fatigue peaking at 3:00 PM) and schedule breaks accordingly.
*   **Scope note**: `PostureHistoryStore` now retains hourly buckets, so the data exists — this is now a view-layer change in `HistoryView` (no data-model work required).
