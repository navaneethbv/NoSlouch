# Improvements and future ideas

The current implementation and acceptance status live in [NEXT.md](NEXT.md) and [M14](milestones/M14-tracking-recovery/README.md).

## Implemented

- Opt-in startup monitoring, explicit test notifications, and dismissible recovery notices.
- Accurate measured-hour attribution and midnight-safe live totals.
- Sensor-gap handling, connection diagnostics, and safe guided calibration.
- Crash checkpoints, duplicate-safe recovery, history deletion, and calendar-day retention.
- Opt-in resume after interruption, named calibration profiles, and minimum-duration goals.
- Reminder scheduling separated from the coordinator and explicit clocks for tests.
- Optimized hardened-runtime release packaging and a manual update entry point.
- Earlier features: launch at login, heatmaps, weekly digest, reminders, snooze, export, and onboarding.

## Future decisions

- Background auto-update requires selecting and reviewing an update framework and signed update feed.
- Native Shortcuts actions and Focus integration require a separately validated platform design.
- Automatic sit/stand classification and adaptive sensitivity need sensor evidence before changing detection behavior.

Real-device and signed-release acceptance are tracked as verification gates, not as implemented features.
