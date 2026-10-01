# NoSlouch architecture

NoSlouch is a dependency-free Swift macOS 14+ menu-bar app.
Apple frameworks provide motion, audio-device status, notifications, login registration, and native UI.

## Input and coordination

`HeadMotionProvider` exposes headphone availability, motion authorization, readings, and connection events.
`AirPodsMotionProvider` throttles sensor delivery on a serial queue and rejects callbacks from stopped generations before publishing them on main.
Audio-output, microphone, activity, and battery monitors remain injectable behind protocols.

`PostureViewModel` coordinates inputs and owns observable UI state on the main thread.
Its clock, calendar, sampling-gap policy, and heartbeat are injectable for deterministic tests.
Production accepts a maximum two-second gap between readings.
A missing stream stops measured accounting, invalidates calibration availability, and resets detector hold/recovery state.
An explicit Stop always cancels automatic resume.
Resume after reconnect or system wake is opt-in and only follows an interrupted monitoring request.
A separate startup preference waits for supported headphones after onboarding completes.
Pending startup has a visible cancellation action; explicit Stop cancels it for the current launch.

## Detection, calibration, and scheduling

`SlouchEngine` is a pure pitch/roll classifier with smoothing, hold, recovery, and a calibrated baseline.
Guided calibration requires at least 15 stable readings over three seconds with no gap over two seconds.
Pitch and roll must each remain within a three-degree range.
The attempt times out after eight seconds without adequate input.
Named calibration profiles are stored locally and preserve the original calibration date when restored.

`ReminderScheduler` tracks monitored-time intervals and a two-minute minimum gap between wellness reminders.
Meetings, quiet hours, and snooze defer reminders without consuming them.
Posture nudge cooldown and automatic pauses stay in the coordinator.
Notification banners request no system sound; selected sound and speech are emitted once according to settings.
The explicit test-notification action refreshes authorization and reports the scheduling result without changing posture state or cooldowns.
Test notifications have their own identifier and no posture-action category.
Submission does not guarantee a banner when system Focus or notification settings suppress presentation.

## Measured history and recovery

`SessionAccumulator` attributes only accepted good/bad intervals to actual calendar hours.
Unknown, away, and missing-sensor time is excluded.
Slouch events are assigned to their actual event hour.
Repeated daylight-saving hours retain distinct absolute timestamps.
The first measured hour counts the session once.

`PostureHistoryStore` stores committed and pending hourly buckets in one versioned snapshot.
The app uses `~/Library/Application Support/NoSlouch/history-v2.json`, atomically replaced at a checkpoint and at session finalization.
Checkpoints occur every 15 seconds during monitoring, with additional writes at interruptions.
A crash can lose time since the latest successful checkpoint.
On restart, pending buckets become committed in the same snapshot write, preventing duplicate recovery.
Write and read failures are surfaced in the UI.
A dismissible recovery notice appears after pending data is recovered.
Tests can inject a file URL or use isolated UserDefaults snapshots.

Daily and hourly UserDefaults mirrors preserve compatibility for an older app version.
The canonical snapshot is authoritative in this version.
Legacy daily/hourly data migrates without inventing exact interval attribution for historical estimates.
Clear History removes active data, canonical data, compatibility mirrors, and corruption backups while retaining settings and profiles.
Retention means today and the preceding 89 calendar days, enforced on load and during app operation.

Live scores, history, and CSV export use the same combined committed/active view.
Goals, daily grades, and sustained-day achievements require 20 measured minutes by default, configurable in Settings.

## UI and distribution

The menu popover provides monitoring, diagnostics, calibration, and navigation.
Settings, onboarding, history, and About use native SwiftUI windows.
The About window links to manual release downloads; there is no background update service or added dependency.

Development uses an ad-hoc bundle.
Release packaging uses an optimized build, hardened runtime, and Developer ID signing with a secure timestamp when a signing identity is supplied.
See [the release runbook](dev/RELEASE.md) for notarization and hardware acceptance.
There is no cloud sync or posture-data telemetry.
